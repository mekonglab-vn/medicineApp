/**
 * Drug interaction service — local PostgreSQL lookup.
 */
import { query } from '../config/database.js';
import { AppError } from '../utils/errors.js';
import {
  INTERACTION_SEVERITY_ORDER,
  buildInteractionPairKey,
  interactionSeverityRank,
  normalizeDisplayText,
  normalizeLookupKey,
  normalizeInteractionSeverity,
} from '../utils/drugLookup.js';

const EMPTY_SUMMARY = {
  contraindicated: 0,
  major: 0,
  moderate: 0,
  minor: 0,
  caution: 0,
  unknown: 0,
};

const DEFAULT_NO_INTERACTIONS_MESSAGE =
  'Không phát hiện tương tác trong dữ liệu hiện tại.';
const DEFAULT_HAS_INTERACTIONS_MESSAGE = 'Đã tìm thấy tương tác thuốc.';

function pickFirst(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null) {
      const trimmed = String(value).trim();
      if (trimmed.length > 0) {
        return trimmed;
      }
    }
  }

  return '';
}

function toInteractionItem(rawItem = {}, severityHint = '') {
  const severityOriginal = pickFirst(
    rawItem.severity_original,
    rawItem.mucDoNghiemTrong,
    rawItem.MucDoNghiemTrong,
    rawItem.severity,
    rawItem.Severity,
    severityHint
  );

  return {
    drugA: pickFirst(
      rawItem.drugA,
      rawItem.drug_a,
      rawItem.tenThuoc1,
      rawItem.TenThuoc_1,
      rawItem.drug_name_a,
      rawItem.source_drug_name_a
    ),
    drugB: pickFirst(
      rawItem.drugB,
      rawItem.drug_b,
      rawItem.tenThuoc2,
      rawItem.TenThuoc_2,
      rawItem.drug_name_b,
      rawItem.source_drug_name_b
    ),
    ingredientA: pickFirst(
      rawItem.ingredientA,
      rawItem.ingredient_a,
      rawItem.hoatChat1,
      rawItem.HoatChat_1,
      rawItem.activeIngredient1,
      rawItem.active_ingredient_1
    ),
    ingredientB: pickFirst(
      rawItem.ingredientB,
      rawItem.ingredient_b,
      rawItem.hoatChat2,
      rawItem.HoatChat_2,
      rawItem.activeIngredient2,
      rawItem.active_ingredient_2
    ),
    severity: normalizeInteractionSeverity(severityOriginal),
    severityOriginal,
    warning: pickFirst(
      rawItem.warning,
      rawItem.canhBao,
      rawItem.CanhBaoTuongTacThuoc,
      rawItem.effect,
      rawItem.recommendations
    ),
  };
}

function summarizeInteractions(items) {
  const severitySummary = { ...EMPTY_SUMMARY };
  for (const item of items) {
    severitySummary[item.severity] = (severitySummary[item.severity] || 0) + 1;
  }

  const highest = items.length
    ? [...items].sort((a, b) => interactionSeverityRank(a.severity) - interactionSeverityRank(b.severity))[0]
      .severity
    : 'unknown';

  return {
    severitySummary,
    highestSeverity: highest,
  };
}

function sortInteractions(items) {
  return [...items].sort((a, b) => {
    const bySeverity = interactionSeverityRank(a.severity) - interactionSeverityRank(b.severity);
    if (bySeverity !== 0) {
      return bySeverity;
    }

    const aLeft = a.drugA || a.ingredientA || '';
    const bLeft = b.drugA || b.ingredientA || '';
    const byLeft = aLeft.localeCompare(bLeft, 'vi');
    if (byLeft !== 0) {
      return byLeft;
    }

    const aRight = a.drugB || a.ingredientB || '';
    const bRight = b.drugB || b.ingredientB || '';
    return aRight.localeCompare(bRight, 'vi');
  });
}

function normalizeInputList(values, fieldName) {
  const unique = [];
  const seen = new Set();

  for (const raw of values || []) {
    const display = normalizeDisplayText(raw);
    const key = normalizeLookupKey(display);
    if (!display || !key) {
      continue;
    }

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    unique.push(display);
  }

  if (unique.length < 2) {
    throw new AppError(
      `At least 2 unique ${fieldName} are required`,
      400,
      'VALIDATION_ERROR'
    );
  }

  return unique;
}

function normalizeSingleValue(value, fieldName) {
  const display = normalizeDisplayText(value);
  if (!display) {
    throw new AppError(`${fieldName} is required`, 400, 'VALIDATION_ERROR');
  }

  return display;
}

async function resolveDrugNames(drugNames) {
  const resolved = [];
  const unresolved = [];

  for (const requestedName of drugNames) {
    const requestedKey = normalizeLookupKey(requestedName);
    let row = null;

    const exact = await query(
      `SELECT DISTINCT ON (drug_name_key) drug_name
       FROM drug_active_ingredients
       WHERE drug_name_key = $1
       ORDER BY drug_name_key, drug_name ASC`,
      [requestedKey]
    );
    row = exact.rows[0] ?? null;

    if (!row) {
      const fuzzy = await query(
        `SELECT drug_name, similarity(drug_name, $1) AS score
         FROM drug_cache
         WHERE drug_name % $1 OR drug_name ILIKE $2
         ORDER BY
           CASE
             WHEN lower(drug_name) = lower($1) THEN 0
             WHEN drug_name ILIKE $3 THEN 1
             ELSE 2
           END,
           similarity(drug_name, $1) DESC,
           drug_name ASC
         LIMIT 1`,
        [requestedName, `%${requestedName}%`, `${requestedName}%`]
      );

      const candidate = fuzzy.rows[0];
      if (candidate && Number(candidate.score) >= 0.2) {
        row = candidate;
      }
    }

    if (row?.drug_name) {
      resolved.push({ requestedName, resolvedName: row.drug_name });
    } else {
      unresolved.push(requestedName);
    }
  }

  const seen = new Set();
  const uniqueResolved = [];
  for (const item of resolved) {
    const key = normalizeLookupKey(item.resolvedName);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    uniqueResolved.push(item);
  }

  return {
    resolved: uniqueResolved,
    unresolved,
  };
}

async function loadDrugIngredientRows(drugNames) {
  const keys = drugNames.map(normalizeLookupKey).filter(Boolean);
  if (keys.length === 0) {
    return [];
  }

  const result = await query(
    `SELECT drug_name, drug_name_key, ingredient_name, ingredient_key
     FROM drug_active_ingredients
     WHERE drug_name_key = ANY($1::text[])
     ORDER BY drug_name ASC, ingredient_name ASC`,
    [keys]
  );

  return result.rows;
}

async function loadInteractionRowsByIngredientKeys(ingredientKeys) {
  if (ingredientKeys.length === 0) {
    return [];
  }

  const result = await query(
    `SELECT source_id, source_drug_name, ingredient_a, ingredient_b,
            ingredient_a_key, ingredient_b_key, pair_key,
            severity_original, severity_normalized, warning, warning_key, dedupe_key
     FROM drug_interaction_pairs
     WHERE ingredient_a_key = ANY($1::text[])
       AND ingredient_b_key = ANY($1::text[])
     ORDER BY severity_normalized ASC, ingredient_a ASC, ingredient_b ASC`,
    [ingredientKeys]
  );

  return result.rows;
}

async function loadInteractionRowsForSingleIngredient(ingredientKey) {
  const result = await query(
    `SELECT source_id, source_drug_name, ingredient_a, ingredient_b,
            ingredient_a_key, ingredient_b_key, pair_key,
            severity_original, severity_normalized, warning, warning_key, dedupe_key
     FROM drug_interaction_pairs
     WHERE ingredient_a_key = $1 OR ingredient_b_key = $1
     ORDER BY severity_normalized ASC, ingredient_a ASC, ingredient_b ASC`,
    [ingredientKey]
  );

  return result.rows;
}

function groupInteractions(items) {
  const grouped = new Map();
  for (const item of items) {
    const severityOriginal = item.severityOriginal || 'Không xác định';
    const bucket = grouped.get(severityOriginal) ?? [];
    bucket.push(item);
    grouped.set(severityOriginal, bucket);
  }

  return [...grouped.entries()]
    .map(([severityOriginal, interactions]) => ({
      severity: normalizeInteractionSeverity(severityOriginal),
      severityOriginal,
      count: interactions.length,
      interactions: sortInteractions(interactions),
    }))
    .sort((a, b) => {
      const bySeverity = interactionSeverityRank(a.severity) - interactionSeverityRank(b.severity);
      if (bySeverity !== 0) {
        return bySeverity;
      }

      return a.severityOriginal.localeCompare(b.severityOriginal, 'vi');
    });
}

function buildInteractionResponse(items, message) {
  const interactions = sortInteractions(items);
  const { severitySummary, highestSeverity } = summarizeInteractions(interactions);
  const groups = groupInteractions(interactions);

  return {
    hasInteractions: interactions.length > 0,
    totalInteractions: interactions.length,
    highestSeverity,
    severitySummary,
    groups,
    interactions,
    message:
      message
      || (interactions.length > 0
        ? DEFAULT_HAS_INTERACTIONS_MESSAGE
        : DEFAULT_NO_INTERACTIONS_MESSAGE),
  };
}

function buildDrugInteractionItems(interactionRows, ingredientToDrugs) {
  const items = [];
  const seen = new Set();

  for (const row of interactionRows) {
    const leftDrugs = ingredientToDrugs.get(row.ingredient_a_key) ?? [];
    const rightDrugs = ingredientToDrugs.get(row.ingredient_b_key) ?? [];

    for (const drugA of leftDrugs) {
      for (const drugB of rightDrugs) {
        const drugPairKey = buildInteractionPairKey(drugA, drugB);
        if (!drugPairKey || normalizeLookupKey(drugA) === normalizeLookupKey(drugB)) {
          continue;
        }

        const dedupeKey = `${drugPairKey}||${row.dedupe_key}`;
        if (seen.has(dedupeKey)) {
          continue;
        }
        seen.add(dedupeKey);

        items.push(
          toInteractionItem({
            drugA,
            drugB,
            ingredient_a: row.ingredient_a,
            ingredient_b: row.ingredient_b,
            severity_original: row.severity_original,
            warning: row.warning,
          })
        );
      }
    }
  }

  return items;
}

export async function searchActiveIngredients(keyword, { limit = 20 } = {}) {
  const displayKeyword = normalizeSingleValue(keyword, 'keyword');
  const keywordKey = normalizeLookupKey(displayKeyword);
  const safeLimit = Math.max(1, Math.min(limit, 50));

  const result = await query(
    `SELECT name, interaction_count,
            CASE
              WHEN name_key LIKE $2 THEN 0
              WHEN name_key LIKE $3 THEN 1
              ELSE 2
            END AS rank,
            similarity(name, $1) AS score
     FROM interaction_active_ingredients
     WHERE name_key LIKE $3
        OR name ILIKE $4
        OR similarity(name, $1) > 0.2
     ORDER BY rank ASC, score DESC, interaction_count DESC, name ASC
     LIMIT $5`,
    [displayKeyword, `${keywordKey}%`, `%${keywordKey}%`, `%${displayKeyword}%`, safeLimit]
  );

  return {
    keyword: displayKeyword,
    suggestions: result.rows.map((row) => ({ name: row.name })),
  };
}

export async function listActiveIngredients({ keyword = '', page = 1, limit = 20 } = {}) {
  const pageValue = Math.max(1, Number(page) || 1);
  const limitValue = Math.max(1, Math.min(Number(limit) || 20, 100));
  const offset = (pageValue - 1) * limitValue;
  const displayKeyword = normalizeDisplayText(keyword);
  const keywordKey = normalizeLookupKey(displayKeyword);

  let whereSql = '';
  let whereParams = [];

  if (keywordKey) {
    whereSql = 'WHERE name_key LIKE $1 OR name ILIKE $2';
    whereParams = [`%${keywordKey}%`, `%${displayKeyword}%`];
  }

  const dataResult = await query(
    `SELECT name, interaction_count
     FROM interaction_active_ingredients
     ${whereSql}
     ORDER BY name ASC
     LIMIT $${whereParams.length + 1} OFFSET $${whereParams.length + 2}`,
    [...whereParams, limitValue, offset]
  );

  const countResult = await query(
    `SELECT COUNT(*) AS total
     FROM interaction_active_ingredients
     ${whereSql}`,
    whereParams
  );

  return {
    items: dataResult.rows.map((row) => ({
      name: row.name,
      interactionCount: Number(row.interaction_count) || 0,
    })),
    total: Number(countResult.rows[0]?.total || 0),
    page: pageValue,
    limit: limitValue,
    keyword: displayKeyword,
  };
}

export async function checkByDrugNames(drugNames) {
  const requestedDrugNames = normalizeInputList(drugNames, 'drug names');
  const resolution = await resolveDrugNames(requestedDrugNames);
  const resolvedDrugNames = resolution.resolved.map((item) => item.resolvedName);
  const ingredientRows = await loadDrugIngredientRows(resolvedDrugNames);

  const ingredientToDrugs = new Map();
  for (const row of ingredientRows) {
    const list = ingredientToDrugs.get(row.ingredient_key) ?? [];
    if (!list.includes(row.drug_name)) {
      list.push(row.drug_name);
    }
    ingredientToDrugs.set(row.ingredient_key, list);
  }

  const interactionRows = await loadInteractionRowsByIngredientKeys([...ingredientToDrugs.keys()]);
  const items = buildDrugInteractionItems(interactionRows, ingredientToDrugs);
  const response = buildInteractionResponse(items);

  return {
    requestedDrugNames,
    resolvedDrugNames,
    unresolvedDrugNames: resolution.unresolved,
    ...response,
  };
}

export async function checkByActiveIngredients(activeIngredients) {
  const requestedActiveIngredients = normalizeInputList(
    activeIngredients,
    'active ingredients'
  );
  const ingredientKeys = requestedActiveIngredients.map(normalizeLookupKey);
  const interactionRows = await loadInteractionRowsByIngredientKeys(ingredientKeys);
  const items = interactionRows.map((row) =>
    toInteractionItem({
      ingredient_a: row.ingredient_a,
      ingredient_b: row.ingredient_b,
      severity_original: row.severity_original,
      warning: row.warning,
    })
  );

  return {
    requestedActiveIngredients,
    ...buildInteractionResponse(items),
  };
}

export async function getInteractionsByActiveIngredient(ingredientName) {
  const displayIngredient = normalizeSingleValue(ingredientName, 'ingredientName');
  const ingredientKey = normalizeLookupKey(displayIngredient);
  const interactionRows = await loadInteractionRowsForSingleIngredient(ingredientKey);
  const items = interactionRows.map((row) =>
    toInteractionItem({
      ingredient_a: row.ingredient_a,
      ingredient_b: row.ingredient_b,
      severity_original: row.severity_original,
      warning: row.warning,
    })
  );

  return {
    ingredientName: displayIngredient,
    ...buildInteractionResponse(items),
  };
}

export function isHighAlertSeverity(severity) {
  const rank = INTERACTION_SEVERITY_ORDER[severity] ?? INTERACTION_SEVERITY_ORDER.unknown;
  return rank <= INTERACTION_SEVERITY_ORDER.major;
}
