/**
 * Test database helpers.
 * Uses same PostgreSQL instance but cleans up data between tests.
 */
import { pool, query } from '../../src/config/database.js';
import { buildInteractionPairKey, normalizeLookupKey } from '../../src/utils/drugLookup.js';

/**
 * Clean test data by email prefix to avoid touching real data.
 */
export async function cleanTestUsers(emailPrefix = 'test_ci_') {
  await query(`DELETE FROM users WHERE email LIKE $1`, [`${emailPrefix}%`]);
}

/**
 * Create a test user and return token data.
 */
export async function createTestUser(suffix = '1') {
  const email = `test_ci_${suffix}@example.com`;
  const password = 'Test1234!';
  const name = `Test User ${suffix}`;

  // Clean existing
  await query('DELETE FROM users WHERE email = $1', [email]);

  const { register, login } = await import('../../src/services/auth.service.js');
  await register({ email, password, name });
  const tokens = await login({ email, password });
  return { email, password, name, ...tokens };
}

const LOOKUP_PREFIX = 'test_ci_lookup_';

export async function cleanLookupFixtures(prefix = LOOKUP_PREFIX) {
  const like = `${prefix}%`;
  await query('DELETE FROM drug_interaction_pairs WHERE source_id LIKE $1', [like]);
  await query('DELETE FROM interaction_active_ingredients WHERE name ILIKE $1', [like]);
  await query(
    'DELETE FROM drug_active_ingredients WHERE source = $1 OR drug_name ILIKE $2 OR ingredient_name ILIKE $2',
    ['test', like]
  );
  await query('DELETE FROM drug_cache WHERE source = $1 OR drug_name ILIKE $2', ['test', like]);
}

export async function seedLookupFixtures(prefix = LOOKUP_PREFIX) {
  const drugs = [
    {
      name: `${prefix}warfarin-drug`,
      ingredient: `${prefix}warfarin`,
      detail: { tenThuoc: `${prefix}warfarin-drug`, hoatChat: [{ tenHoatChat: `${prefix}warfarin` }] },
    },
    {
      name: `${prefix}aspirin-drug`,
      ingredient: `${prefix}aspirin`,
      detail: { tenThuoc: `${prefix}aspirin-drug`, hoatChat: [{ tenHoatChat: `${prefix}aspirin` }] },
    },
    {
      name: `${prefix}levocetirizine-drug`,
      ingredient: `${prefix}levocetirizine`,
      detail: {
        tenThuoc: `${prefix}levocetirizine-drug`,
        hoatChat: [{ tenHoatChat: `${prefix}levocetirizine` }],
      },
    },
    {
      name: `${prefix}theophylline-drug`,
      ingredient: `${prefix}theophylline`,
      detail: {
        tenThuoc: `${prefix}theophylline-drug`,
        hoatChat: [{ tenHoatChat: `${prefix}theophylline` }],
      },
    },
  ];

  for (const drug of drugs) {
    await query(
      `INSERT INTO drug_cache (drug_name, source, data, cached_at, expires_at)
       VALUES ($1, 'test', $2, NOW(), NOW() + INTERVAL '365 days')
       ON CONFLICT (drug_name, source) DO UPDATE
       SET data = EXCLUDED.data, cached_at = NOW(), expires_at = NOW() + INTERVAL '365 days'`,
      [drug.name, JSON.stringify(drug.detail)]
    );

    await query(
      `INSERT INTO drug_active_ingredients
        (drug_name, drug_name_key, ingredient_name, ingredient_key, strength, source)
       VALUES ($1, $2, $3, $4, NULL, 'test')
       ON CONFLICT (drug_name_key, ingredient_key, source) DO NOTHING`,
      [
        drug.name,
        normalizeLookupKey(drug.name),
        drug.ingredient,
        normalizeLookupKey(drug.ingredient),
      ]
    );
  }

  const ingredients = [
    { name: `${prefix}warfarin`, count: 2 },
    { name: `${prefix}aspirin`, count: 1 },
    { name: `${prefix}levocetirizine`, count: 1 },
    { name: `${prefix}theophylline`, count: 1 },
  ];

  for (const item of ingredients) {
    await query(
      `INSERT INTO interaction_active_ingredients (name, name_key, interaction_count)
       VALUES ($1, $2, $3)
       ON CONFLICT (name_key) DO UPDATE
       SET name = EXCLUDED.name, interaction_count = EXCLUDED.interaction_count`,
      [item.name, normalizeLookupKey(item.name), item.count]
    );
  }

  const interactions = [
    {
      sourceId: `${prefix}pair-major`,
      ingredientA: `${prefix}warfarin`,
      ingredientB: `${prefix}aspirin`,
      severityOriginal: 'Nghiêm trọng',
      severityNormalized: 'major',
      warning: 'Tăng nguy cơ chảy máu',
    },
    {
      sourceId: `${prefix}pair-unknown`,
      ingredientA: `${prefix}levocetirizine`,
      ingredientB: `${prefix}theophylline`,
      severityOriginal: 'Không xác định',
      severityNormalized: 'unknown',
      warning: 'Giảm nhẹ độ thanh thải',
    },
  ];

  for (const item of interactions) {
    const pairKey = buildInteractionPairKey(item.ingredientA, item.ingredientB);
    const warningKey = normalizeLookupKey(item.warning);
    const dedupeKey = `${item.sourceId}::${pairKey}`;
    await query(
      `INSERT INTO drug_interaction_pairs
        (source_id, source_drug_name, ingredient_a, ingredient_b, ingredient_a_key, ingredient_b_key,
         pair_key, severity_original, severity_normalized, warning, warning_key, dedupe_key)
       VALUES ($1, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (dedupe_key) DO UPDATE
       SET severity_original = EXCLUDED.severity_original,
           severity_normalized = EXCLUDED.severity_normalized,
           warning = EXCLUDED.warning,
           warning_key = EXCLUDED.warning_key`,
      [
        item.sourceId,
        item.ingredientA,
        item.ingredientB,
        normalizeLookupKey(item.ingredientA),
        normalizeLookupKey(item.ingredientB),
        pairKey,
        item.severityOriginal,
        item.severityNormalized,
        item.warning,
        warningKey,
        dedupeKey,
      ]
    );
  }

  return {
    prefix,
    drugs,
    ingredients,
    interactions,
  };
}

export { pool, query };
