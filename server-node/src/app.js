/**
 * MedicineApp — Node.js API Server
 *
 * Entry point. Sets up Express with middleware and routes.
 *
 * Usage:
 *   npm run dev    # Development with auto-reload
 *   npm start      # Production
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

import { env } from './config/env.js';
import { requestLogger } from './middleware/logger.js';
import { errorHandler } from './middleware/errorHandler.js';
import { generalLimiter, authLimiter } from './middleware/rateLimiter.js';
import healthRoutes from './routes/health.routes.js';
import authRoutes from './routes/auth.routes.js';
import drugRoutes from './routes/drug.routes.js';
import drugInteractionRoutes from './routes/drugInteraction.routes.js';
import scanRoutes from './routes/scan.routes.js';
import planRoutes from './routes/plan.routes.js';

const app = express();

// ── Security ──
app.use(helmet());
app.use(cors({
  origin: env.NODE_ENV === 'production'
    ? ['https://medicineapp.example.com']
    : '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Parsing ──
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── Logging ──
app.use(requestLogger);

// ── Rate Limiting ──
app.use('/api', generalLimiter);
app.use('/api/auth', authLimiter);

// ── Routes ──
app.use('/health', healthRoutes);
app.use('/api', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/drugs', drugRoutes);
app.use('/api/drug-interactions', drugInteractionRoutes);
app.use('/api/scan', scanRoutes);
app.use('/api/plans', planRoutes);

// ── 404 ──
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: {
      code: 'NOT_FOUND',
      message: `Route ${req.method} ${req.originalUrl} not found`,
    },
  });
});

// ── Error Handler (must be last) ──
app.use(errorHandler);

export default app;
