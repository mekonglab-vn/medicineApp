import logger from './logger.js';

/**
 * Global error handling middleware.
 * MUST be registered as the LAST middleware.
 */
// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  const statusCode = err.statusCode || 500;
  const isOperational = err.isOperational || false;

  // Log error (NEVER log passwords or tokens)
  logger.error({
    message: err.message,
    code: err.code,
    statusCode,
    method: req.method,
    url: req.originalUrl,
    ...(statusCode === 500 && { stack: err.stack }),
  });

  // Send response
  res.status(statusCode).json({
    success: false,
    error: {
      code: err.code || 'INTERNAL_ERROR',
      message: isOperational
        ? err.message
        : 'Internal Server Error',
    },
  });
}
