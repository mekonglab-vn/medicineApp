/**
 * Drug routes — search, details, interactions.
 */
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/errors.js';
import { success, paginated } from '../utils/response.js';
import { validateQuery } from '../middleware/validator.js';
import { requireAuth } from '../middleware/auth.js';
import * as drugService from '../services/drug.service.js';

const router = Router();

// ── Validation ──

const searchSchema = z.object({
  q: z.string().min(2, 'Query must be at least 2 characters'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

// ── Routes ──

/**
 * GET /api/drugs/search?q=paracetamol&page=1&limit=20
 * Fuzzy search drugs by name. Requires auth.
 */
router.get(
  '/search',
  requireAuth,
  validateQuery(searchSchema),
  asyncHandler(async (req, res) => {
    const { q, page, limit } = req.query;
    const result = await drugService.searchDrugs(q, { page, limit });
    paginated(res, {
      items: result.drugs,
      total: result.total,
      page,
      limit,
    });
  })
);

/**
 * GET /api/drugs/:name
 * Get drug details by name. Requires auth.
 */
router.get(
  '/:name',
  requireAuth,
  asyncHandler(async (req, res) => {
    const drug = await drugService.getDrugDetails(req.params.name);
    success(res, drug);
  })
);

/**
 * GET /api/drugs/interactions/:ingredient
 * Get drug interactions by active ingredient. Requires auth.
 */
router.get(
  '/interactions/:ingredient',
  requireAuth,
  asyncHandler(async (req, res) => {
    const data = await drugService.getInteractions(req.params.ingredient);
    success(res, data);
  })
);

export default router;
