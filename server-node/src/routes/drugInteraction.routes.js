/**
 * Drug interaction routes — interactions by drug and active ingredient.
 */
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/errors.js';
import { paginated, success } from '../utils/response.js';
import { validateBody, validateQuery } from '../middleware/validator.js';
import { requireAuth } from '../middleware/auth.js';
import * as drugInteractionService from '../services/drugInteraction.service.js';

const router = Router();

const checkByDrugsSchema = z.object({
  drugNames: z.array(z.string().trim().min(1).max(255)).min(2).max(20),
});

const checkByActiveIngredientsSchema = z.object({
  activeIngredients: z.array(z.string().trim().min(1).max(255)).min(2).max(20),
});

const searchActiveIngredientsSchema = z.object({
  keyword: z.string().trim().min(1).max(120),
});

const listActiveIngredientsSchema = z.object({
  keyword: z.string().trim().max(120).optional().default(''),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const byActiveIngredientSchema = z.object({
  ingredientName: z.string().trim().min(1).max(120),
});

/**
 * POST /api/drug-interactions/check-by-drugs
 */
router.post(
  '/check-by-drugs',
  requireAuth,
  validateBody(checkByDrugsSchema),
  asyncHandler(async (req, res) => {
    const data = await drugInteractionService.checkByDrugNames(req.body.drugNames);
    success(res, data);
  })
);

/**
 * GET /api/drug-interactions/search-active-ingredients?keyword=...
 */
router.get(
  '/search-active-ingredients',
  requireAuth,
  validateQuery(searchActiveIngredientsSchema),
  asyncHandler(async (req, res) => {
    const data = await drugInteractionService.searchActiveIngredients(req.query.keyword);
    success(res, data);
  })
);

/**
 * GET /api/drug-interactions/active-ingredients?keyword=...&page=1&limit=20
 */
router.get(
  '/active-ingredients',
  requireAuth,
  validateQuery(listActiveIngredientsSchema),
  asyncHandler(async (req, res) => {
    const { keyword, page, limit } = req.query;
    const data = await drugInteractionService.listActiveIngredients({
      keyword,
      page,
      limit,
    });
    paginated(res, {
      items: data.items,
      total: data.total,
      page: data.page,
      limit: data.limit,
    });
  })
);

/**
 * POST /api/drug-interactions/check-by-active-ingredients
 */
router.post(
  '/check-by-active-ingredients',
  requireAuth,
  validateBody(checkByActiveIngredientsSchema),
  asyncHandler(async (req, res) => {
    const data = await drugInteractionService.checkByActiveIngredients(req.body.activeIngredients);
    success(res, data);
  })
);

/**
 * GET /api/drug-interactions/by-active-ingredient?ingredientName=...
 */
router.get(
  '/by-active-ingredient',
  requireAuth,
  validateQuery(byActiveIngredientSchema),
  asyncHandler(async (req, res) => {
    const data = await drugInteractionService.getInteractionsByActiveIngredient(
      req.query.ingredientName
    );
    success(res, data);
  })
);

export default router;
