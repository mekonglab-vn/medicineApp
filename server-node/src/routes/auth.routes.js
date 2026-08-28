/**
 * Auth routes — register, login, refresh, logout.
 */
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/errors.js';
import { success, created } from '../utils/response.js';
import { validateBody } from '../middleware/validator.js';
import { requireAuth } from '../middleware/auth.js';
import * as authService from '../services/auth.service.js';

const router = Router();

// ── Validation schemas ──

const registerSchema = z.object({
  email: z.string().email('Invalid email'),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Must contain uppercase letter')
    .regex(/[0-9]/, 'Must contain a number'),
  name: z.string().min(1).max(100).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
  deviceInfo: z.string().optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1, 'Refresh token required'),
});

// ── Routes ──

/**
 * POST /api/auth/register
 */
router.post(
  '/register',
  validateBody(registerSchema),
  asyncHandler(async (req, res) => {
    const user = await authService.register(req.body);
    created(res, { user });
  })
);

/**
 * POST /api/auth/login
 */
router.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.login(req.body);
    success(res, result);
  })
);

/**
 * POST /api/auth/refresh
 */
router.post(
  '/refresh',
  validateBody(refreshSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.refresh(req.body.refreshToken);
    success(res, result);
  })
);

/**
 * POST /api/auth/logout-all
 * Requires authentication. Revokes all refresh tokens.
 */
router.post(
  '/logout-all',
  requireAuth,
  asyncHandler(async (req, res) => {
    await authService.logoutAll(req.user.sub);
    success(res, { message: 'All sessions revoked' });
  })
);

export default router;
