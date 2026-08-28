/**
 * Drug service — fully local PostgreSQL-backed drug lookup.
 */
import { query } from '../config/database.js';
import { AppError } from '../utils/errors.js';
import { getInteractionsByActiveIngredient } from './drugInteraction.service.js';

/**
 * Search drugs by name (fuzzy search using pg_trgm).
 * @param {string} q - Search query
 * @param {{ page?: number, limit?: number }} opts
 * @returns {Promise<{ drugs: any[], total: number }>}
 */
export async function searchDrugs(q, { page = 1, limit = 20 } = {}) {
  const offset = (page - 1) * limit;

  if (!q || q.trim().length < 2) {
    throw new AppError('Search query must be at least 2 characters', 400, 'INVALID_QUERY');
  }

  const searchTerm = q.trim();

  // Use pg_trgm for fuzzy search + ILIKE for exact prefix match
  const result = await query(
    `SELECT drug_name, source, data,
            similarity(drug_name, $1) AS sim_score
     FROM drug_cache
     WHERE drug_name % $1 OR drug_name ILIKE $2
     ORDER BY sim_score DESC, drug_name ASC
     LIMIT $3 OFFSET $4`,
    [searchTerm, `%${searchTerm}%`, limit, offset]
  );

  // Count total
  const countResult = await query(
    `SELECT COUNT(*) FROM drug_cache
     WHERE drug_name % $1 OR drug_name ILIKE $2`,
    [searchTerm, `%${searchTerm}%`]
  );

  const total = parseInt(countResult.rows[0].count);

  return {
    drugs: result.rows.map((r) => ({
      name: r.drug_name,
      source: r.source,
      score: parseFloat(r.sim_score),
      ...r.data,
    })),
    total,
  };
}

/**
 * Get drug details by exact or fuzzy-local name.
 * @param {string} name - Drug name
 * @returns {Promise<object>}
 */
export async function getDrugDetails(name) {
  if (!name || name.trim().length < 1) {
    throw new AppError('Drug name required', 400, 'INVALID_NAME');
  }

  const trimmed = name.trim();

  // 1. Exact local match (non-expired)
  const cached = await query(
    `SELECT data, source, cached_at, expires_at FROM drug_cache
     WHERE drug_name ILIKE $1 AND expires_at > NOW() LIMIT 1`,
    [trimmed]
  );

  if (cached.rows.length > 0) {
    const row = cached.rows[0];
    return {
      ...row.data,
      _source: row.source,
      _cached: true,
      _cached_at: row.cached_at,
    };
  }

  // 2. Local fuzzy fallback to avoid remote dependency for detail pages.
  const fuzzy = await query(
    `SELECT data, source, cached_at,
            similarity(drug_name, $1) AS sim_score
     FROM drug_cache
     WHERE drug_name % $1 OR drug_name ILIKE $2
     ORDER BY
       CASE
         WHEN lower(drug_name) = lower($1) THEN 0
         WHEN drug_name ILIKE $3 THEN 1
         ELSE 2
       END,
       sim_score DESC,
       drug_name ASC
     LIMIT 1`,
    [trimmed, `%${trimmed}%`, `${trimmed}%`]
  );

  if (fuzzy.rows.length > 0) {
    const row = fuzzy.rows[0];
    return {
      ...row.data,
      _source: row.source,
      _cached: true,
      _cached_at: row.cached_at,
      _fuzzy_match: true,
    };
  }

  throw new AppError(`Drug not found: ${trimmed}`, 404, 'DRUG_NOT_FOUND');
}

/**
 * Get drug interactions by active ingredient.
 * @param {string} ingredientName
 * @returns {Promise<object>}
 */
export async function getInteractions(ingredientName) {
  if (!ingredientName || ingredientName.length < 2) {
    throw new AppError('Ingredient name required', 400, 'INVALID_NAME');
  }

  return getInteractionsByActiveIngredient(ingredientName);
}
