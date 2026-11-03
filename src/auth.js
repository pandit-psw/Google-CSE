import { OAuth2Client } from 'google-auth-library';

/**
 * Authentication middleware for verifying Google Workspace requests
 */
export class AuthVerifier {
  constructor(config) {
    this.allowedDomain = config.allowedDomain;
    this.client = new OAuth2Client();
  }

  /**
   * Verify Google Workspace authentication token
   * Google CSE sends authentication information in the request
   */
  async verifyRequest(authData) {
    try {
      if (!authData || !authData.credentials) {
        throw new Error('Missing authentication credentials');
      }

      // Extract the JWT token from credentials
      // Google Workspace CSE sends authentication in various formats
      const token = this.extractToken(authData);

      if (!token) {
        throw new Error('No authentication token found');
      }

      // Verify the JWT token
      const ticket = await this.client.verifyIdToken({
        idToken: token,
        // Google Workspace CSE uses specific audiences
        audience: process.env.GOOGLE_CLOUD_PROJECT_ID
      });

      const payload = ticket.getPayload();

      // Extract user information
      const userInfo = {
        email: payload.email,
        domain: payload.hd, // Hosted domain
        userId: payload.sub,
        verified: payload.email_verified
      };

      // Verify the user is from the allowed domain
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

  /**
   * Extract token from various authentication formats
   */
  extractToken(authData) {
    // Google Workspace CSE can send tokens in different formats
    if (typeof authData.credentials === 'string') {
      return authData.credentials;
    }

    if (authData.credentials.token) {
      return authData.credentials.token;
    }

    if (authData.credentials.idToken) {
      return authData.credentials.idToken;
    }

    // Bearer token format
    if (authData.credentials.bearer) {
      return authData.credentials.bearer;
    }

    return null;
  }

  /**
   * Middleware function for Express
   */
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

        // Attach user info to request
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

/**
 * Simplified auth for development/testing
 * WARNING: DO NOT USE IN PRODUCTION
 */
export class DevAuthVerifier {
  constructor(config) {
    this.allowedDomain = config.allowedDomain;
    console.warn('⚠️  WARNING: Using development authentication - NOT FOR PRODUCTION');
  }

  async verifyRequest(authData) {
    // In dev mode, accept a simple email/domain structure
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
        // In dev mode, accept authentication from body or headers
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
