import crypto from 'crypto';

/**
 * Key wrapping and unwrapping using AES-KW (RFC 3394)
 * This is the standard for key wrapping used by Google Workspace CSE
 */

export class KeyWrapper {
  constructor(masterKek) {
    if (!masterKek || masterKek.length !== 32) {
      throw new Error('Master KEK must be 32 bytes (256 bits)');
    }
    this.masterKek = masterKek;
  }

  /**
   * Wrap a Data Encryption Key (DEK) with the Key Encryption Key (KEK)
   * @param {Buffer} dek - The data encryption key to wrap (typically 32 bytes)
   * @returns {Buffer} - The wrapped key
   */
  wrapKey(dek) {
    // AES-256-KW algorithm (RFC 3394)
    const cipher = crypto.createCipheriv('id-aes256-wrap', this.masterKek, null);

    const wrapped = Buffer.concat([
      cipher.update(dek),
      cipher.final()
    ]);

    return wrapped;
  }

  /**
   * Unwrap a previously wrapped DEK
   * @param {Buffer} wrappedKey - The wrapped key
   * @returns {Buffer} - The unwrapped DEK
   */
  unwrapKey(wrappedKey) {
    try {
      const decipher = crypto.createDecipheriv('id-aes256-wrap', this.masterKek, null);

      const unwrapped = Buffer.concat([
        decipher.update(wrappedKey),
        decipher.final()
      ]);

      return unwrapped;
    } catch (error) {
      throw new Error('Failed to unwrap key: invalid wrapped key or KEK');
    }
  }

  /**
   * Generate a new KEK
   * @returns {Buffer} - A 32-byte KEK
   */
  static generateKek() {
    return crypto.randomBytes(32);
  }

  /**
   * Generate a new DEK (typically done by Google, but useful for testing)
   * @returns {Buffer} - A 32-byte DEK
   */
  static generateDek() {
    return crypto.randomBytes(32);
  }
}

/**
 * Helper function to encode/decode base64 for API communication
 */
export const base64 = {
  encode: (buffer) => buffer.toString('base64'),
  decode: (str) => Buffer.from(str, 'base64')
};
