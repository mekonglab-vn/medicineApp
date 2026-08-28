/**
 * Rate limiting middleware.
 * Separate limits for auth routes (stricter) vs general routes.
 */
import rateLimit from 'express-rate-limit';
import { env } from '../config/env.js';

/**
 * General rate limiter: 300 req / 15 min per IP.
 */
export const generalLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MS,
  max: env.RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many requests. Please try again later.',
    },
  },
});

/**
 * Auth rate limiter: 20 req / 15 min per IP (stricter).
 * Prevents brute force login/register.
 */
export const authLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MS,
  max: env.AUTH_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'AUTH_RATE_LIMITED',
      message: 'Too many authentication attempts. Please try again later.',
    },
  },
});
