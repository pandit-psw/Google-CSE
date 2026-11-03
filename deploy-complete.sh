#!/bin/bash

################################################################################
# Google Workspace CSE Key Service - Complete Deployment Script
# Run this as ROOT on your Oracle VM
################################################################################

set -e  # Exit on error

DOMAIN="cse-keys.paxtontech.top"
EMAIL="admin@paxtontech.top"  # Change if needed
APP_DIR="/opt/cse-key-service"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Google Workspace CSE Key Service - Complete Deployment"
echo "  Domain: $DOMAIN"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
   echo "❌ Please run as root"
   exit 1
fi

# Step 1: Update system
echo "📋 Step 1/11: Updating system..."
apt update -y
DEBIAN_FRONTEND=noninteractive apt upgrade -y
echo "   ✓ System updated"

# Step 2: Install dependencies
echo ""
echo "📦 Step 2/11: Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt install -y \
    curl wget git build-essential python3 \
    nginx certbot python3-certbot-nginx \
    iptables-persistent
echo "   ✓ Dependencies installed"

# Step 3: Install Node.js
echo ""
echo "🟢 Step 3/11: Installing Node.js 20..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
fi
echo "   ✓ Node.js $(node --version) installed"
echo "   ✓ npm $(npm --version) installed"

# Step 4: Create user
echo ""
echo "👤 Step 4/11: Creating application user..."
if ! id -u cse &>/dev/null; then
    useradd -r -s /bin/bash -m -d $APP_DIR cse
    echo "   ✓ User 'cse' created"
else
    echo "   ✓ User 'cse' exists"
fi

# Step 5: Create directories
echo ""
echo "📁 Step 5/11: Creating directories..."
mkdir -p $APP_DIR/app/{src,data,logs}
mkdir -p $APP_DIR/backups
echo "   ✓ Directories created"

# Step 6: Deploy source files
echo ""
echo "📝 Step 6/11: Creating source files..."

# package.json
cat > $APP_DIR/app/package.json << 'EOF_PACKAGE'
{
  "name": "google-cse-key-service",
  "version": "1.0.0",
  "description": "Self-hosted external key service for Google Workspace CSE",
  "main": "src/server.js",
  "type": "module",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "google-auth-library": "^9.4.1",
    "better-sqlite3": "^9.2.2",
    "dotenv": "^16.3.1",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "uuid": "^9.0.1"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
EOF_PACKAGE
echo "   ✓ package.json created"

# src/crypto.js
cat > $APP_DIR/app/src/crypto.js << 'EOF_CRYPTO'
import crypto from 'crypto';

export class KeyWrapper {
  constructor(masterKek) {
    if (!masterKek || masterKek.length !== 32) {
      throw new Error('Master KEK must be 32 bytes (256 bits)');
    }
    this.masterKek = masterKek;
  }

  wrapKey(dek) {
    const cipher = crypto.createCipheriv('id-aes256-wrap', this.masterKek, null);
    const wrapped = Buffer.concat([cipher.update(dek), cipher.final()]);
    return wrapped;
  }

  unwrapKey(wrappedKey) {
    try {
      const decipher = crypto.createDecipheriv('id-aes256-wrap', this.masterKek, null);
      const unwrapped = Buffer.concat([decipher.update(wrappedKey), decipher.final()]);
      return unwrapped;
    } catch (error) {
      throw new Error('Failed to unwrap key: invalid wrapped key or KEK');
    }
  }

  static generateKek() {
    return crypto.randomBytes(32);
  }

  static generateDek() {
    return crypto.randomBytes(32);
  }
}

export const base64 = {
  encode: (buffer) => buffer.toString('base64'),
  decode: (str) => Buffer.from(str, 'base64')
};
EOF_CRYPTO
echo "   ✓ src/crypto.js created"

# src/database.js
cat > $APP_DIR/app/src/database.js << 'EOF_DATABASE'
import Database from 'better-sqlite3';
import { mkdir } from 'fs/promises';
import { dirname } from 'path';

export class KeyDatabase {
  constructor(dbPath) {
    this.dbPath = dbPath;
    this.db = null;
  }

  async initialize() {
    await mkdir(dirname(this.dbPath), { recursive: true });
    this.db = new Database(this.dbPath);
    this.db.pragma('journal_mode = WAL');
    this.createTables();
  }

  createTables() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS keks (
        key_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        algorithm TEXT NOT NULL DEFAULT 'AES-256-KW',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        metadata TEXT
      )
    `);

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        operation TEXT NOT NULL,
        key_id TEXT,
        user_email TEXT,
        user_domain TEXT,
        reason TEXT,
        success INTEGER NOT NULL,
        error TEXT,
        ip_address TEXT,
        request_id TEXT
      )
    `);

    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
      CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_email);
      CREATE INDEX IF NOT EXISTS idx_audit_operation ON audit_log(operation);
    `);
  }

  registerKek(keyId, metadata = {}) {
    const stmt = this.db.prepare(`
      INSERT INTO keks (key_id, created_at, metadata)
      VALUES (?, ?, ?)
    `);
    stmt.run(keyId, Date.now(), JSON.stringify(metadata));
  }

  getKek(keyId) {
    const stmt = this.db.prepare(`
      SELECT * FROM keks WHERE key_id = ? AND status = 'ACTIVE'
    `);
    return stmt.get(keyId);
  }

  listKeks() {
    const stmt = this.db.prepare(`
      SELECT * FROM keks WHERE status = 'ACTIVE' ORDER BY created_at DESC
    `);
    return stmt.all();
  }

  rotateKek(keyId) {
    const stmt = this.db.prepare(`
      UPDATE keks SET status = 'ROTATED' WHERE key_id = ?
    `);
    stmt.run(keyId);
  }

  logOperation(operation, details) {
    const stmt = this.db.prepare(`
      INSERT INTO audit_log (
        timestamp, operation, key_id, user_email, user_domain,
        reason, success, error, ip_address, request_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      Date.now(),
      operation,
      details.keyId || null,
      details.userEmail || null,
      details.userDomain || null,
      details.reason || null,
      details.success ? 1 : 0,
      details.error || null,
      details.ipAddress || null,
      details.requestId || null
    );
  }

  getAuditLogs(filter = {}) {
    let query = 'SELECT * FROM audit_log WHERE 1=1';
    const params = [];

    if (filter.userEmail) {
      query += ' AND user_email = ?';
      params.push(filter.userEmail);
    }

    if (filter.operation) {
      query += ' AND operation = ?';
      params.push(filter.operation);
    }

    if (filter.startTime) {
      query += ' AND timestamp >= ?';
      params.push(filter.startTime);
    }

    if (filter.endTime) {
      query += ' AND timestamp <= ?';
      params.push(filter.endTime);
    }

    query += ' ORDER BY timestamp DESC LIMIT ?';
    params.push(filter.limit || 100);

    const stmt = this.db.prepare(query);
    return stmt.all(...params);
  }

  close() {
    if (this.db) {
      this.db.close();
    }
  }
}
EOF_DATABASE
echo "   ✓ src/database.js created"

# src/auth.js
cat > $APP_DIR/app/src/auth.js << 'EOF_AUTH'
import { OAuth2Client } from 'google-auth-library';

export class AuthVerifier {
  constructor(config) {
    this.allowedDomain = config.allowedDomain;
    this.client = new OAuth2Client();
  }

  async verifyRequest(authData) {
    try {
      if (!authData || !authData.credentials) {
        throw new Error('Missing authentication credentials');
      }

      const token = this.extractToken(authData);

      if (!token) {
        throw new Error('No authentication token found');
      }

      const ticket = await this.client.verifyIdToken({
        idToken: token,
        audience: process.env.GOOGLE_CLOUD_PROJECT_ID
      });

      const payload = ticket.getPayload();

      const userInfo = {
        email: payload.email,
        domain: payload.hd,
        userId: payload.sub,
        verified: payload.email_verified
      };

      if (this.allowedDomain && userInfo.domain !== this.allowedDomain) {
        throw new Error(`User domain ${userInfo.domain} not allowed`);
      }

      if (!userInfo.verified) {
        throw new Error('Email not verified');
      }

      return userInfo;
    } catch (error) {
      console.error('Authentication verification failed:', error.message);
      throw new Error(`Authentication failed: ${error.message}`);
    }
  }

  extractToken(authData) {
    if (typeof authData.credentials === 'string') {
      return authData.credentials;
    }

    if (authData.credentials.token) {
      return authData.credentials.token;
    }

    if (authData.credentials.idToken) {
      return authData.credentials.idToken;
    }

    if (authData.credentials.bearer) {
      return authData.credentials.bearer;
    }

    return null;
  }

  middleware() {
    return async (req, res, next) => {
      try {
        const authData = req.body.authentication;

        if (!authData) {
          return res.status(401).json({
            error: 'AUTHENTICATION_REQUIRED',
            message: 'Missing authentication data'
          });
        }

        const userInfo = await this.verifyRequest(authData);

        req.user = userInfo;
        req.requestId = req.headers['x-request-id'] || `req_${Date.now()}`;

        next();
      } catch (error) {
        console.error('Auth middleware error:', error.message);
        return res.status(401).json({
          error: 'AUTHENTICATION_FAILED',
          message: error.message
        });
      }
    };
  }
}

export class DevAuthVerifier {
  constructor(config) {
    this.allowedDomain = config.allowedDomain;
    console.warn('⚠️  WARNING: Using development authentication - NOT FOR PRODUCTION');
  }

  async verifyRequest(authData) {
    if (!authData || !authData.email) {
      throw new Error('Dev mode requires email in authentication');
    }

    const [localPart, domain] = authData.email.split('@');

    return {
      email: authData.email,
      domain: domain,
      userId: `dev_${localPart}`,
      verified: true,
      devMode: true
    };
  }

  middleware() {
    return async (req, res, next) => {
      try {
        let authData = req.body.authentication;

        if (!authData && req.headers['x-dev-user-email']) {
          authData = { email: req.headers['x-dev-user-email'] };
        }

        if (!authData) {
          return res.status(401).json({
            error: 'AUTHENTICATION_REQUIRED',
            message: 'Missing authentication data (dev mode)'
          });
        }

        const userInfo = await this.verifyRequest(authData);
        req.user = userInfo;
        req.requestId = req.headers['x-request-id'] || `req_${Date.now()}`;

        next();
      } catch (error) {
        return res.status(401).json({
          error: 'AUTHENTICATION_FAILED',
          message: error.message
        });
      }
    };
  }
}
EOF_AUTH
echo "   ✓ src/auth.js created"

# src/server.js - This is the largest file
echo "   📝 Creating src/server.js (main server file)..."

cat > $APP_DIR/app/src/server.js << 'EOF_SERVER'
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from 'dotenv';
import { v4 as uuidv4 } from 'uuid';
import { KeyWrapper, base64 } from './crypto.js';
import { KeyDatabase } from './database.js';
import { AuthVerifier, DevAuthVerifier } from './auth.js';

config();

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

app.use(helmet());
app.use(express.json());
app.use(morgan('combined'));

let keyWrapper;
let database;
let authVerifier;

async function initializeServer() {
  database = new KeyDatabase(process.env.DATABASE_PATH || './data/keys.db');
  await database.initialize();
  console.log('✓ Database initialized');

  const masterKekBase64 = process.env.MASTER_KEK_BASE64;
  if (!masterKekBase64) {
    console.error('ERROR: MASTER_KEK_BASE64 not set');
    process.exit(1);
  }

  const masterKek = base64.decode(masterKekBase64);
  keyWrapper = new KeyWrapper(masterKek);
  console.log('✓ Key wrapper initialized');

  const authConfig = {
    allowedDomain: process.env.ALLOWED_WORKSPACE_DOMAIN
  };

  if (NODE_ENV === 'production') {
    authVerifier = new AuthVerifier(authConfig);
    console.log('✓ Production authentication enabled');
  } else {
    authVerifier = new DevAuthVerifier(authConfig);
    console.log('✓ Development authentication enabled');
  }

  const existingKeks = database.listKeks();
  if (existingKeks.length === 0) {
    const defaultKeyId = 'kek_default_v1';
    database.registerKek(defaultKeyId, {
      description: 'Default KEK',
      createdBy: 'system'
    });
    console.log(`✓ Registered default KEK: ${defaultKeyId}`);
  }
}

app.get('/healthz', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

app.get('/', (req, res) => {
  res.json({
    service: 'Google Workspace CSE External Key Service',
    version: '1.0.0',
    endpoints: {
      wrap: 'POST /v1/wrappedKeys:wrap',
      unwrap: 'POST /v1/wrappedKeys:unwrap',
      health: 'GET /healthz'
    }
  });
});

app.post('/v1/wrappedKeys:wrap', authVerifier.middleware(), async (req, res) => {
  const startTime = Date.now();

  try {
    const { key, reason } = req.body;

    if (!key) {
      return res.status(400).json({
        error: 'INVALID_REQUEST',
        message: 'Missing required field: key'
      });
    }

    const dek = base64.decode(key);

    if (dek.length !== 32) {
      return res.status(400).json({
        error: 'INVALID_KEY_SIZE',
        message: 'DEK must be 32 bytes (256 bits)'
      });
    }

    const wrappedKey = keyWrapper.wrapKey(dek);
    const keyId = 'kek_default_v1';

    database.logOperation('WRAP', {
      keyId,
      userEmail: req.user.email,
      userDomain: req.user.domain,
      reason: reason || 'ENCRYPT_DOCUMENT',
      success: true,
      ipAddress: req.ip,
      requestId: req.requestId
    });

    const duration = Date.now() - startTime;
    console.log(`Wrapped key for ${req.user.email} in ${duration}ms`);

    res.json({
      wrappedKey: base64.encode(wrappedKey),
      keyId: keyId,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Wrap error:', error);

    database.logOperation('WRAP', {
      userEmail: req.user?.email,
      userDomain: req.user?.domain,
      reason: req.body.reason,
      success: false,
      error: error.message,
      ipAddress: req.ip,
      requestId: req.requestId
    });

    res.status(500).json({
      error: 'WRAP_FAILED',
      message: 'Failed to wrap key'
    });
  }
});

app.post('/v1/wrappedKeys:unwrap', authVerifier.middleware(), async (req, res) => {
  const startTime = Date.now();

  try {
    const { wrappedKey, keyId, reason } = req.body;

    if (!wrappedKey || !keyId) {
      return res.status(400).json({
        error: 'INVALID_REQUEST',
        message: 'Missing required fields: wrappedKey, keyId'
      });
    }

    const kekInfo = database.getKek(keyId);
    if (!kekInfo) {
      database.logOperation('UNWRAP', {
        keyId,
        userEmail: req.user.email,
        userDomain: req.user.domain,
        reason: reason || 'DECRYPT_DOCUMENT',
        success: false,
        error: 'KEK not found',
        ipAddress: req.ip,
        requestId: req.requestId
      });

      return res.status(404).json({
        error: 'KEY_NOT_FOUND',
        message: `KEK ${keyId} not found or inactive`
      });
    }

    const wrappedKeyBuffer = base64.decode(wrappedKey);
    const dek = keyWrapper.unwrapKey(wrappedKeyBuffer);

    database.logOperation('UNWRAP', {
      keyId,
      userEmail: req.user.email,
      userDomain: req.user.domain,
      reason: reason || 'DECRYPT_DOCUMENT',
      success: true,
      ipAddress: req.ip,
      requestId: req.requestId
    });

    const duration = Date.now() - startTime;
    console.log(`Unwrapped key for ${req.user.email} in ${duration}ms`);

    res.json({
      key: base64.encode(dek),
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Unwrap error:', error);

    database.logOperation('UNWRAP', {
      keyId: req.body.keyId,
      userEmail: req.user?.email,
      userDomain: req.user?.domain,
      reason: req.body.reason,
      success: false,
      error: error.message,
      ipAddress: req.ip,
      requestId: req.requestId
    });

    res.status(500).json({
      error: 'UNWRAP_FAILED',
      message: 'Failed to unwrap key'
    });
  }
});

app.get('/v1/audit/logs', async (req, res) => {
  try {
    const filter = {
      userEmail: req.query.email,
      operation: req.query.operation,
      startTime: req.query.startTime ? parseInt(req.query.startTime) : undefined,
      endTime: req.query.endTime ? parseInt(req.query.endTime) : undefined,
      limit: req.query.limit ? parseInt(req.query.limit) : 100
    };

    const logs = database.getAuditLogs(filter);

    res.json({
      count: logs.length,
      logs: logs
    });
  } catch (error) {
    console.error('Audit log error:', error);
    res.status(500).json({
      error: 'QUERY_FAILED',
      message: 'Failed to retrieve audit logs'
    });
  }
});

app.get('/v1/keys', (req, res) => {
  try {
    const keks = database.listKeks();

    res.json({
      count: keks.length,
      keys: keks.map(k => ({
        keyId: k.key_id,
        algorithm: k.algorithm,
        status: k.status,
        createdAt: new Date(k.created_at).toISOString()
      }))
    });
  } catch (error) {
    console.error('List keys error:', error);
    res.status(500).json({
      error: 'QUERY_FAILED',
      message: 'Failed to list keys'
    });
  }
});

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'INTERNAL_ERROR',
    message: 'An internal error occurred'
  });
});

initializeServer().then(() => {
  app.listen(PORT, () => {
    console.log('');
    console.log('🔐 Google Workspace CSE Key Service');
    console.log(`   Server running on port ${PORT}`);
    console.log(`   Environment: ${NODE_ENV}`);
    console.log(`   Allowed domain: ${process.env.ALLOWED_WORKSPACE_DOMAIN || 'any'}`);
    console.log('');
  });
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, closing database...');
  database.close();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, closing database...');
  database.close();
  process.exit(0);
});
EOF_SERVER
echo "   ✓ src/server.js created"

# Step 7: Install npm dependencies
echo ""
echo "📦 Step 7/11: Installing npm dependencies..."
cd $APP_DIR/app
npm install --production
echo "   ✓ Dependencies installed"

# Step 8: Generate KEK and create .env
echo ""
echo "🔑 Step 8/11: Generating Master KEK..."
MASTER_KEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")

cat > $APP_DIR/app/.env << EOF_ENV
PORT=3000
NODE_ENV=production

GOOGLE_CLOUD_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=$APP_DIR/app/service-account-key.json

ALLOWED_WORKSPACE_DOMAIN=yourdomain.com

MASTER_KEK_BASE64=$MASTER_KEK

DATABASE_PATH=$APP_DIR/app/data/keys.db

ENABLE_AUDIT_LOG=true
AUDIT_LOG_PATH=$APP_DIR/app/logs/audit.log
EOF_ENV

echo "   ✓ Master KEK generated and saved to .env"
echo ""
echo "   ⚠️  CRITICAL: Backup this Master KEK now!"
echo "   KEK: $MASTER_KEK"
echo ""
echo "   Save it to: password manager, encrypted file, or write it down"
echo "   If you lose this, ALL encrypted data is unrecoverable!"
echo ""

# Set permissions
chown -R cse:cse $APP_DIR
chmod 600 $APP_DIR/app/.env
chmod 755 $APP_DIR/app/src/*.js

# Step 9: Create systemd service
echo ""
echo "🔧 Step 9/11: Creating systemd service..."
cat > /etc/systemd/system/cse-key-service.service << EOF_SERVICE
[Unit]
Description=Google Workspace CSE Key Service
After=network.target

[Service]
Type=simple
User=cse
WorkingDirectory=$APP_DIR/app
Environment=NODE_ENV=production
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=10

StandardOutput=append:$APP_DIR/app/logs/app.log
StandardError=append:$APP_DIR/app/logs/error.log

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable cse-key-service
echo "   ✓ Systemd service configured"

# Step 10: Configure nginx
echo ""
echo "🌐 Step 10/11: Configuring nginx..."
cat > /etc/nginx/sites-available/cse-key-service << EOF_NGINX
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /healthz {
        proxy_pass http://localhost:3000/healthz;
        access_log off;
    }
}
EOF_NGINX

ln -sf /etc/nginx/sites-available/cse-key-service /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
echo "   ✓ nginx configured"

# Step 11: Configure firewall
echo ""
echo "🔥 Step 11/11: Configuring firewall..."
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
netfilter-persistent save
echo "   ✓ Firewall configured (ports 80, 443 opened)"

# Get SSL certificate
echo ""
echo "🔐 Obtaining SSL certificate from Let's Encrypt..."
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect
echo "   ✓ SSL certificate obtained"

# Start services
echo ""
echo "🚀 Starting services..."
systemctl start cse-key-service
systemctl reload nginx
echo "   ✓ Services started"

# Wait and test
echo ""
echo "✅ Testing deployment..."
sleep 5

# Test local
if curl -f -s http://localhost:3000/healthz > /dev/null; then
    echo "   ✓ Local health check: PASSED"
else
    echo "   ✗ Local health check: FAILED"
    echo "   Check logs: journalctl -u cse-key-service -n 50"
fi

# Test external
if curl -f -s https://$DOMAIN/healthz > /dev/null; then
    echo "   ✓ External health check: PASSED"
    echo "   ✓ SSL certificate: WORKING"
else
    echo "   ⚠️  External health check: FAILED"
    echo "   This is normal if DNS just propagated. Wait 5 min and try:"
    echo "   curl https://$DOMAIN/healthz"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  ✅ DEPLOYMENT COMPLETE!"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Service URLs:"
echo "   • Health check: https://$DOMAIN/healthz"
echo "   • Wrap endpoint: POST https://$DOMAIN/v1/wrappedKeys:wrap"
echo "   • Unwrap endpoint: POST https://$DOMAIN/v1/wrappedKeys:unwrap"
echo ""
echo "⚠️  CRITICAL NEXT STEPS:"
echo ""
echo "1. BACKUP YOUR MASTER KEK:"
echo "   $MASTER_KEK"
echo "   Also in: $APP_DIR/app/.env"
echo ""
echo "2. Configure Google Cloud (for production authentication):"
echo "   a. Create Google Cloud project"
echo "   b. Create service account"
echo "   c. Download service account key JSON"
echo "   d. Upload to VM: scp service-account-key.json root@138.2.98.29:$APP_DIR/app/"
echo ""
echo "3. Edit $APP_DIR/app/.env:"
echo "   • Set GOOGLE_CLOUD_PROJECT_ID=your-actual-project-id"
echo "   • Set ALLOWED_WORKSPACE_DOMAIN=your-workspace-domain.com"
echo ""
echo "4. Restart service:"
echo "   systemctl restart cse-key-service"
echo ""
echo "5. Register in Google Workspace Admin:"
echo "   • Go to: https://admin.google.com"
echo "   • Security → Client-side encryption"
echo "   • Add external key service"
echo "   • Service URL: https://$DOMAIN"
echo ""
echo "Useful Commands:"
echo "   • View logs: journalctl -u cse-key-service -f"
echo "   • Restart: systemctl restart cse-key-service"
echo "   • Status: systemctl status cse-key-service"
echo "   • Test: curl https://$DOMAIN/healthz"
echo "   • Edit config: nano $APP_DIR/app/.env"
echo ""
echo "Documentation:"
echo "   • Full guide at: /root/google-cse-key-service/"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"

