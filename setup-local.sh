#!/bin/bash

echo "🔐 Google Workspace CSE Key Service - Local Setup"
echo "=================================================="
echo ""

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js 20+ first."
    echo "   Download from: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo "❌ Node.js version 20+ required. Current version: $(node --version)"
    exit 1
fi

echo "✅ Node.js $(node --version) found"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
npm install

if [ $? -ne 0 ]; then
    echo "❌ npm install failed"
    exit 1
fi

echo "✅ Dependencies installed"
echo ""

# Generate master KEK
echo "🔑 Generating Master KEK..."
MASTER_KEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")

if [ -z "$MASTER_KEK" ]; then
    echo "❌ Failed to generate KEK"
    exit 1
fi

echo "✅ Master KEK generated"
echo ""

# Create .env file
if [ -f .env ]; then
    echo "⚠️  .env file already exists. Backing up to .env.backup"
    cp .env .env.backup
fi

cat > .env << EOF
# Server Configuration
PORT=3000
NODE_ENV=development

# Google Cloud Configuration (will be set up later for production)
GOOGLE_CLOUD_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json

# Allowed Google Workspace Domain
ALLOWED_WORKSPACE_DOMAIN=yourdomain.com

# Master Key Encryption Key (KEK)
# ⚠️  KEEP THIS SECRET! Backup securely!
MASTER_KEK_BASE64=$MASTER_KEK

# Database
DATABASE_PATH=./data/keys.db

# Audit Logging
ENABLE_AUDIT_LOG=true
AUDIT_LOG_PATH=./logs/audit.log
EOF

echo "✅ Created .env file with generated KEK"
echo ""
echo "📝 IMPORTANT: Edit .env and set ALLOWED_WORKSPACE_DOMAIN to your domain"
echo ""

# Create directories
mkdir -p data logs
echo "✅ Created data and logs directories"
echo ""

# Run tests
echo "🧪 Running tests..."
node test.js

if [ $? -ne 0 ]; then
    echo "❌ Tests failed"
    exit 1
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env and set ALLOWED_WORKSPACE_DOMAIN to your Google Workspace domain"
echo "2. Start the server: npm start"
echo "3. Test the API: curl http://localhost:3000/healthz"
echo ""
echo "⚠️  IMPORTANT: Backup your Master KEK from .env file securely!"
echo "   If you lose this key, all encrypted data becomes unrecoverable."
echo ""
