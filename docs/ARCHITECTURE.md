# Architecture & Technical Details

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Workspace                          │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Gmail   │  │  Drive   │  │   Docs   │  │  Sheets  │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │             │              │              │          │
│       └─────────────┴──────────────┴──────────────┘          │
│                         │                                    │
│                    HTTPS (TLS 1.3)                          │
│                    KACLS Protocol                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Wrap/Unwrap Requests
                         │ (JWT Authentication)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│               Your Key Service (Oracle Cloud VM)            │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                   nginx (Port 443)                     │ │
│  │  - TLS termination (Let's Encrypt SSL)                │ │
│  │  - Request routing                                     │ │
│  │  - Security headers                                    │ │
│  │  - Rate limiting                                       │ │
│  └──────────────────────┬─────────────────────────────────┘ │
│                         │                                    │
│                         │ HTTP                               │
│                         ▼                                    │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              Node.js Express App (Port 3000)          │ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐│ │
│  │  │  Authentication Middleware                        ││ │
│  │  │  - Verify Google JWT tokens                       ││ │
│  │  │  - Extract user info (email, domain)              ││ │
│  │  │  - Domain whitelist check                         ││ │
│  │  └──────────────────────────────────────────────────┘│ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐│ │
│  │  │  API Endpoints                                    ││ │
│  │  │  - POST /v1/wrappedKeys:wrap                      ││ │
│  │  │  - POST /v1/wrappedKeys:unwrap                    ││ │
│  │  │  - GET  /healthz                                  ││ │
│  │  │  - GET  /v1/audit/logs (admin)                    ││ │
│  │  └──────────────────────────────────────────────────┘│ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐│ │
│  │  │  Crypto Module (AES-KW RFC 3394)                  ││ │
│  │  │  - Key wrapping (AES-256-KW)                      ││ │
│  │  │  - Key unwrapping                                 ││ │
│  │  │  - Hardware-accelerated (ARM AES)                 ││ │
│  │  └──────────────────────────────────────────────────┘│ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐│ │
│  │  │  Database (SQLite)                                ││ │
│  │  │  - KEK metadata storage                           ││ │
│  │  │  - Audit log persistence                          ││ │
│  │  │  - WAL mode for performance                       ││ │
│  │  └──────────────────────────────────────────────────┘│ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  File System:                                                │
│  - /opt/cse-key-service/app/data/keys.db (database)         │
│  - /opt/cse-key-service/app/.env (Master KEK)               │
│  - /opt/cse-key-service/app/logs/ (audit logs)              │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Encryption Flow (Wrap)

```
1. User creates new encrypted document in Google Docs
   ┌──────────────┐
   │ Google Docs  │
   └──────┬───────┘
          │
          │ 1a. Generate random 256-bit DEK
          │     (Data Encryption Key)
          │
          ▼
   ┌────────────────────────────────┐
   │ DEK = random_bytes(32)         │
   │ e.g., "x7k2m9p4r1..."          │
   └───────┬────────────────────────┘
           │
           │ 1b. Encrypt document content with DEK
           │     (AES-256-GCM)
           │
           ▼
   ┌────────────────────────────────┐
   │ Encrypted Content              │
   │ (stored in Google's servers)   │
   └────────────────────────────────┘
           │
           │ 2. Send DEK to key service for wrapping
           │
           ▼
   POST /v1/wrappedKeys:wrap
   {
     "key": "eN2TTNm9cDJyNHIx...",  (base64 DEK)
     "authentication": {
       "credentials": "eyJhbGc..."     (JWT token)
     },
     "reason": "ENCRYPT_DOCUMENT"
   }
           │
           │ 3. Your service receives request
           │
           ▼
   ┌─────────────────────────────────┐
   │ Authentication Verification     │
   │ - Decode JWT                     │
   │ - Verify signature               │
   │ - Check domain                   │
   │ - Extract user email             │
   └───────┬─────────────────────────┘
           │
           │ 4. Wrap DEK with your KEK
           │
           ▼
   ┌─────────────────────────────────┐
   │ AES-KW Key Wrapping              │
   │                                  │
   │ Input:  DEK (32 bytes)           │
   │         KEK (32 bytes, your key) │
   │                                  │
   │ Algorithm: AES-256-KW (RFC 3394) │
   │                                  │
   │ Output: Wrapped DEK (40 bytes)   │
   └───────┬─────────────────────────┘
           │
           │ 5. Log operation
           │
           ▼
   ┌─────────────────────────────────┐
   │ Audit Database                   │
   │ - Timestamp                      │
   │ - Operation: WRAP                │
   │ - User: user@domain.com          │
   │ - Key ID: kek_default_v1         │
   │ - Success: true                  │
   └─────────────────────────────────┘
           │
           │ 6. Return wrapped DEK
           │
           ▼
   Response:
   {
     "wrappedKey": "z8j3k1m2n4...",  (base64)
     "keyId": "kek_default_v1",
     "timestamp": "2024-11-03T..."
   }
           │
           │ 7. Google stores wrapped DEK
           │    with encrypted content
           │
           ▼
   ┌─────────────────────────────────┐
   │ Google Storage                   │
   │ - Encrypted content (with DEK)   │
   │ - Wrapped DEK (encrypted with    │
   │   your KEK, Google can't decrypt)│
   │ - Metadata                       │
   └─────────────────────────────────┘
```

### Decryption Flow (Unwrap)

```
1. User opens encrypted document
   ┌──────────────┐
   │ Google Docs  │
   └──────┬───────┘
          │
          │ 1a. Retrieve encrypted content
          │     and wrapped DEK from storage
          │
          ▼
   ┌────────────────────────────────┐
   │ Wrapped DEK: "z8j3k1m2n4..."   │
   │ Encrypted Content              │
   └───────┬────────────────────────┘
           │
           │ 2. Send wrapped DEK to key service
           │
           ▼
   POST /v1/wrappedKeys:unwrap
   {
     "wrappedKey": "z8j3k1m2n4...",
     "keyId": "kek_default_v1",
     "authentication": {
       "credentials": "eyJhbGc..."
     },
     "reason": "DECRYPT_DOCUMENT"
   }
           │
           │ 3. Your service authenticates user
           │
           ▼
   ┌─────────────────────────────────┐
   │ Authentication & Authorization  │
   │ - Verify JWT token               │
   │ - Check user permissions         │
   │ - Validate key ID exists         │
   └───────┬─────────────────────────┘
           │
           │ 4. Unwrap DEK
           │
           ▼
   ┌─────────────────────────────────┐
   │ AES-KW Key Unwrapping            │
   │                                  │
   │ Input:  Wrapped DEK (40 bytes)   │
   │         KEK (32 bytes, your key) │
   │                                  │
   │ Algorithm: AES-256-Unwrap        │
   │                                  │
   │ Output: DEK (32 bytes)           │
   │         OR error if KEK wrong    │
   └───────┬─────────────────────────┘
           │
           │ 5. Log operation
           │
           ▼
   ┌─────────────────────────────────┐
   │ Audit Database                   │
   │ - Timestamp                      │
   │ - Operation: UNWRAP              │
   │ - User: user@domain.com          │
   │ - Key ID: kek_default_v1         │
   │ - Success: true                  │
   └─────────────────────────────────┘
           │
           │ 6. Return unwrapped DEK
           │
           ▼
   Response:
   {
     "key": "eN2TTNm9cDJyNHIx...",  (base64 DEK)
     "timestamp": "2024-11-03T..."
   }
           │
           │ 7. Google decrypts content with DEK
           │
           ▼
   ┌─────────────────────────────────┐
   │ Decrypt Content                  │
   │ - Use DEK to decrypt             │
   │ - Render document to user        │
   └─────────────────────────────────┘
           │
           │ 8. User sees decrypted document
           │
           ▼
   ┌──────────────┐
   │ Google Docs  │  
   │ (decrypted)  │
   └──────────────┘
```

## Key Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│                    Master KEK                           │
│                 (256-bit AES key)                       │
│                                                          │
│  - Stored in .env file on your server                   │
│  - Never transmitted                                    │
│  - Never leaves your server                             │
│  - BACKUP SECURELY OFFLINE                              │
│                                                          │
│  Purpose: Wraps/unwraps all DEKs                        │
└───────────────────┬─────────────────────────────────────┘
                    │
                    │ Wraps/Unwraps
                    ▼
┌─────────────────────────────────────────────────────────┐
│              Data Encryption Keys (DEKs)                │
│                 (256-bit AES keys)                      │
│                                                          │
│  - Generated by Google Workspace                        │
│  - One per encrypted document/email                     │
│  - Wrapped by your KEK before storage                   │
│  - Google stores wrapped version only                   │
│                                                          │
│  Purpose: Encrypt individual documents/emails           │
└───────────────────┬─────────────────────────────────────┘
                    │
                    │ Encrypts/Decrypts
                    ▼
┌─────────────────────────────────────────────────────────┐
│                 Document Content                        │
│                                                          │
│  - Your actual Google Docs/Sheets/emails                │
│  - Encrypted with DEK (AES-256-GCM)                     │
│  - Stored in Google's infrastructure                    │
│                                                          │
│  Security: Two layers of encryption                     │
│  1. DEK encrypts content (Google has wrapped DEK)       │
│  2. KEK encrypts DEK (only you have KEK)                │
└─────────────────────────────────────────────────────────┘
```

## Security Model

### What Google Knows

```
✅ Google can see:
   - Document metadata (title, author, timestamps)
   - Wrapped DEK (but cannot unwrap it)
   - Encrypted content (but cannot decrypt it)
   - Access patterns (who accessed when)

❌ Google CANNOT:
   - Decrypt wrapped DEKs (no access to your KEK)
   - Read document content
   - Access your encryption keys
   - Decrypt even if legally compelled
```

### What Your Key Service Controls

```
✅ Your service controls:
   - Who can encrypt (wrap DEKs)
   - Who can decrypt (unwrap DEKs)
   - Access policies
   - Audit trail
   - Key rotation

⚠️ Your service is responsible for:
   - Authenticating users
   - Verifying permissions
   - Protecting KEK
   - Maintaining uptime
   - Backup & recovery
```

### Threat Model

**Protected Against:**
✅ Google insider access to content  
✅ Government data requests to Google  
✅ Google server compromise  
✅ Google database breaches  
✅ Man-in-the-middle (TLS encryption)  
✅ Unauthorized access (authentication)  

**NOT Protected Against:**
❌ Loss of your KEK (data unrecoverable)  
❌ Compromise of your key service  
❌ Malware on user's device  
❌ Authorized user accessing content  
❌ Your key service downtime (content inaccessible)  

## Technical Specifications

### Cryptographic Algorithms

| Operation | Algorithm | Key Size | Standard |
|-----------|-----------|----------|----------|
| Key Wrapping | AES-KW | 256-bit | RFC 3394 |
| KEK Storage | AES-256-GCM | 256-bit | NIST |
| Transport | TLS 1.2/1.3 | 2048-bit RSA or ECDHE | RFC 8446 |
| Authentication | JWT (RS256) | 2048-bit RSA | RFC 7519 |
| Content Encryption (by Google) | AES-GCM | 256-bit | NIST |

### Performance Characteristics

**Oracle A1 (4 ARM CPUs):**
- Single wrap operation: 0.3-0.5ms
- Single unwrap operation: 0.3-0.5ms
- Throughput: 5,000-10,000 ops/sec
- Concurrent users: 1,000+ simultaneous
- Memory footprint: ~100-500 MB
- Storage growth: ~200 bytes/operation (audit log)

### API Specifications

#### Wrap Endpoint

```
POST /v1/wrappedKeys:wrap
Content-Type: application/json

Request:
{
  "key": "base64-encoded-32-byte-dek",
  "authentication": {
    "type": "GOOGLE_WORKSPACE",
    "credentials": "jwt-token"
  },
  "reason": "ENCRYPT_DOCUMENT" | "ENCRYPT_EMAIL" | etc.
}

Response (200 OK):
{
  "wrappedKey": "base64-encoded-40-byte-wrapped-key",
  "keyId": "kek_identifier",
  "timestamp": "ISO-8601-timestamp"
}

Errors:
- 400: Invalid request (missing fields, invalid key size)
- 401: Authentication failed
- 500: Wrap operation failed
```

#### Unwrap Endpoint

```
POST /v1/wrappedKeys:unwrap
Content-Type: application/json

Request:
{
  "wrappedKey": "base64-encoded-wrapped-key",
  "keyId": "kek_identifier",
  "authentication": {
    "type": "GOOGLE_WORKSPACE",
    "credentials": "jwt-token"
  },
  "reason": "DECRYPT_DOCUMENT" | "DECRYPT_EMAIL" | etc.
}

Response (200 OK):
{
  "key": "base64-encoded-32-byte-dek",
  "timestamp": "ISO-8601-timestamp"
}

Errors:
- 400: Invalid request
- 401: Authentication failed
- 404: KEK not found
- 500: Unwrap operation failed (wrong key, corrupted data)
```

## Database Schema

### KEKs Table

```sql
CREATE TABLE keks (
  key_id TEXT PRIMARY KEY,           -- e.g., "kek_default_v1"
  created_at INTEGER NOT NULL,       -- Unix timestamp
  algorithm TEXT NOT NULL,           -- "AES-256-KW"
  status TEXT NOT NULL,              -- "ACTIVE" | "ROTATED"
  metadata TEXT                      -- JSON: {"description": "...", ...}
);
```

### Audit Log Table

```sql
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,         -- Unix timestamp
  operation TEXT NOT NULL,            -- "WRAP" | "UNWRAP"
  key_id TEXT,                        -- KEK used
  user_email TEXT,                    -- user@domain.com
  user_domain TEXT,                   -- domain.com
  reason TEXT,                        -- "ENCRYPT_DOCUMENT", etc.
  success INTEGER NOT NULL,           -- 1 = success, 0 = failure
  error TEXT,                         -- Error message if failed
  ip_address TEXT,                    -- Client IP
  request_id TEXT                     -- Unique request ID
);

CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX idx_audit_user ON audit_log(user_email);
CREATE INDEX idx_audit_operation ON audit_log(operation);
```

## Deployment Architecture

### Oracle Cloud Infrastructure

```
Oracle Cloud (Always Free Tier)
└── Region (e.g., us-ashburn-1)
    └── Availability Domain
        └── VM.Standard.A1.Flex
            ├── Compute
            │   ├── 4 OCPUs (Ampere Altra ARM)
            │   ├── 24 GB RAM
            │   └── Ubuntu 22.04 LTS
            ├── Storage
            │   └── 200 GB Block Volume
            └── Network
                ├── Public IP (reserved)
                ├── VCN (Virtual Cloud Network)
                ├── Security List
                │   ├── Ingress: TCP 22 (SSH)
                │   └── Ingress: TCP 443 (HTTPS)
                └── Firewall (iptables)
```

### Network Flow

```
Internet
   │
   │ Port 443 (HTTPS)
   ▼
[Oracle Cloud Firewall]
   │
   ▼
[VM iptables]
   │
   ▼
[nginx] Port 443
   │
   │ TLS Termination
   │ SSL Certificate (Let's Encrypt)
   │
   ▼
[nginx reverse proxy]
   │
   │ HTTP (localhost only)
   │
   ▼
[Node.js Express] Port 3000
   │
   ├──▶ [Authentication Middleware]
   ├──▶ [KACLS Endpoints]
   ├──▶ [Crypto Module]
   └──▶ [SQLite Database]
```

## Scalability & High Availability

### Scaling Options

**Vertical Scaling (single instance):**
- Oracle A1 Free Tier: 4 CPUs, 24 GB RAM
- Handles: ~5,000-10,000 ops/sec
- Sufficient for: Up to 1,000-5,000 users

**Horizontal Scaling (if needed):**
- Load balancer (nginx or Oracle LB)
- Multiple Node.js instances
- Shared database (PostgreSQL/MySQL)
- Session affinity not required (stateless)

**High Availability (advanced):**
- Multiple VMs in different availability domains
- Replicated database
- Health checks & automatic failover
- Cost: Requires paid resources

For most use cases, a single Always Free instance is sufficient.

## Monitoring & Operations

### Health Checks

```
GET /healthz

Response:
{
  "status": "healthy",
  "timestamp": "2024-11-03T12:34:56.789Z",
  "version": "1.0.0"
}
```

### Metrics to Monitor

- Wrap/unwrap operation latency
- Success/failure rates
- Authentication failures
- Database size growth
- CPU & memory usage
- Disk space
- Certificate expiry (Let's Encrypt)

### Logging

**Application logs:**
- stdout/stderr → journalctl
- /opt/cse-key-service/app/logs/app.log
- /opt/cse-key-service/app/logs/error.log

**Audit logs:**
- SQLite database (audit_log table)
- Queryable via API or SQL
- Retention: Configurable (default: unlimited)

**System logs:**
- /var/log/nginx/access.log
- /var/log/nginx/error.log
- journalctl -u cse-key-service

## Security Hardening Checklist

- [ ] TLS 1.2+ only (disable TLS 1.0/1.1)
- [ ] Strong ciphers (no RC4, 3DES, MD5)
- [ ] HSTS enabled
- [ ] Certificate auto-renewal (certbot)
- [ ] Firewall configured (only 22, 443)
- [ ] SSH key-based auth only (no passwords)
- [ ] Regular system updates
- [ ] Master KEK backed up offline
- [ ] Database encrypted at rest (optional)
- [ ] Audit logs monitored
- [ ] Rate limiting (optional)
- [ ] IP whitelisting (optional)
- [ ] Fail2ban for SSH (optional)
- [ ] Security headers (Helmet.js)
- [ ] Input validation on all endpoints
- [ ] Parameterized SQL queries
- [ ] No secrets in logs
- [ ] Service runs as non-root user
- [ ] File permissions (600 for .env, keys)

---

This architecture provides enterprise-grade security with minimal complexity and cost. The design prioritizes simplicity, security, and operational ease over unnecessary features.
