# Troubleshooting Guide

## Quick Diagnostics

Run these commands on your Oracle VM to check service status:

```bash
# Service status
sudo systemctl status cse-key-service

# Recent logs
sudo journalctl -u cse-key-service -n 50

# Test local endpoint
curl http://localhost:3000/healthz

# Test external endpoint
curl https://your-domain.com/healthz

# Check nginx
sudo systemctl status nginx
sudo nginx -t

# Check firewall
sudo iptables -L -n | grep 443

# Check SSL certificate
sudo certbot certificates
```

## Common Issues

### 1. Service Won't Start

**Symptom:** `systemctl start cse-key-service` fails

**Check:**
```bash
sudo journalctl -u cse-key-service -n 100
```

**Common causes:**

#### A. Missing MASTER_KEK_BASE64
```
Error: MASTER_KEK_BASE64 not set in environment
```

**Fix:**
```bash
# Generate a KEK
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"

# Edit .env
sudo nano /opt/cse-key-service/app/.env

# Add:
MASTER_KEK_BASE64=<generated-key>

# Restart
sudo systemctl restart cse-key-service
```

#### B. Port 3000 Already in Use
```
Error: listen EADDRINUSE: address already in use :::3000
```

**Fix:**
```bash
# Find process using port 3000
sudo lsof -i :3000

# Kill it
sudo kill <PID>

# Or change port in .env
PORT=3001
```

#### C. Missing Dependencies
```
Error: Cannot find module 'express'
```

**Fix:**
```bash
cd /opt/cse-key-service/app
npm install
sudo systemctl restart cse-key-service
```

#### D. Permission Issues
```
Error: EACCES: permission denied
```

**Fix:**
```bash
# Fix ownership
sudo chown -R cse:cse /opt/cse-key-service/app

# Fix permissions
chmod 600 /opt/cse-key-service/app/.env
chmod 600 /opt/cse-key-service/app/service-account-key.json
```

### 2. Authentication Failures

**Symptom:** Wrap/unwrap requests return 401

**Check logs:**
```bash
sudo journalctl -u cse-key-service -f
```

**Common causes:**

#### A. Invalid Service Account
```
Error: Could not load the default credentials
```

**Fix:**
```bash
# Verify file exists
ls -l /opt/cse-key-service/app/service-account-key.json

# Verify it's valid JSON
cat service-account-key.json | python3 -m json.tool

# Verify GOOGLE_APPLICATION_CREDENTIALS in .env
cat .env | grep GOOGLE_APPLICATION_CREDENTIALS
```

#### B. Wrong Domain
```
Error: User domain example.com not allowed
```

**Fix:**
```bash
# Edit .env
nano /opt/cse-key-service/app/.env

# Set correct domain
ALLOWED_WORKSPACE_DOMAIN=yourdomain.com

# Restart
sudo systemctl restart cse-key-service
```

#### C. JWT Verification Fails
```
Error: Invalid token
```

**Possible causes:**
- Clock skew (VM time not synchronized)
- Wrong project ID in .env
- Expired token

**Fix:**
```bash
# Sync time
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Verify project ID
cat .env | grep GOOGLE_CLOUD_PROJECT_ID

# Check VM time
date
```

### 3. Cannot Connect Externally

**Symptom:** `curl https://your-domain.com/healthz` fails

#### A. Firewall Not Configured

**Check:**
```bash
sudo iptables -L -n | grep 443
```

Should show:
```
ACCEPT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:443
```

**Fix:**
```bash
# Allow HTTPS
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT

# Save rules
sudo netfilter-persistent save

# Verify
sudo iptables -L -n | grep 443
```

#### B. Oracle Cloud Security List

**Check Oracle Cloud Console:**
1. Go to: Networking → Virtual Cloud Networks
2. Select your VCN → Security Lists
3. Check Ingress Rules

**Should have:**
- Source: 0.0.0.0/0
- Protocol: TCP
- Destination Port: 443

**Add if missing:**
```
Source: 0.0.0.0/0
IP Protocol: TCP
Destination Port Range: 443
Description: HTTPS for CSE Key Service
```

#### C. nginx Not Running

**Check:**
```bash
sudo systemctl status nginx
```

**Fix:**
```bash
# Start nginx
sudo systemctl start nginx

# Enable on boot
sudo systemctl enable nginx

# Test configuration
sudo nginx -t

# If config errors, check:
sudo nano /etc/nginx/sites-available/cse-key-service
```

#### D. DNS Not Configured

**Test:**
```bash
dig your-domain.com
nslookup your-domain.com
```

**Should return your Oracle VM's public IP.**

**Fix:**
- Update DNS A record at your domain registrar
- Point to Oracle VM public IP
- Wait for DNS propagation (up to 48 hours, usually < 1 hour)

### 4. SSL Certificate Issues

**Symptom:** Browser shows SSL error or certificate expired

#### A. Certificate Not Obtained

**Check:**
```bash
sudo certbot certificates
```

**Fix:**
```bash
# Obtain certificate
sudo certbot --nginx -d your-domain.com \
  --email your-email@example.com \
  --agree-tos --non-interactive

# Verify
sudo certbot certificates
```

#### B. Certificate Expired

**Check expiry:**
```bash
sudo certbot certificates
```

**Fix:**
```bash
# Manual renewal
sudo certbot renew

# Test auto-renewal
sudo certbot renew --dry-run

# Check cron job
sudo systemctl status certbot.timer
```

#### C. Wrong Domain in Certificate

**Fix:**
```bash
# Delete old certificate
sudo certbot delete --cert-name your-old-domain.com

# Obtain new one
sudo certbot --nginx -d your-new-domain.com
```

### 5. Wrap/Unwrap Operations Fail

**Symptom:** 500 error on wrap/unwrap

#### A. Invalid KEK

**Error in logs:**
```
Error: Master KEK must be 32 bytes (256 bits)
```

**Fix:**
```bash
# Generate new KEK (32 bytes = 44 characters base64)
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"

# Update .env
MASTER_KEK_BASE64=<new-key>

# ⚠️ WARNING: Old wrapped keys cannot be unwrapped with new KEK!
# Only do this for new deployments or after backing up old KEK
```

#### B. Invalid Input

**Error:**
```
Error: DEK must be 32 bytes (256 bits)
```

**Cause:** Client sent wrong key size

**Test with correct size:**
```bash
# Generate test DEK (32 bytes)
TEST_DEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")

# Test wrap
curl -X POST http://localhost:3000/v1/wrappedKeys:wrap \
  -H "Content-Type: application/json" \
  -H "X-Dev-User-Email: test@yourdomain.com" \
  -d "{
    \"key\": \"$TEST_DEK\",
    \"authentication\": {
      \"email\": \"test@yourdomain.com\"
    },
    \"reason\": \"ENCRYPT_DOCUMENT\"
  }"
```

#### C. Database Error

**Error:**
```
Error: SQLITE_CANTOPEN: unable to open database file
```

**Fix:**
```bash
# Create data directory
mkdir -p /opt/cse-key-service/app/data

# Fix permissions
sudo chown -R cse:cse /opt/cse-key-service/app/data

# Reinitialize database
cd /opt/cse-key-service/app
sudo -u cse node -e "
  const { KeyDatabase } = require('./src/database.js');
  const db = new KeyDatabase('./data/keys.db');
  db.initialize().then(() => {
    console.log('Database initialized');
    process.exit(0);
  });
"
```

### 6. Google Workspace Integration Issues

**Symptom:** Cannot register key service in Workspace Admin

#### A. URL Not Accessible

**Test from different location:**
```bash
# From your local machine
curl -v https://your-domain.com/healthz
```

**Should return:**
```json
{"status":"healthy",...}
```

#### B. Invalid SSL Certificate

**Check certificate:**
```bash
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

**Look for:**
- Valid certificate chain
- No expired certificates
- Correct domain name

#### C. Google Cannot Reach Your Server

**Possible causes:**
- Firewall blocking Google IPs (don't do this)
- Rate limiting too aggressive
- Service not running
- Wrong URL in Workspace Admin

**Fix:**
- Ensure port 443 is open to 0.0.0.0/0
- Check service is running: `sudo systemctl status cse-key-service`
- Verify health check works externally

### 7. Performance Issues

**Symptom:** Slow response times

#### A. High CPU Usage

**Check:**
```bash
top
htop  # if installed
```

**If cse-key-service using > 50% CPU:**

**Check logs for errors:**
```bash
sudo journalctl -u cse-key-service -n 100
```

**Common causes:**
- Too many requests (need scaling)
- Infinite loop in code (check logs)
- Database lock contention

**Fix:**
```bash
# Check request rate
curl http://localhost:3000/v1/audit/logs?limit=100 | \
  python3 -m json.tool | grep timestamp

# If legitimate high load, consider:
# - Adding more instances
# - Using load balancer
# - Upgrading to paid compute (more CPUs)
```

#### B. Database Growing Too Large

**Check size:**
```bash
du -h /opt/cse-key-service/app/data/keys.db
```

**If > 1 GB, clean old logs:**
```bash
# Connect to database
sqlite3 /opt/cse-key-service/app/data/keys.db

# Check audit log count
SELECT COUNT(*) FROM audit_log;

# Delete logs older than 90 days
DELETE FROM audit_log 
WHERE timestamp < (strftime('%s', 'now') - 90*24*60*60) * 1000;

# Vacuum to reclaim space
VACUUM;

.quit
```

**Or automate:**
```bash
cat > /opt/cse-key-service/app/cleanup-logs.sh << 'EOF'
#!/bin/bash
sqlite3 /opt/cse-key-service/app/data/keys.db << SQL
DELETE FROM audit_log 
WHERE timestamp < (strftime('%s', 'now') - 90*24*60*60) * 1000;
VACUUM;
SQL
echo "Cleaned up audit logs older than 90 days"
EOF

chmod +x /opt/cse-key-service/app/cleanup-logs.sh

# Add to crontab (monthly)
sudo -u cse crontab -e
# Add:
0 3 1 * * /opt/cse-key-service/app/cleanup-logs.sh
```

### 8. Lost Master KEK

**Symptom:** Need to recover or lost .env file

**⚠️ CRITICAL:** If you lost your Master KEK, all wrapped DEKs are UNRECOVERABLE.

**Recovery options:**

#### A. From Backup
```bash
# Restore from backup
cp /path/to/backup/.env /opt/cse-key-service/app/.env

# Restart service
sudo systemctl restart cse-key-service
```

#### B. From Another Instance
If you have multiple VMs:
```bash
# On old instance
cat /opt/cse-key-service/app/.env | grep MASTER_KEK_BASE64

# Copy to new instance
# Update .env on new instance
```

#### C. No Recovery Possible
If truly lost with no backup:
- All existing wrapped DEKs cannot be unwrapped
- All encrypted documents become unrecoverable
- Must generate new KEK and start fresh
- Previous encrypted content is permanently lost

**Generate new KEK (ONLY if starting fresh):**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"

# Update .env with new KEK
# ⚠️ This makes all old wrapped keys unusable!
```

**Prevention:**
- Backup .env file to multiple secure locations
- Store KEK in password manager
- Keep offline encrypted backup
- Consider using cloud secret manager (advanced)

## Testing

### Local Testing

```bash
# Health check
curl http://localhost:3000/healthz

# Generate test data
TEST_DEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")
echo "Test DEK: $TEST_DEK"

# Test wrap (dev mode)
WRAP_RESPONSE=$(curl -s -X POST http://localhost:3000/v1/wrappedKeys:wrap \
  -H "Content-Type: application/json" \
  -H "X-Dev-User-Email: test@yourdomain.com" \
  -d "{
    \"key\": \"$TEST_DEK\",
    \"authentication\": {\"email\": \"test@yourdomain.com\"},
    \"reason\": \"ENCRYPT_DOCUMENT\"
  }")

echo "Wrap response: $WRAP_RESPONSE"

# Extract wrapped key
WRAPPED_KEY=$(echo $WRAP_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['wrappedKey'])")
KEY_ID=$(echo $WRAP_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['keyId'])")

echo "Wrapped key: $WRAPPED_KEY"
echo "Key ID: $KEY_ID"

# Test unwrap
UNWRAP_RESPONSE=$(curl -s -X POST http://localhost:3000/v1/wrappedKeys:unwrap \
  -H "Content-Type: application/json" \
  -H "X-Dev-User-Email: test@yourdomain.com" \
  -d "{
    \"wrappedKey\": \"$WRAPPED_KEY\",
    \"keyId\": \"$KEY_ID\",
    \"authentication\": {\"email\": \"test@yourdomain.com\"},
    \"reason\": \"DECRYPT_DOCUMENT\"
  }")

echo "Unwrap response: $UNWRAP_RESPONSE"

# Extract unwrapped key
UNWRAPPED_DEK=$(echo $UNWRAP_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['key'])")

# Verify match
if [ "$TEST_DEK" = "$UNWRAPPED_DEK" ]; then
  echo "✅ SUCCESS: Unwrapped DEK matches original"
else
  echo "❌ FAILURE: Keys don't match!"
  echo "Original:  $TEST_DEK"
  echo "Unwrapped: $UNWRAPPED_DEK"
fi
```

### Production Testing

```bash
# Test from external location
curl https://your-domain.com/healthz

# Check SSL
curl -v https://your-domain.com/healthz 2>&1 | grep -A 10 'Server certificate'

# Test with real Google token (requires actual CSE setup)
# This would be done through Google Workspace, not curl
```

## Monitoring

### Real-time Logs

```bash
# Application logs
sudo journalctl -u cse-key-service -f

# nginx access logs
sudo tail -f /var/log/nginx/access.log

# nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Audit Logs

```bash
# Recent operations
curl http://localhost:3000/v1/audit/logs?limit=50 | python3 -m json.tool

# Filter by user
curl "http://localhost:3000/v1/audit/logs?email=user@domain.com&limit=20"

# Filter by operation
curl "http://localhost:3000/v1/audit/logs?operation=WRAP&limit=20"

# Failed operations only
curl http://localhost:3000/v1/audit/logs | \
  python3 -c "import sys, json; logs = json.load(sys.stdin)['logs']; [print(l) for l in logs if l['success'] == 0]"
```

### System Health

```bash
# Disk space
df -h

# Memory usage
free -h

# CPU load
uptime

# Active connections
sudo netstat -an | grep :3000 | wc -l

# Service uptime
sudo systemctl status cse-key-service | grep Active
```

## Getting Help

If you're still stuck:

1. **Check logs thoroughly:**
   ```bash
   sudo journalctl -u cse-key-service --since "1 hour ago" | less
   ```

2. **Enable debug logging:**
   ```bash
   # Edit .env
   NODE_ENV=development
   
   # Restart
   sudo systemctl restart cse-key-service
   ```

3. **Review documentation:**
   - [README.md](./README.md)
   - [QUICKSTART.md](./QUICKSTART.md)
   - [DEPLOYMENT.md](./DEPLOYMENT.md)
   - [ARCHITECTURE.md](./ARCHITECTURE.md)

4. **Test locally first:**
   - Set up on your local machine
   - Verify it works there
   - Then troubleshoot production differences

5. **Common overlooked items:**
   - [ ] Firewall rules (both Oracle Cloud and iptables)
   - [ ] DNS propagation (can take hours)
   - [ ] Certificate domain name matches actual domain
   - [ ] Service account key is valid JSON
   - [ ] .env file has no syntax errors
   - [ ] File permissions (600 for secrets)
   - [ ] Service running as correct user
   - [ ] Clock synchronized (for JWT validation)
   - [ ] Allowed domain matches your workspace

## Emergency Recovery

### Service Completely Broken

```bash
# Stop everything
sudo systemctl stop cse-key-service
sudo systemctl stop nginx

# Backup current state
sudo cp -r /opt/cse-key-service/app /opt/cse-key-service/app.backup.$(date +%Y%m%d_%H%M%S)

# Restore from backup or redeploy
# ... (follow DEPLOYMENT.md)

# Test locally first
cd /opt/cse-key-service/app
sudo -u cse npm start

# If works, restart services
sudo systemctl start cse-key-service
sudo systemctl start nginx
```

### Data Recovery

```bash
# Backup database
sudo cp /opt/cse-key-service/app/data/keys.db \
       /opt/cse-key-service/app/data/keys.db.backup

# Export audit logs
sqlite3 /opt/cse-key-service/app/data/keys.db << EOF
.headers on
.mode csv
.output /tmp/audit_export.csv
SELECT * FROM audit_log;
.quit
EOF
```

---

**Remember:** Most issues are configuration-related. Check logs, verify settings, test locally first!
