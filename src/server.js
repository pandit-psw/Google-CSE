import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from 'dotenv';
import { v4 as uuidv4 } from 'uuid';
import { KeyWrapper, base64 } from './crypto.js';
import { KeyDatabase } from './database.js';
import { AuthVerifier, DevAuthVerifier } from './auth.js';

// Load environment variables
config();

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

// Middleware
app.use(helmet());
app.use(express.json());
app.use(morgan('combined'));

// Initialize components
let keyWrapper;
let database;
let authVerifier;

async function initializeServer() {
  // Initialize database
  database = new KeyDatabase(process.env.DATABASE_PATH || './data/keys.db');
  await database.initialize();
  console.log('✓ Database initialized');

  // Initialize key wrapper with master KEK
  const masterKekBase64 = process.env.MASTER_KEK_BASE64;
  if (!masterKekBase64) {
    console.error('ERROR: MASTER_KEK_BASE64 not set in environment');
    console.log('Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'base64\'))"');
    process.exit(1);
  }

  const masterKek = base64.decode(masterKekBase64);
  keyWrapper = new KeyWrapper(masterKek);
  console.log('✓ Key wrapper initialized');

  // Initialize authentication
  const authConfig = {
    allowedDomain: process.env.ALLOWED_WORKSPACE_DOMAIN
  };

  if (NODE_ENV === 'production') {
    authVerifier = new AuthVerifier(authConfig);
    console.log('✓ Production authentication enabled');
  } else {
    authVerifier = new DevAuthVerifier(authConfig);
    console.log('✓ Development authentication enabled (NOT FOR PRODUCTION)');
  }

  // Register default KEK if none exists
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

// Health check endpoint
app.get('/healthz', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// Service information endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Google Workspace CSE External Key Service',
    version: '1.0.0',
    endpoints: {
      wrap: 'POST /v1/wrappedKeys:wrap',
      unwrap: 'POST /v1/wrappedKeys:unwrap',
      health: 'GET /healthz'
    },
    documentation: 'https://developers.google.com/workspace/cse'
  });
});

/**
 * POST /v1/wrappedKeys:wrap
 * Wrap a Data Encryption Key (DEK)
 */
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

    // Decode the DEK from base64
    const dek = base64.decode(key);

    if (dek.length !== 32) {
      return res.status(400).json({
        error: 'INVALID_KEY_SIZE',
        message: 'DEK must be 32 bytes (256 bits)'
      });
    }

    // Wrap the DEK
    const wrappedKey = keyWrapper.wrapKey(dek);
    const keyId = 'kek_default_v1'; // Use default KEK (in production, you might select based on policy)

    // Log the operation
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

/**
 * POST /v1/wrappedKeys:unwrap
 * Unwrap a previously wrapped DEK
 */
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

    // Verify the KEK exists
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

    // Decode and unwrap the DEK
    const wrappedKeyBuffer = base64.decode(wrappedKey);
    const dek = keyWrapper.unwrapKey(wrappedKeyBuffer);

    // Log the operation
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

/**
 * GET /v1/audit/logs
 * Get audit logs (admin endpoint)
 */
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

/**
 * GET /v1/keys
 * List active KEKs (admin endpoint)
 */
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

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'INTERNAL_ERROR',
    message: 'An internal error occurred'
  });
});

// Start server
initializeServer().then(() => {
  app.listen(PORT, () => {
    console.log('');
    console.log('🔐 Google Workspace CSE Key Service');
    console.log(`   Server running on port ${PORT}`);
    console.log(`   Environment: ${NODE_ENV}`);
    console.log(`   Allowed domain: ${process.env.ALLOWED_WORKSPACE_DOMAIN || 'any'}`);
    console.log('');
    console.log(`   Health check: http://localhost:${PORT}/healthz`);
    console.log(`   Wrap endpoint: POST http://localhost:${PORT}/v1/wrappedKeys:wrap`);
    console.log(`   Unwrap endpoint: POST http://localhost:${PORT}/v1/wrappedKeys:unwrap`);
    console.log('');
  });
});

// Graceful shutdown
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
