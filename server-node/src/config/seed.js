/**
 * Drug seed script — Import crawled drugs (drug_db_vn_full.json) into drug_cache table.
 *
 * Usage: node src/config/seed.js
 */
import fs from 'node:fs';
import path from 'node:path';
import { pool, query } from './database.js';

function resolveDrugDbPath() {
  const candidates = [
    process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR, 'drug_db_vn_full.json') : null,
    path.resolve(import.meta.dirname, '..', '..', 'data', 'drug_db_vn_full.json'),
    path.resolve(import.meta.dirname, '..', '..', '..', 'data', 'drug_db_vn_full.json'),
    '/app/data/drug_db_vn_full.json',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return candidates[0] || '/app/data/drug_db_vn_full.json';
}

const DRUG_DB_PATH = resolveDrugDbPath();

async function seed() {
  console.log('🌱 Seeding drug_cache from crawled data...');

  if (!fs.existsSync(DRUG_DB_PATH)) {
    console.error(`❌ File not found: ${DRUG_DB_PATH}`);
    process.exit(1);
  }

  // Fast check: skip if already seeded
  try {
    const countRes = await query(`SELECT COUNT(*) FROM drug_cache WHERE source = 'local'`);
    const existingCount = parseInt(countRes.rows[0].count, 10);
    if (existingCount >= 9000) {
      console.log(`  ℹ️ drug_cache already contains ${existingCount} drugs. Seed is up-to-date.`);
      await pool.end();
      return;
    }
  } catch (err) {
    console.log(`  ℹ️ Unable to check existing count (${err.message}), proceeding with seed.`);
  }

  const raw = JSON.parse(fs.readFileSync(DRUG_DB_PATH, 'utf-8'));
  const sourceDrugs = raw.drugs || [];
  const uniqueDrugs = new Map();
  for (const drug of sourceDrugs) {
    const key = String(drug?.tenThuoc || '').trim().toLowerCase();
    if (!key) {
      continue;
    }
    uniqueDrugs.set(key, drug);
  }

  const drugs = [...uniqueDrugs.values()];
  console.log(`  Found ${sourceDrugs.length} source rows`);
  console.log(`  Using ${drugs.length} unique drug names`);

  let inserted = 0;
  let skipped = 0;

  // Batch insert in chunks of 100
  const BATCH = 100;
  for (let i = 0; i < drugs.length; i += BATCH) {
    const batch = drugs.slice(i, i + BATCH);
    const values = [];
    const params = [];
    let paramIdx = 1;

    for (const drug of batch) {
      values.push(`($${paramIdx}, 'local', $${paramIdx + 1}, NOW(), NOW() + INTERVAL '365 days')`);
      params.push(drug.tenThuoc, JSON.stringify(drug));
      paramIdx += 2;
    }

    try {
      await query(
        `INSERT INTO drug_cache (drug_name, source, data, cached_at, expires_at)
         VALUES ${values.join(', ')}
         ON CONFLICT (drug_name, source) DO UPDATE
         SET data = EXCLUDED.data, cached_at = NOW(), expires_at = NOW() + INTERVAL '365 days'`,
        params
      );
      inserted += batch.length;
    } catch (err) {
      console.error(`  ⚠️ Batch ${i}–${i + batch.length}: ${err.message}`);
      skipped += batch.length;
    }

    if ((i + BATCH) % 1000 === 0 || i + BATCH >= drugs.length) {
      console.log(`  [${Math.min(i + BATCH, drugs.length)}/${drugs.length}] inserted: ${inserted}`);
    }
  }

  console.log(`✅ Seed complete: ${inserted} inserted, ${skipped} skipped`);
  await pool.end();
}

seed();
