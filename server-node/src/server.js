/**
 * server.js — Entry point for running the HTTP server.
 * Imported separately from app.js so tests can import app without listening.
 */
import app from './app.js';
import { env } from './config/env.js';
import logger from './middleware/logger.js';

const PORT = env.PORT;
app.listen(PORT, '0.0.0.0', () => {
  logger.info(`🚀 Server running on http://localhost:${PORT}`);
  logger.info(`📋 Health: http://localhost:${PORT}/api/health`);
  logger.info(`🌍 Environment: ${env.NODE_ENV}`);
});
