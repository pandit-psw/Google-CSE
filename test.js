import { KeyWrapper, base64 } from './src/crypto.js';
import { KeyDatabase } from './src/database.js';
import crypto from 'crypto';

console.log('🧪 Testing Google Workspace CSE Key Service Components\n');

// Test 1: Key Generation
console.log('Test 1: Key Generation');
const testKek = KeyWrapper.generateKek();
const testDek = KeyWrapper.generateDek();
console.log(`✓ Generated KEK: ${testKek.length} bytes`);
console.log(`✓ Generated DEK: ${testDek.length} bytes\n`);

// Test 2: Key Wrapping
console.log('Test 2: Key Wrapping and Unwrapping');
const wrapper = new KeyWrapper(testKek);
const wrapped = wrapper.wrapKey(testDek);
console.log(`✓ Wrapped DEK: ${wrapped.length} bytes`);
console.log(`  Base64: ${base64.encode(wrapped).substring(0, 40)}...`);

const unwrapped = wrapper.unwrapKey(wrapped);
console.log(`✓ Unwrapped DEK: ${unwrapped.length} bytes`);

// Verify correctness
if (Buffer.compare(testDek, unwrapped) === 0) {
  console.log(`✓ Unwrapped DEK matches original\n`);
} else {
  console.error(`✗ ERROR: Unwrapped DEK does not match!\n`);
  process.exit(1);
}

// Test 3: Database Operations
console.log('Test 3: Database Operations');
const testDbPath = './test-keys.db';
const db = new KeyDatabase(testDbPath);
await db.initialize();
console.log('✓ Database initialized');

// Register a test KEK
db.registerKek('test_kek_1', { description: 'Test KEK', environment: 'test' });
console.log('✓ Registered test KEK');

// Retrieve KEK
const kekInfo = db.getKek('test_kek_1');
console.log(`✓ Retrieved KEK: ${kekInfo.key_id}`);

// Log operations
db.logOperation('WRAP', {
  keyId: 'test_kek_1',
  userEmail: 'test@example.com',
  userDomain: 'example.com',
  reason: 'TEST',
  success: true,
  ipAddress: '127.0.0.1',
  requestId: 'test_req_001'
});
console.log('✓ Logged wrap operation');

db.logOperation('UNWRAP', {
  keyId: 'test_kek_1',
  userEmail: 'test@example.com',
  userDomain: 'example.com',
  reason: 'TEST',
  success: true,
  ipAddress: '127.0.0.1',
  requestId: 'test_req_002'
});
console.log('✓ Logged unwrap operation');

// Query audit logs
const logs = db.getAuditLogs({ limit: 10 });
console.log(`✓ Retrieved ${logs.length} audit log entries\n`);

// Test 4: Full Wrap/Unwrap Cycle
console.log('Test 4: Full KACLS Simulation');
const masterKek = KeyWrapper.generateKek();
const kacls = new KeyWrapper(masterKek);

// Simulate Google sending a DEK to wrap
const googleDek = KeyWrapper.generateDek();
console.log(`  Google sends DEK: ${base64.encode(googleDek).substring(0, 40)}...`);

// Wrap it
const wrappedForStorage = kacls.wrapKey(googleDek);
console.log(`  Service wraps DEK: ${base64.encode(wrappedForStorage).substring(0, 40)}...`);

// Simulate storage and retrieval
const retrievedWrapped = wrappedForStorage;
console.log(`  Retrieve wrapped DEK from storage`);

// Unwrap it
const unwrappedDek = kacls.unwrapKey(retrievedWrapped);
console.log(`  Service unwraps DEK: ${base64.encode(unwrappedDek).substring(0, 40)}...`);

// Verify
if (Buffer.compare(googleDek, unwrappedDek) === 0) {
  console.log(`✓ Full cycle successful - DEK matches\n`);
} else {
  console.error(`✗ ERROR: Full cycle failed\n`);
  process.exit(1);
}

// Test 5: Performance
console.log('Test 5: Performance Test');
const iterations = 1000;
const perfKek = KeyWrapper.generateKek();
const perfWrapper = new KeyWrapper(perfKek);
const perfDek = KeyWrapper.generateDek();

const startWrap = Date.now();
for (let i = 0; i < iterations; i++) {
  perfWrapper.wrapKey(perfDek);
}
const wrapTime = Date.now() - startWrap;

const testWrapped = perfWrapper.wrapKey(perfDek);
const startUnwrap = Date.now();
for (let i = 0; i < iterations; i++) {
  perfWrapper.unwrapKey(testWrapped);
}
const unwrapTime = Date.now() - startUnwrap;

console.log(`  Wrap ${iterations} keys: ${wrapTime}ms (${(iterations / (wrapTime / 1000)).toFixed(2)} ops/sec)`);
console.log(`  Unwrap ${iterations} keys: ${unwrapTime}ms (${(iterations / (unwrapTime / 1000)).toFixed(2)} ops/sec)`);
console.log(`  Average wrap latency: ${(wrapTime / iterations).toFixed(3)}ms`);
console.log(`  Average unwrap latency: ${(unwrapTime / iterations).toFixed(3)}ms\n`);

// Cleanup
db.close();
import { unlink } from 'fs/promises';
try {
  await unlink(testDbPath);
  await unlink(testDbPath + '-shm');
  await unlink(testDbPath + '-wal');
} catch (e) {
  // Ignore cleanup errors
}

console.log('✅ All tests passed!\n');
console.log('Next steps:');
console.log('1. Install dependencies: npm install');
console.log('2. Configure .env file (copy from .env.example)');
console.log('3. Generate master KEK: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'base64\'))"');
console.log('4. Start server: npm start');
console.log('5. Test health endpoint: curl http://localhost:3000/healthz');
