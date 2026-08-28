import { Router } from 'express';
import { healthCheck } from '../config/database.js';
import { env } from '../config/env.js';

const router = Router();

/**
 * GET /api/health
 * Returns server status, DB connection, Python pipeline status.
 */
router.get('/health', async (req, res) => {
  const db = await healthCheck();

  // Check Python FastAPI is reachable
  let pythonStatus = { ok: false };
  try {
    const ctrl = new AbortController();
    const timeout = setTimeout(() => ctrl.abort(), 3000);
    const resp = await fetch(`${env.PYTHON_API_URL}/api/health`, {
      signal: ctrl.signal,
    });
    clearTimeout(timeout);
    pythonStatus = { ok: resp.ok, status: resp.status };
  } catch {
    pythonStatus = { ok: false, error: 'unreachable' };
  }

  const allOk = db.ok;
  res.status(allOk ? 200 : 503).json({
    success: allOk,
    data: {
      server: 'ok',
      version: '1.0.0',
      environment: env.NODE_ENV,
      database: db,
      python_pipeline: pythonStatus,
      uptime_s: Math.floor(process.uptime()),
    },
  });
});

export default router;
