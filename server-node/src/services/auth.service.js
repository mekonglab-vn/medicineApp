/**
 * Auth service — JWT + bcrypt + refresh token logic.
 */
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'node:crypto';
import { query } from '../config/database.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';

const SALT_ROUNDS = 12;

/**
 * Register a new user.
 * @param {{ email: string, password: string, name?: string }} data
 * @returns {Promise<{ id: string, email: string, name: string }>}
 */
export async function register({ email, password, name }) {
  // Check duplicate email
  const existing = await query('SELECT id FROM users WHERE email = $1', [email]);
  if (existing.rows.length > 0) {
    throw new AppError('Email already registered', 409, 'DUPLICATE_EMAIL');
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
  const result = await query(
    `INSERT INTO users (email, password_hash, name)
     VALUES ($1, $2, $3)
     RETURNING id, email, name, created_at`,
    [email, passwordHash, name || null]
  );

  return result.rows[0];
}

/**
 * Login with email + password → access + refresh tokens.
 * @param {{ email: string, password: string, deviceInfo?: string }} data
 * @returns {Promise<{ user, accessToken, refreshToken }>}
 */
export async function login({ email, password, deviceInfo }) {
  const result = await query(
    'SELECT id, email, name, password_hash FROM users WHERE email = $1',
    [email]
  );

  if (result.rows.length === 0) {
    throw new AppError('Invalid email or password', 401, 'INVALID_CREDENTIALS');
  }

  const user = result.rows[0];
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    throw new AppError('Invalid email or password', 401, 'INVALID_CREDENTIALS');
  }

  const accessToken = generateAccessToken(user);
  const refreshToken = await generateRefreshToken(user.id, deviceInfo);

  return {
    user: { id: user.id, email: user.email, name: user.name },
    accessToken,
    refreshToken,
  };
}

/**
 * Refresh access token using refresh token.
 * @param {string} refreshToken
 * @returns {Promise<{ accessToken, refreshToken }>}
 */
export async function refresh(refreshToken) {
  const tokenHash = hashToken(refreshToken);

  const result = await query(
    `SELECT rt.id, rt.user_id, rt.expires_at, u.email, u.name
     FROM refresh_tokens rt
     JOIN users u ON u.id = rt.user_id
     WHERE rt.token_hash = $1 AND rt.revoked_at IS NULL`,
    [tokenHash]
  );

  if (result.rows.length === 0) {
    throw new AppError('Invalid refresh token', 401, 'INVALID_TOKEN');
  }

  const row = result.rows[0];

  if (new Date(row.expires_at) < new Date()) {
    throw new AppError('Refresh token expired', 401, 'TOKEN_EXPIRED');
  }

  // Revoke old token (rotation)
  await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1', [row.id]);

  // Generate new pair
  const user = { id: row.user_id, email: row.email, name: row.name };
  const newAccessToken = generateAccessToken(user);
  const newRefreshToken = await generateRefreshToken(row.user_id);

  return { accessToken: newAccessToken, refreshToken: newRefreshToken };
}

/**
 * Logout all devices — revoke all refresh tokens.
 * @param {string} userId
 */
export async function logoutAll(userId) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
    [userId]
  );
}

// ── Internal helpers ──

function generateAccessToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email },
    env.JWT_SECRET,
    { expiresIn: env.JWT_EXPIRES_IN }
  );
}

async function generateRefreshToken(userId, deviceInfo) {
  const token = crypto.randomBytes(40).toString('hex');
  const tokenHash = hashToken(token);

  // Parse refresh expiry (e.g. '7d' → 7 days)
  const daysMatch = env.JWT_REFRESH_EXPIRES_IN.match(/^(\d+)d$/);
  const days = daysMatch ? parseInt(daysMatch[1]) : 7;
  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000);

  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [userId, tokenHash, deviceInfo || null, expiresAt]
  );

  return token;
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}
