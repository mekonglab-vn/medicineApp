/**
 * Input validation middleware using Zod.
 */
import { AppError } from '../utils/errors.js';

/**
 * Create validation middleware for request body.
 * @param {import('zod').ZodSchema} schema
 */
export function validateBody(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      const errors = result.error.flatten().fieldErrors;
      throw new AppError(
        `Validation failed: ${JSON.stringify(errors)}`,
        400,
        'VALIDATION_ERROR'
      );
    }
    req.body = result.data; // Use parsed (sanitized) data
    next();
  };
}

/**
 * Create validation middleware for query params.
 * @param {import('zod').ZodSchema} schema
 */
export function validateQuery(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
      const errors = result.error.flatten().fieldErrors;
      throw new AppError(
        `Validation failed: ${JSON.stringify(errors)}`,
        400,
        'VALIDATION_ERROR'
      );
    }
    req.query = result.data;
    next();
  };
}
