import Database from 'better-sqlite3';
import { mkdir } from 'fs/promises';
import { dirname } from 'path';

/**
 * Database for storing KEK metadata and audit logs
 */
export class KeyDatabase {
  constructor(dbPath) {
    this.dbPath = dbPath;
    this.db = null;
  }

  async initialize() {
    // Ensure data directory exists
    await mkdir(dirname(this.dbPath), { recursive: true });

    this.db = new Database(this.dbPath);

    // Enable WAL mode for better concurrency
    this.db.pragma('journal_mode = WAL');

    this.createTables();
  }

  createTables() {
    // KEK metadata table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS keks (
        key_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        algorithm TEXT NOT NULL DEFAULT 'AES-256-KW',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        metadata TEXT
      )
    `);

    // Audit log table
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

    // Create indexes
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
      CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_email);
      CREATE INDEX IF NOT EXISTS idx_audit_operation ON audit_log(operation);
    `);
  }

  /**
   * Register a new KEK
   */
  registerKek(keyId, metadata = {}) {
    const stmt = this.db.prepare(`
      INSERT INTO keks (key_id, created_at, metadata)
      VALUES (?, ?, ?)
    `);

    stmt.run(keyId, Date.now(), JSON.stringify(metadata));
  }

  /**
   * Get KEK information
   */
  getKek(keyId) {
    const stmt = this.db.prepare(`
      SELECT * FROM keks WHERE key_id = ? AND status = 'ACTIVE'
    `);

    return stmt.get(keyId);
  }

  /**
   * List all active KEKs
   */
  listKeks() {
    const stmt = this.db.prepare(`
      SELECT * FROM keks WHERE status = 'ACTIVE' ORDER BY created_at DESC
    `);

    return stmt.all();
  }

  /**
   * Rotate (deactivate) a KEK
   */
  rotateKek(keyId) {
    const stmt = this.db.prepare(`
      UPDATE keks SET status = 'ROTATED' WHERE key_id = ?
    `);

    stmt.run(keyId);
  }

  /**
   * Log an operation for audit purposes
   */
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

  /**
   * Get audit logs
   */
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
