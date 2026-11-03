#!/bin/bash

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Google Workspace CSE Key Service - Verification Report"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# 1. Service Status
echo "📋 1. Service Status"
if systemctl is-active --quiet cse-key-service; then
    echo "   ✅ Service is running"
    systemctl status cse-key-service --no-pager | grep "Active:"
else
    echo "   ❌ Service is NOT running"
fi
echo ""

# 2. Port Listening
echo "🔌 2. Port Listening"
if netstat -tln | grep -q ":3000"; then
    echo "   ✅ Port 3000 (app) is listening"
else
    echo "   ❌ Port 3000 is NOT listening"
fi

if netstat -tln | grep -q ":80"; then
    echo "   ✅ Port 80 (HTTP) is listening"
else
    echo "   ❌ Port 80 is NOT listening"
fi

if netstat -tln | grep -q ":443"; then
    echo "   ✅ Port 443 (HTTPS) is listening"
else
    echo "   ❌ Port 443 is NOT listening"
fi
echo ""

# 3. nginx Status
echo "🌐 3. nginx Status"
if systemctl is-active --quiet nginx; then
    echo "   ✅ nginx is running"
    nginx -t 2>&1 | grep "successful"
else
    echo "   ❌ nginx is NOT running"
fi
echo ""

# 4. SSL Certificate
echo "🔐 4. SSL Certificate"
if [ -f /etc/letsencrypt/live/cse-keys.paxtontech.top/fullchain.pem ]; then
    echo "   ✅ SSL certificate exists"
    EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/cse-keys.paxtontech.top/fullchain.pem | cut -d= -f2)
    echo "   📅 Expires: $EXPIRY"
else
    echo "   ❌ SSL certificate NOT found"
fi
echo ""

# 5. Firewall Rules
echo "🔥 5. Firewall Rules"
if iptables -L -n | grep -q "dpt:443"; then
    echo "   ✅ Port 443 allowed in firewall"
else
    echo "   ⚠️  Port 443 may not be allowed"
fi

if iptables -L -n | grep -q "dpt:80"; then
    echo "   ✅ Port 80 allowed in firewall"
else
    echo "   ⚠️  Port 80 may not be allowed"
fi
echo ""

# 6. Application Files
echo "📁 6. Application Files"
if [ -f /opt/cse-key-service/app/src/server.js ]; then
    echo "   ✅ server.js exists"
else
    echo "   ❌ server.js NOT found"
fi

if [ -f /opt/cse-key-service/app/.env ]; then
    echo "   ✅ .env exists"
    echo "   📝 Checking .env configuration..."

    if grep -q "MASTER_KEK_BASE64=" /opt/cse-key-service/app/.env && ! grep -q "MASTER_KEK_BASE64=\$" /opt/cse-key-service/app/.env; then
        echo "      ✅ Master KEK is set"
    else
        echo "      ❌ Master KEK NOT set correctly"
    fi

    if grep -q "NODE_ENV=production" /opt/cse-key-service/app/.env; then
        echo "      ✅ NODE_ENV=production"
    else
        echo "      ⚠️  NODE_ENV is not production"
    fi

    WORKSPACE_DOMAIN=$(grep "ALLOWED_WORKSPACE_DOMAIN=" /opt/cse-key-service/app/.env | cut -d= -f2)
    echo "      📧 Allowed domain: $WORKSPACE_DOMAIN"

    PROJECT_ID=$(grep "GOOGLE_CLOUD_PROJECT_ID=" /opt/cse-key-service/app/.env | cut -d= -f2)
    echo "      🔑 Google Project ID: $PROJECT_ID"
else
    echo "   ❌ .env NOT found"
fi
echo ""

# 7. Database
echo "💾 7. Database"
if [ -f /opt/cse-key-service/app/data/keys.db ]; then
    echo "   ✅ Database exists"
    DB_SIZE=$(du -h /opt/cse-key-service/app/data/keys.db | cut -f1)
    echo "   📊 Size: $DB_SIZE"
else
    echo "   ❌ Database NOT found"
fi
echo ""

# 8. Logs
echo "📝 8. Recent Logs"
if [ -f /opt/cse-key-service/app/logs/error.log ]; then
    ERROR_COUNT=$(wc -l < /opt/cse-key-service/app/logs/error.log)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "   ⚠️  Error log has $ERROR_COUNT lines"
        echo "   Last 3 errors:"
        tail -3 /opt/cse-key-service/app/logs/error.log | sed 's/^/      /'
    else
        echo "   ✅ No errors logged"
    fi
else
    echo "   ✅ No error log (good)"
fi
echo ""

# 9. Health Checks
echo "🏥 9. Health Checks"
echo "   Testing local endpoint..."
LOCAL_HEALTH=$(curl -s http://localhost:3000/healthz 2>&1)
if echo "$LOCAL_HEALTH" | grep -q "healthy"; then
    echo "   ✅ Local health check: PASSED"
else
    echo "   ❌ Local health check: FAILED"
    echo "      Response: $LOCAL_HEALTH"
fi
echo ""

echo "   Testing external HTTPS endpoint..."
EXTERNAL_HEALTH=$(curl -s https://cse-keys.paxtontech.top/healthz 2>&1)
if echo "$EXTERNAL_HEALTH" | grep -q "healthy"; then
    echo "   ✅ External HTTPS health check: PASSED"
else
    echo "   ❌ External HTTPS health check: FAILED"
    echo "      Response: $EXTERNAL_HEALTH"
fi
echo ""

# 10. DNS Check
echo "🌍 10. DNS Resolution"
DNS_IP=$(dig +short cse-keys.paxtontech.top | head -1)
if [ -n "$DNS_IP" ]; then
    echo "   ✅ DNS resolves to: $DNS_IP"
    ACTUAL_IP=$(hostname -I | awk '{print $1}')
    echo "   📍 Server IP: $ACTUAL_IP"
else
    echo "   ❌ DNS resolution failed"
fi
echo ""

# 11. Auto-start on Boot
echo "🔄 11. Auto-start Configuration"
if systemctl is-enabled --quiet cse-key-service; then
    echo "   ✅ Service will start on boot"
else
    echo "   ❌ Service NOT enabled for boot"
fi
echo ""

# 12. Disk Space
echo "💿 12. Disk Space"
df -h /opt/cse-key-service | tail -1 | awk '{print "   📊 Available: "$4" ("$5" used)"}'
echo ""

# 13. Test Wrap/Unwrap (Development Mode)
echo "🧪 13. Functional Test (Wrap/Unwrap)"
TEST_DEK=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")
echo "   Generating test DEK..."

WRAP_RESPONSE=$(curl -s -X POST http://localhost:3000/v1/wrappedKeys:wrap \
  -H "Content-Type: application/json" \
  -H "X-Dev-User-Email: test@example.com" \
  -d "{
    \"key\": \"$TEST_DEK\",
    \"authentication\": {\"email\": \"test@example.com\"},
    \"reason\": \"ENCRYPT_DOCUMENT\"
  }")

if echo "$WRAP_RESPONSE" | grep -q "wrappedKey"; then
    echo "   ✅ Wrap operation: PASSED"
    WRAPPED_KEY=$(echo "$WRAP_RESPONSE" | grep -o '"wrappedKey":"[^"]*"' | cut -d'"' -f4)
    KEY_ID=$(echo "$WRAP_RESPONSE" | grep -o '"keyId":"[^"]*"' | cut -d'"' -f4)

    UNWRAP_RESPONSE=$(curl -s -X POST http://localhost:3000/v1/wrappedKeys:unwrap \
      -H "Content-Type: application/json" \
      -H "X-Dev-User-Email: test@example.com" \
      -d "{
        \"wrappedKey\": \"$WRAPPED_KEY\",
        \"keyId\": \"$KEY_ID\",
        \"authentication\": {\"email\": \"test@example.com\"},
        \"reason\": \"DECRYPT_DOCUMENT\"
      }")

    if echo "$UNWRAP_RESPONSE" | grep -q "\"key\""; then
        UNWRAPPED_KEY=$(echo "$UNWRAP_RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        if [ "$TEST_DEK" = "$UNWRAPPED_KEY" ]; then
            echo "   ✅ Unwrap operation: PASSED"
            echo "   ✅ Key round-trip: SUCCESS"
        else
            echo "   ❌ Unwrap operation: Keys don't match!"
        fi
    else
        echo "   ❌ Unwrap operation: FAILED"
    fi
else
    echo "   ❌ Wrap operation: FAILED"
    echo "      Response: $WRAP_RESPONSE"
fi
echo ""

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Count checks
TOTAL=0
PASSED=0

systemctl is-active --quiet cse-key-service && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

netstat -tln | grep -q ":3000" && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

systemctl is-active --quiet nginx && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

[ -f /etc/letsencrypt/live/cse-keys.paxtontech.top/fullchain.pem ] && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

curl -s http://localhost:3000/healthz | grep -q "healthy" && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

curl -s https://cse-keys.paxtontech.top/healthz | grep -q "healthy" && PASSED=$((PASSED+1))
TOTAL=$((TOTAL+1))

echo "✅ Passed: $PASSED/$TOTAL critical checks"
echo ""

if [ $PASSED -eq $TOTAL ]; then
    echo "🎉 ALL CHECKS PASSED! Service is fully operational."
    echo ""
    echo "✅ Ready for Google Workspace integration!"
    echo ""
    echo "Next steps:"
    echo "   1. Set up Google Cloud project & service account"
    echo "   2. Update .env with your project ID and workspace domain"
    echo "   3. Restart service: systemctl restart cse-key-service"
    echo "   4. Register in Google Workspace Admin Console"
else
    echo "⚠️  Some checks failed. Review the report above."
fi
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
