# Deployment Guide

## Prerequisites

### 1. Oracle Cloud Setup

1. Create an Oracle Cloud account (Always Free tier)
2. Provision an Ampere A1 instance:
   - Shape: VM.Standard.A1.Flex (4 OCPUs, 24GB RAM)
   - Image: Ubuntu 22.04 LTS
   - Public IP: Assign a reserved public IP
   - SSH: Generate and download SSH keys

3. Configure security list/firewall:
   ```bash
   # Allow HTTPS traffic
   - Ingress: Port 443, Source 0.0.0.0/0
   - Ingress: Port 22 (SSH), Source your-ip/32
   ```

### 2. Google Cloud Setup

1. Create a new Google Cloud project
2. Enable required APIs:
   ```bash
   gcloud services enable \
     cloudresourcemanager.googleapis.com \
     iam.googleapis.com
   ```

3. Create a service account:
   ```bash
   gcloud iam service-accounts create cse-key-service \
     --display-name="CSE Key Service" \
     --project=YOUR_PROJECT_ID
   ```

4. Download the service account key:
   ```bash
   gcloud iam service-accounts keys create service-account-key.json \
     --iam-account=cse-key-service@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```

5. Configure OAuth consent screen (optional but recommended):
   - Go to: https://console.cloud.google.com/apis/credentials/consent
   - Set up internal app for your Workspace domain
   - Add scopes: email, profile

## Server Deployment

### Step 1: Connect to Oracle VM

```bash
ssh -i ~/path/to/private-key ubuntu@YOUR_ORACLE_VM_IP
```

### Step 2: Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install nginx
sudo apt install -y nginx

# Install certbot for Let's Encrypt
sudo apt install -y certbot python3-certbot-nginx

# Install build tools (for better-sqlite3)
sudo apt install -y build-essential python3
```

### Step 3: Create Application User

```bash
sudo useradd -r -s /bin/bash -m -d /opt/cse-key-service cse
sudo su - cse
```

### Step 4: Deploy Application

```bash
# Clone or upload your code
mkdir -p /opt/cse-key-service/app
cd /opt/cse-key-service/app

# Upload your code (from your local machine):
# scp -i ~/path/to/private-key -r google-cse-key-service/* ubuntu@YOUR_ORACLE_VM_IP:/tmp/
# Then as cse user:
# cp -r /tmp/google-cse-key-service/* /opt/cse-key-service/app/

# Install dependencies
npm install --production

# Create data and logs directories
mkdir -p data logs
```

### Step 5: Configure Environment

```bash
# Generate a secure KEK
export MASTER_KEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")

# Create .env file
cat > .env << EOF
PORT=3000
NODE_ENV=production

GOOGLE_CLOUD_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=/opt/cse-key-service/app/service-account-key.json

ALLOWED_WORKSPACE_DOMAIN=yourdomain.com

MASTER_KEK_BASE64=$MASTER_KEK

DATABASE_PATH=/opt/cse-key-service/app/data/keys.db

ENABLE_AUDIT_LOG=true
AUDIT_LOG_PATH=/opt/cse-key-service/app/logs/audit.log
EOF

# Upload service account key
# From local: scp -i ~/path/to/private-key service-account-key.json ubuntu@YOUR_ORACLE_VM_IP:/tmp/
cp /tmp/service-account-key.json /opt/cse-key-service/app/

# Secure the files
chmod 600 .env service-account-key.json
```

### Step 6: Set Up Systemd Service

Exit from cse user and create systemd service:

```bash
exit  # Back to ubuntu user

sudo tee /etc/systemd/system/cse-key-service.service > /dev/null << EOF
[Unit]
Description=Google Workspace CSE Key Service
After=network.target

[Service]
Type=simple
User=cse
WorkingDirectory=/opt/cse-key-service/app
Environment=NODE_ENV=production
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=10

StandardOutput=append:/opt/cse-key-service/app/logs/app.log
StandardError=append:/opt/cse-key-service/app/logs/error.log

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable cse-key-service
sudo systemctl start cse-key-service

# Check status
sudo systemctl status cse-key-service
```

### Step 7: Configure Nginx

```bash
sudo tee /etc/nginx/sites-available/cse-key-service > /dev/null << 'EOF'
server {
    listen 80;
    server_name your-domain.com;  # Replace with your domain

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;  # Replace with your domain

    # SSL certificates (will be added by certbot)
    # ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # Proxy to Node.js app
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Health check endpoint
    location /healthz {
        proxy_pass http://localhost:3000/healthz;
        access_log off;
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/cse-key-service /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Step 8: Obtain SSL Certificate

```bash
# Replace with your domain and email
sudo certbot --nginx -d your-domain.com --email your-email@example.com --agree-tos --non-interactive

# Test auto-renewal
sudo certbot renew --dry-run
```

### Step 9: Configure Oracle Cloud Firewall

```bash
# On the Oracle VM, allow HTTPS through local firewall
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

## Testing

### Test from local machine:

```bash
# Health check
curl https://your-domain.com/healthz

# Test wrap (development mode)
curl -X POST https://your-domain.com/v1/wrappedKeys:wrap \
  -H "Content-Type: application/json" \
  -H "X-Dev-User-Email: test@yourdomain.com" \
  -d '{
    "key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    "authentication": {
      "email": "test@yourdomain.com"
    },
    "reason": "ENCRYPT_DOCUMENT"
  }'
```

## Google Workspace Configuration

### Register External Key Service

1. Go to Google Workspace Admin Console: https://admin.google.com
2. Navigate to: **Security** → **Access and data control** → **Client-side encryption**
3. Click **Add external key service**
4. Enter your key service details:
   - Name: Your Key Service
   - Service URL: `https://your-domain.com`
   - Authentication: OAuth 2.0 or Service Account

### Configure CSE for Apps

1. In Admin Console, enable CSE for:
   - Gmail
   - Google Drive
   - Google Docs
   - Google Sheets
   - Google Slides
   - Google Meet

2. Apply to organizational units or groups

### Test with Google Docs

1. Open Google Docs
2. Create a new document
3. Look for the encryption icon/option
4. Select your external key service
5. Create encrypted content

## Monitoring

### View logs:

```bash
# Application logs
sudo journalctl -u cse-key-service -f

# Audit logs
sudo su - cse
tail -f /opt/cse-key-service/app/logs/audit.log

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Check audit database:

```bash
sudo su - cse
cd /opt/cse-key-service/app

# Query audit logs via API
curl http://localhost:3000/v1/audit/logs?limit=50
```

## Backup

```bash
# Backup the KEK and database
sudo su - cse
cd /opt/cse-key-service/app

# Backup script
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/cse-key-service/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
cp data/keys.db $BACKUP_DIR/keys_${DATE}.db

# Backup environment (contains KEK)
cp .env $BACKUP_DIR/.env_${DATE}

# Keep only last 30 days
find $BACKUP_DIR -name "keys_*.db" -mtime +30 -delete
find $BACKUP_DIR -name ".env_*" -mtime +30 -delete

echo "Backup completed: $DATE"
EOF

chmod +x backup.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/cse-key-service/app/backup.sh") | crontab -
```

## Security Checklist

- [ ] HTTPS enabled with valid SSL certificate
- [ ] Firewall configured (only ports 22, 443)
- [ ] Service account key secured (chmod 600)
- [ ] Master KEK backed up securely offline
- [ ] Audit logging enabled
- [ ] Regular backups scheduled
- [ ] SSH key-based authentication only
- [ ] Production authentication enabled (NODE_ENV=production)
- [ ] Google Workspace domain restricted
- [ ] Monitor logs regularly

## Troubleshooting

### Service won't start:
```bash
sudo systemctl status cse-key-service
sudo journalctl -u cse-key-service -n 50
```

### Connection issues:
```bash
# Check if service is listening
sudo netstat -tlnp | grep 3000

# Test locally
curl http://localhost:3000/healthz

# Check nginx
sudo nginx -t
sudo systemctl status nginx
```

### Authentication failures:
- Verify GOOGLE_APPLICATION_CREDENTIALS path
- Check service account key permissions
- Ensure Google Cloud project ID is correct
- Verify Workspace domain matches
