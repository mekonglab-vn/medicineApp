/**
 * Lookup seed script — imports local interaction data and derived ingredient mappings.
 *
 * Usage: node src/config/seed_lookup.js
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { pool } from './database.js';
import {
  buildInteractionPairKey,
  normalizeDisplayText,
  normalizeInteractionSeverity,
  normalizeLookupKey,
} from '../utils/drugLookup.js';

const ROOT_DIR = path.resolve(import.meta.dirname, '..', '..', '..');
const DRUG_DB_PATH = path.resolve(ROOT_DIR, 'data', 'drug_db_vn_full.json');
const INTERACTION_DB_PATH = path.resolve(ROOT_DIR, 'data', 'drug_interactions_vn.json');

function loadJson(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Required seed file not found: ${filePath}`);
  }

  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function pickPreferredLabel(current, candidate) {
  if (!current) {
    return candidate;
  }

  if (!candidate) {
    return current;
  }

  if (candidate.length < current.length) {
    return candidate;
  }

  return current;
}

function buildDrugIngredientRows(drugPayload) {
  const drugs = Array.isArray(drugPayload?.drugs) ? drugPayload.drugs : [];
  const rows = [];
  const seen = new Set();

  for (const drug of drugs) {
    const drugName = normalizeDisplayText(drug.tenThuoc);
    const drugNameKey = normalizeLookupKey(drugName);
    if (!drugName || !drugNameKey) {
      continue;
    }

    const ingredients = Array.isArray(drug.hoatChat) ? drug.hoatChat : [];
    for (const item of ingredients) {
      const ingredientName = normalizeDisplayText(item?.tenHoatChat);
      const ingredientKey = normalizeLookupKey(ingredientName);
      if (!ingredientName || !ingredientKey) {
        continue;
      }

      const dedupeKey = `${drugNameKey}||${ingredientKey}`;
      if (seen.has(dedupeKey)) {
        continue;
      }
      seen.add(dedupeKey);

      rows.push({
        drugName,
        drugNameKey,
        ingredientName,
        ingredientKey,
        strength: normalizeDisplayText(item?.nongDo) || null,
      });
    }
  }

  return rows;
}

function buildInteractionRows(interactionPayload) {
  const records = Array.isArray(interactionPayload) ? interactionPayload : [];
  const rowMap = new Map();
  const ingredientCatalog = new Map();

  for (const record of records) {
    const ingredientA = normalizeDisplayText(record.HoatChat_1);
    const ingredientB = normalizeDisplayText(record.HoatChat_2);
    const ingredientAKey = normalizeLookupKey(ingredientA);
    const ingredientBKey = normalizeLookupKey(ingredientB);
    if (!ingredientAKey || !ingredientBKey) {
      continue;
    }

    const severityOriginal = normalizeDisplayText(record.MucDoNghiemTrong);
    const severityNormalized = normalizeInteractionSeverity(severityOriginal);
    const warning = normalizeDisplayText(record.CanhBaoTuongTacThuoc) || '';
    const warningKey = normalizeLookupKey(warning);
    const pairKey = buildInteractionPairKey(ingredientAKey, ingredientBKey);
    const dedupePayload = `${pairKey}||${severityNormalized}||${warningKey}`;
    const dedupeKey = crypto.createHash('sha1').update(dedupePayload).digest('hex');

    if (!rowMap.has(dedupeKey)) {
      rowMap.set(dedupeKey, {
        sourceId: normalizeDisplayText(record.id) || null,
        sourceDrugName: normalizeDisplayText(record.TenThuoc) || null,
        ingredientA,
        ingredientB,
        ingredientAKey,
        ingredientBKey,
        pairKey,
        severityOriginal: severityOriginal || null,
        severityNormalized,
        warning: warning || null,
        warningKey,
        dedupeKey,
      });
    }

    for (const [name, key] of [
      [ingredientA, ingredientAKey],
      [ingredientB, ingredientBKey],
    ]) {
      const current = ingredientCatalog.get(key) ?? { name, interactionCount: 0 };
      current.name = pickPreferredLabel(current.name, name);
      current.interactionCount += 1;
      ingredientCatalog.set(key, current);
    }
  }

  return {
    rows: [...rowMap.values()],
    ingredients: [...ingredientCatalog.entries()].map(([nameKey, item]) => ({
      name: item.name,
      nameKey,
      interactionCount: item.interactionCount,
    })),
  };
}

async function insertBatch(client, sqlPrefix, rows, mapRow) {
  if (rows.length === 0) {
    return;
  }

  const values = [];
  const params = [];
  let paramIndex = 1;

  for (const row of rows) {
    const mapped = mapRow(row);
    const placeholders = mapped.map(() => `$${paramIndex++}`);
    values.push(`(${placeholders.join(', ')})`);
    params.push(...mapped);
  }

  await client.query(`${sqlPrefix} VALUES ${values.join(', ')}`, params);
}

async function seedLookup() {
  console.log('🌱 Seeding local lookup data...');

  const drugPayload = loadJson(DRUG_DB_PATH);
  const interactionPayload = loadJson(INTERACTION_DB_PATH);
  const drugIngredientRows = buildDrugIngredientRows(drugPayload);
  const interactionData = buildInteractionRows(interactionPayload);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      'TRUNCATE TABLE drug_interaction_pairs, interaction_active_ingredients, drug_active_ingredients RESTART IDENTITY'
    );

    const BATCH = 500;
    for (let index = 0; index < drugIngredientRows.length; index += BATCH) {
      const batch = drugIngredientRows.slice(index, index + BATCH);
      await insertBatch(
        client,
        `INSERT INTO drug_active_ingredients
          (drug_name, drug_name_key, ingredient_name, ingredient_key, strength, source)`,
        batch,
        (row) => [
          row.drugName,
          row.drugNameKey,
          row.ingredientName,
          row.ingredientKey,
          row.strength,
          'local',
        ]
      );
    }

    for (let index = 0; index < interactionData.ingredients.length; index += BATCH) {
      const batch = interactionData.ingredients.slice(index, index + BATCH);
      await insertBatch(
        client,
        `INSERT INTO interaction_active_ingredients
          (name, name_key, interaction_count)`,
        batch,
        (row) => [row.name, row.nameKey, row.interactionCount]
      );
    }

    for (let index = 0; index < interactionData.rows.length; index += BATCH) {
      const batch = interactionData.rows.slice(index, index + BATCH);
      await insertBatch(
        client,
        `INSERT INTO drug_interaction_pairs
          (source_id, source_drug_name, ingredient_a, ingredient_b, ingredient_a_key, ingredient_b_key,
           pair_key, severity_original, severity_normalized, warning, warning_key, dedupe_key)`,
        batch,
        (row) => [
          row.sourceId,
          row.sourceDrugName,
          row.ingredientA,
          row.ingredientB,
          row.ingredientAKey,
          row.ingredientBKey,
          row.pairKey,
          row.severityOriginal,
          row.severityNormalized,
          row.warning,
          row.warningKey,
          row.dedupeKey,
        ]
      );
    }

    await client.query('COMMIT');
    console.log(`  Drug ingredients: ${drugIngredientRows.length}`);
    console.log(`  Active ingredient catalog: ${interactionData.ingredients.length}`);
    console.log(`  Interaction pairs: ${interactionData.rows.length}`);
    console.log('✅ Local lookup seed complete');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error(`❌ Local lookup seed failed: ${error.message}`);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

seedLookup();
