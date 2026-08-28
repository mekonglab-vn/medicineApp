import pg from 'pg';
import { env } from './env.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});

// Log pool errors
pool.on('error', (err) => {
  console.error('Unexpected PostgreSQL pool error:', err);
});

/**
 * Execute a parameterized query.
 * @param {string} text - SQL query with $1, $2, ... placeholders
 * @param {any[]} params - Query parameters
 * @returns {Promise<pg.QueryResult>}
 */
export async function query(text, params) {
  const start = Date.now();
  const result = await pool.query(text, params);
  const duration = Date.now() - start;
  if (env.NODE_ENV === 'development' && duration > 100) {
    console.log(`Slow query (${duration}ms): ${text.substring(0, 80)}`);
  }
  return result;
}

/**
 * Check database is reachable.
 * @returns {Promise<{ok: boolean, latency_ms: number}>}
 */
export async function healthCheck() {
  try {
    const start = Date.now();
    await pool.query('SELECT 1');
    return { ok: true, latency_ms: Date.now() - start };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}
