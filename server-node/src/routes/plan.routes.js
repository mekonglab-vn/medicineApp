/**
 * Plan routes — CRUD medication plans + medication logs.
 */
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/errors.js';
import { success, created, paginated } from '../utils/response.js';
import { validateBody, validateQuery } from '../middleware/validator.js';
import { requireAuth } from '../middleware/auth.js';
import * as planService from '../services/plan.service.js';

const router = Router();

// ── Validation ──

const doseScheduleItemSchema = z.object({
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  pills: z.number().int().min(1).max(20),
});

const planDrugSchema = z.object({
  id: z.string().optional(),
  drugName: z.string().min(1).max(255),
  dosage: z.string().max(100).optional(),
  notes: z.string().max(500).optional(),
  sortOrder: z.number().int().min(0).optional(),
});

const planSlotItemSchema = z.object({
  drugId: z.string().optional(),
  drugName: z.string().min(1).max(255),
  dosage: z.string().max(100).optional(),
  pills: z.number().int().min(1).max(20),
});

const planSlotSchema = z.object({
  id: z.string().optional(),
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  sortOrder: z.number().int().min(0).optional(),
  items: z.array(planSlotItemSchema).min(1),
});

function validatePlanGroup(data, ctx) {
  const slotTimes = new Set();
  for (const slot of data.slots || []) {
    if (slotTimes.has(slot.time)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['slots'],
        message: 'Không được trùng giờ giữa các khung giờ',
      });
      break;
    }
    slotTimes.add(slot.time);
  }
}

const createPlanBaseSchema = z.object({
  title: z.string().max(255).optional(),
  drugs: z.array(planDrugSchema).min(1),
  slots: z.array(planSlotSchema).min(1),
  totalDays: z.number().int().min(1).max(365).optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  notes: z.string().max(500).optional(),
});

const createPlanSchema = createPlanBaseSchema.superRefine(validatePlanGroup);

const updatePlanSchema = z.object({
  title: z.string().max(255).optional(),
  drugs: z.array(planDrugSchema).min(1).optional(),
  slots: z.array(planSlotSchema).min(1).optional(),
  totalDays: z.number().int().min(1).max(365).optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  notes: z.string().max(500).optional(),
  isActive: z.boolean().optional(),
}).superRefine((data, ctx) => {
  if (data.slots !== undefined) {
    validatePlanGroup({ slots: data.slots }, ctx);
  }
});

const logSchema = z.object({
  scheduledTime: z.string().datetime(),
  status: z.enum(['taken', 'missed', 'skipped']),
  occurrenceId: z.string().min(3).max(120).optional(),
  note: z.string().max(500).optional(),
});

const logsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

// ── Routes ──

/**
 * POST /api/plans
 */
router.post(
  '/',
  requireAuth,
  validateBody(createPlanSchema),
  asyncHandler(async (req, res) => {
    const plan = await planService.createPlan(req.user.sub, req.body);
    created(res, plan);
  })
);

/**
 * GET /api/plans?page=1&limit=20&active=true
 */
router.get(
  '/',
  requireAuth,
  asyncHandler(async (req, res) => {
    const page = parseInt(req.query.page) || 1;
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    const activeOnly = req.query.active !== 'false';

    const result = await planService.getUserPlans(req.user.sub, {
      page, limit, activeOnly,
    });

    paginated(res, {
      items: result.plans,
      total: result.total,
      page,
      limit,
    });
  })
);

/**
 * GET /api/plans/:id
 */
router.get(
  '/:id',
  requireAuth,
  asyncHandler(async (req, res) => {
    const plan = await planService.getPlanById(req.user.sub, req.params.id);
    success(res, plan);
  })
);

/**
 * PUT /api/plans/:id
 */
router.put(
  '/:id',
  requireAuth,
  validateBody(updatePlanSchema),
  asyncHandler(async (req, res) => {
    const plan = await planService.updatePlan(
      req.user.sub, req.params.id, req.body
    );
    success(res, plan);
  })
);

/**
 * DELETE /api/plans/:id (soft delete)
 */
router.delete(
  '/:id',
  requireAuth,
  asyncHandler(async (req, res) => {
    await planService.deletePlan(req.user.sub, req.params.id);
    success(res, { message: 'Plan deactivated' });
  })
);

/**
 * POST /api/plans/:id/log
 */
router.post(
  '/:id/log',
  requireAuth,
  validateBody(logSchema),
  asyncHandler(async (req, res) => {
    const log = await planService.logMedication(
      req.params.id, req.user.sub, req.body
    );
    created(res, log);
  })
);

/**
 * GET /api/plans/:id/logs
 */
router.get(
  '/:id/logs',
  requireAuth,
  asyncHandler(async (req, res) => {
    const logs = await planService.getPlanLogs(
      req.params.id, req.user.sub
    );
    success(res, logs);
  })
);

/**
 * GET /api/plans/logs?date=YYYY-MM-DD&page=1&limit=20
 * Get medication logs across all plans for current user.
 */
router.get(
  '/logs/all',
  requireAuth,
  validateQuery(logsQuerySchema),
  asyncHandler(async (req, res) => {
    const { page, limit, date } = req.query;
    const result = await planService.getUserMedicationLogs(req.user.sub, {
      page,
      limit,
      date: date || null,
    });

    paginated(res, {
      items: result.logs,
      total: result.total,
      page,
      limit,
    });
  })
);

/**
 * GET /api/plans/today?date=YYYY-MM-DD
 * Get expanded doses for today's schedule.
 */
router.get(
  '/today/summary',
  requireAuth,
  validateQuery(z.object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  })),
  asyncHandler(async (req, res) => {
    const date = typeof req.query.date === 'string' ? req.query.date : null;
    const result = await planService.getTodaySchedule(req.user.sub, { date });
    success(res, result);
  })
);

export default router;
