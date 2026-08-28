/**
 * Scan routes — upload prescription image, get scan history.
 */
import { Router } from 'express';
import multer from 'multer';
import { asyncHandler } from '../utils/errors.js';
import { success, paginated } from '../utils/response.js';
import { requireAuth } from '../middleware/auth.js';
import { AppError } from '../utils/errors.js';
import * as scanService from '../services/scan.service.js';
import { env } from '../config/env.js';

const router = Router();

// Multer config: memory storage, max 10MB
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: env.MAX_FILE_SIZE_MB * 1024 * 1024 },
});

// Allowed MIME types (magic bytes check in route)
const ALLOWED_MIMES = ['image/jpeg', 'image/png', 'image/webp'];

/**
 * POST /api/scan
 * Upload prescription image → OCR pipeline → drug list.
 * Requires auth. Max 10MB image.
 */
router.post(
  '/',
  requireAuth,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new AppError('No file uploaded', 400, 'NO_FILE');
    }

    // Check MIME type from magic bytes (not just Content-Type header)
    const { fileTypeFromBuffer } = await import('file-type');
    const detected = await fileTypeFromBuffer(req.file.buffer);
    if (!detected || !ALLOWED_MIMES.includes(detected.mime)) {
      throw new AppError(
        `Invalid file type. Allowed: ${ALLOWED_MIMES.join(', ')}`,
        400,
        'INVALID_FILE_TYPE'
      );
    }

    const ocrText = req.body?.ocr_text || req.body?.ocrText || null;
    const ocrLines = req.body?.ocr_lines || req.body?.ocrLines || null;

    const result = await scanService.scanPrescription(
      req.file.buffer,
      req.user.sub,
      req.file.originalname,
      detected.mime, // pass verified MIME type
      null,
      ocrText,
      ocrLines
    );

    success(res, result);
  })
);

/**
 * POST /api/scan/session/start
 * Start adaptive multi-shot scan session.
 */
router.post(
  '/session/start',
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await scanService.startScanSession(req.user.sub);
    success(res, result, 201);
  })
);

/**
 * POST /api/scan/session/:sessionId/add-image
 * Add a captured image into an active session.
 */
router.post(
  '/session/:sessionId/add-image',
  requireAuth,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new AppError('No file uploaded', 400, 'NO_FILE');
    }

    const { fileTypeFromBuffer } = await import('file-type');
    const detected = await fileTypeFromBuffer(req.file.buffer);
    if (!detected || !ALLOWED_MIMES.includes(detected.mime)) {
      throw new AppError(
        `Invalid file type. Allowed: ${ALLOWED_MIMES.join(', ')}`,
        400,
        'INVALID_FILE_TYPE'
      );
    }

    const result = await scanService.addImageToSession(
      req.params.sessionId,
      req.user.sub,
      req.file.buffer,
      req.file.originalname,
      detected.mime
    );
    success(res, result);
  })
);

/**
 * GET /api/scan/session/:sessionId
 * Get current adaptive session state.
 */
router.get(
  '/session/:sessionId',
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await scanService.getScanSession(
      req.params.sessionId,
      req.user.sub
    );
    success(res, result);
  })
);

/**
 * POST /api/scan/session/:sessionId/stop
 * Stop adaptive session and return merged result.
 */
router.post(
  '/session/:sessionId/stop',
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await scanService.stopScanSession(
      req.params.sessionId,
      req.user.sub
    );
    success(res, result);
  })
);

/**
 * GET /api/scan/history?page=1&limit=20
 * Get scan history for current user.
 */
router.get(
  '/history',
  requireAuth,
  asyncHandler(async (req, res) => {
    const page = parseInt(req.query.page) || 1;
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);

    const result = await scanService.getScanHistory(req.user.sub, { page, limit });
    paginated(res, {
      items: result.scans,
      total: result.total,
      page,
      limit,
    });
  })
);

/**
 * GET /api/scan/history/:id
 * Get detail of a single scan history item.
 */
router.get(
  '/history/:id',
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await scanService.getScanHistoryItem(req.user.sub, req.params.id);
    success(res, result);
  })
);

export default router;
