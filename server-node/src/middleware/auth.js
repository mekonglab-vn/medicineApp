/**
 * JWT authentication middleware.
 * Verifies Bearer token and attaches user to req.user.
 */
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';
import { query } from '../config/database.js';

/**
 * Require valid JWT Bearer token.
 * Sets req.user = { sub, email, iat, exp }
 */
export async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new AppError('Authentication required', 401, 'AUTH_REQUIRED'));
  }

  const token = authHeader.split(' ')[1];

  try {
    const decoded = jwt.verify(token, env.JWT_SECRET);
    const result = await query('SELECT id, email FROM users WHERE id = $1', [decoded.sub]);
    if (result.rows.length === 0) {
      return next(new AppError('Session expired', 401, 'AUTH_USER_NOT_FOUND'));
    }
    req.user = decoded;
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return next(new AppError('Token expired', 401, 'TOKEN_EXPIRED'));
    }
    return next(new AppError('Invalid token', 401, 'INVALID_TOKEN'));
  }
}
