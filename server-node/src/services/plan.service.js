/**
 * Plan service — prescription plan group CRUD + logs.
 */
import { query } from '../config/database.js';
import { AppError } from '../utils/errors.js';

function normalizeDateKey(dateStr) {
  if (!dateStr || typeof dateStr !== 'string') return null;
  const trimmed = dateStr.trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(trimmed) ? trimmed : null;
}

function normalizeTime(value) {
  const time = String(value || '').slice(0, 5);
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(time) ? time : null;
}

function buildScheduledIso(dateKey, time) {
  const normalizedTime = normalizeTime(time);
  if (!normalizedTime) return null;
  const dt = new Date(`${dateKey}T${normalizedTime}:00+07:00`);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

function buildOccurrenceId(planId, scheduledTime, providedOccurrenceId) {
  if (providedOccurrenceId && typeof providedOccurrenceId === 'string') {
    const cleaned = providedOccurrenceId.trim();
    if (cleaned.length > 0) return cleaned.slice(0, 120);
  }
  const dt = new Date(scheduledTime);
  if (Number.isNaN(dt.getTime())) return null;
  const iso = dt.toISOString();
  return `${planId}:${iso.slice(0, 10)}:${iso.slice(11, 16)}`;
}

function derivePlanTitle(row, drugs) {
  if (row.title && row.title.trim()) return row.title;
  if (!drugs.length) return 'Kế hoạch thuốc';
  if (drugs.length === 1) return drugs[0].drugName;
  const preview = drugs.slice(0, 2).map((drug) => drug.drugName).join(', ');
  return `${preview}${drugs.length > 2 ? ` và ${drugs.length - 2} thuốc khác` : ''}`;
}

async function hydratePlanRow(row) {
  const drugsResult = await query(
    `SELECT id, drug_name, dosage, notes, sort_order
     FROM prescription_plan_drugs
     WHERE plan_id = $1
     ORDER BY sort_order ASC, created_at ASC`,
    [row.id],
  );

  const slotsResult = await query(
    `SELECT s.id,
            s.time,
            s.sort_order,
            COALESCE(
              jsonb_agg(
                jsonb_build_object(
                  'drugId', d.id,
                  'drugName', d.drug_name,
                  'dosage', d.dosage,
                  'pills', sd.pills
                )
                ORDER BY d.sort_order ASC, d.created_at ASC
              ) FILTER (WHERE d.id IS NOT NULL),
              '[]'::jsonb
            ) AS items
     FROM prescription_plan_slots s
     LEFT JOIN prescription_plan_slot_drugs sd ON sd.slot_id = s.id
     LEFT JOIN prescription_plan_drugs d ON d.id = sd.drug_id
     WHERE s.plan_id = $1
     GROUP BY s.id, s.time, s.sort_order
     ORDER BY s.sort_order ASC, s.time ASC`,
    [row.id],
  );

  const drugs = drugsResult.rows.map((drug) => ({
    id: drug.id,
    drugName: drug.drug_name,
    dosage: drug.dosage,
    notes: drug.notes,
    sortOrder: drug.sort_order,
  }));

  const slots = slotsResult.rows.map((slot) => ({
    id: slot.id,
    time: slot.time,
    sortOrder: slot.sort_order,
    items: Array.isArray(slot.items) ? slot.items : [],
  }));

  return {
    id: row.id,
    title: derivePlanTitle(row, drugs),
    drugs,
    slots,
    total_days: row.total_days,
    start_date: row.start_date,
    end_date: row.end_date,
    is_active: row.is_active,
    notes: row.notes,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function ensurePlanOwnership(userId, planId) {
  const result = await query(
    'SELECT * FROM prescription_plans WHERE id = $1 AND user_id = $2',
    [planId, userId],
  );
  if (!result.rows.length) {
    throw new AppError('Plan not found', 404, 'PLAN_NOT_FOUND');
  }
  return result.rows[0];
}

async function replacePlanChildren(execute, planId, drugs = [], slots = []) {
  await execute('DELETE FROM prescription_plan_slot_drugs WHERE slot_id IN (SELECT id FROM prescription_plan_slots WHERE plan_id = $1)', [planId]);
  await execute('DELETE FROM prescription_plan_slots WHERE plan_id = $1', [planId]);
  await execute('DELETE FROM prescription_plan_drugs WHERE plan_id = $1', [planId]);

  const drugIdByTempKey = new Map();
  for (let i = 0; i < drugs.length; i += 1) {
    const drug = drugs[i];
    const inserted = await execute(
      `INSERT INTO prescription_plan_drugs (plan_id, drug_name, dosage, notes, sort_order)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id`,
      [planId, drug.drugName, drug.dosage || null, drug.notes || null, drug.sortOrder ?? i],
    );
    const insertedId = inserted.rows[0].id;
    const tempKeys = [drug.id, drug.drugName, `${i}`].filter(Boolean);
    for (const key of tempKeys) {
      if (!drugIdByTempKey.has(key)) {
        drugIdByTempKey.set(key, insertedId);
      }
    }
  }

  for (let i = 0; i < slots.length; i += 1) {
    const slot = slots[i];
    const time = normalizeTime(slot.time);
    if (!time) continue;

    const insertedSlot = await execute(
      `INSERT INTO prescription_plan_slots (plan_id, time, sort_order)
       VALUES ($1, $2, $3)
       RETURNING id`,
      [planId, time, slot.sortOrder ?? i],
    );
    const slotId = insertedSlot.rows[0].id;

    for (const item of slot.items || []) {
      let drugId = item.drugId ? drugIdByTempKey.get(item.drugId) : null;
      if (!drugId && item.drugName) {
        drugId = drugIdByTempKey.get(item.drugName);
      }
      if (!drugId) continue;

      await execute(
        `INSERT INTO prescription_plan_slot_drugs (slot_id, drug_id, pills)
         VALUES ($1, $2, $3)`,
        [slotId, drugId, Number.parseInt(item.pills, 10) || 1],
      );
    }
  }
}

export async function createPlan(userId, data) {
  try {
    const title = String(data.title || '').trim() || null;
    const result = await query(
      `INSERT INTO prescription_plans (user_id, title, total_days, start_date, end_date, notes)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [userId, title, data.totalDays || null, data.startDate, data.endDate || null, data.notes || null],
    );
    const planRow = result.rows[0];
    await replacePlanChildren(query, planRow.id, data.drugs || [], data.slots || []);
    return getPlanById(userId, planRow.id);
  } catch (error) {
    throw error;
  }
}

export async function getUserPlans(userId, { page = 1, limit = 20, activeOnly = true } = {}) {
  const offset = (page - 1) * limit;
  const result = await query(
    `SELECT * FROM prescription_plans
     WHERE user_id = $1
       AND (
         $2::boolean IS FALSE OR (
           is_active = true
           AND (end_date IS NULL OR end_date >= CURRENT_DATE)
         )
       )
     ORDER BY created_at DESC
     LIMIT $3 OFFSET $4`,
    [userId, activeOnly, limit, offset],
  );

  const countResult = await query(
    `SELECT COUNT(*) FROM prescription_plans
     WHERE user_id = $1
       AND (
         $2::boolean IS FALSE OR (
           is_active = true
           AND (end_date IS NULL OR end_date >= CURRENT_DATE)
         )
       )`,
    [userId, activeOnly],
  );

  const plans = [];
  for (const row of result.rows) {
    plans.push(await hydratePlanRow(row));
  }
  return {
    plans,
    total: Number.parseInt(countResult.rows[0].count, 10),
  };
}

export async function getPlanById(userId, planId) {
  const row = await ensurePlanOwnership(userId, planId);
  return hydratePlanRow(row);
}

export async function updatePlan(userId, planId, data) {
  await ensurePlanOwnership(userId, planId);

  const fields = [];
  const values = [];
  let idx = 1;
  const mapping = {
    title: 'title',
    totalDays: 'total_days',
    startDate: 'start_date',
    endDate: 'end_date',
    isActive: 'is_active',
    notes: 'notes',
  };
  for (const [jsKey, dbKey] of Object.entries(mapping)) {
    if (data[jsKey] !== undefined) {
      fields.push(`${dbKey} = $${idx}`);
      values.push(data[jsKey]);
      idx += 1;
    }
  }

  const hasChildrenUpdate = data.drugs !== undefined || data.slots !== undefined;
  if (fields.length === 0 && !hasChildrenUpdate) {
    throw new AppError('No fields to update', 400, 'NO_UPDATES');
  }

  try {
    if (fields.length > 0) {
      values.push(planId, userId);
      await query(
        `UPDATE prescription_plans SET ${fields.join(', ')}, updated_at = NOW()
         WHERE id = $${idx} AND user_id = $${idx + 1}`,
        values,
      );
    }

    if (hasChildrenUpdate) {
      await replacePlanChildren(query, planId, data.drugs || [], data.slots || []);
    }
    return getPlanById(userId, planId);
  } catch (error) {
    throw error;
  }
}

export async function deletePlan(userId, planId) {
  await ensurePlanOwnership(userId, planId);
  await query(
    'UPDATE prescription_plans SET is_active = false, updated_at = NOW() WHERE id = $1 AND user_id = $2',
    [planId, userId],
  );
}

export async function logMedication(planId, userId, data) {
  await ensurePlanOwnership(userId, planId);
  const occurrenceId = buildOccurrenceId(planId, data.scheduledTime, data.occurrenceId);
  if (!occurrenceId) {
    throw new AppError('Invalid occurrence', 400, 'INVALID_OCCURRENCE');
  }
  const dt = new Date(data.scheduledTime);
  const slotTime = dt.toISOString().slice(11, 16);
  const takenAt = data.status === 'taken' ? new Date().toISOString() : null;

  const result = await query(
    `INSERT INTO prescription_plan_logs (plan_id, occurrence_id, slot_time, scheduled_time, taken_at, status, note)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (plan_id, occurrence_id)
     DO UPDATE SET
       slot_time = EXCLUDED.slot_time,
       scheduled_time = EXCLUDED.scheduled_time,
       taken_at = EXCLUDED.taken_at,
       status = EXCLUDED.status,
       note = COALESCE(EXCLUDED.note, prescription_plan_logs.note),
       updated_at = NOW()
     RETURNING *`,
    [planId, occurrenceId, slotTime, data.scheduledTime, takenAt, data.status, data.note || null],
  );
  return result.rows[0];
}

export async function getPlanLogs(planId, userId) {
  await ensurePlanOwnership(userId, planId);
  const result = await query(
    `SELECT * FROM prescription_plan_logs WHERE plan_id = $1 ORDER BY scheduled_time DESC`,
    [planId],
  );
  return result.rows;
}

export async function getUserMedicationLogs(userId, { date = null, page = 1, limit = 20 } = {}) {
  const offset = (page - 1) * limit;
  const dateKey = normalizeDateKey(date);
  const clauses = ['p.user_id = $1'];
  const params = [userId];
  if (dateKey) {
    params.push(dateKey);
    clauses.push(`l.scheduled_time::date = $2::date`);
  }
  params.push(limit, offset);
  const limitIdx = params.length - 1;
  const offsetIdx = params.length;

  const result = await query(
    `SELECT l.*, p.title
     FROM prescription_plan_logs l
     JOIN prescription_plans p ON p.id = l.plan_id
     WHERE ${clauses.join(' AND ')}
     ORDER BY l.scheduled_time DESC
     LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
    params,
  );
  const countResult = await query(
    `SELECT COUNT(*)
     FROM prescription_plan_logs l
     JOIN prescription_plans p ON p.id = l.plan_id
     WHERE ${clauses.join(' AND ')}`,
    params.slice(0, params.length - 2),
  );

  return {
    logs: result.rows.map((row) => ({
      ...row,
      drug_name: row.title,
    })),
    total: Number.parseInt(countResult.rows[0].count, 10),
  };
}

export async function getTodaySchedule(userId, { date = null } = {}) {
  const dateKey = normalizeDateKey(date) || new Date().toISOString().slice(0, 10);
  const plansResult = await query(
    `SELECT * FROM prescription_plans
     WHERE user_id = $1
       AND is_active = true
       AND start_date <= $2::date
       AND (end_date IS NULL OR end_date >= $2::date)
     ORDER BY created_at DESC`,
    [userId, dateKey],
  );

  if (!plansResult.rows.length) {
    return {
      date: dateKey,
      doses: [],
      summary: { total: 0, taken: 0, pending: 0, skipped: 0, missed: 0 },
    };
  }

  const doses = [];
  for (const row of plansResult.rows) {
    const plan = await hydratePlanRow(row);
    for (const slot of plan.slots) {
      const scheduledTime = buildScheduledIso(dateKey, slot.time);
      if (!scheduledTime) continue;
      doses.push({
        occurrenceId: `${plan.id}:${dateKey}:${slot.time}`,
        planId: plan.id,
        title: plan.title,
        drugName: slot.items.map((item) => item.drugName).join(', '),
        time: slot.time,
        scheduledTime,
        status: 'pending',
        pillsPerDose: slot.items.reduce((sum, item) => sum + item.pills, 0),
        doseSchedule: slot.items.map((item) => ({ drugName: item.drugName, pills: item.pills })),
        medications: slot.items,
        notes: plan.notes,
        takenAt: null,
        note: null,
      });
    }
  }

  const occurrenceIds = doses.map((dose) => dose.occurrenceId);
  const logsResult = await query(
    `SELECT * FROM prescription_plan_logs
     WHERE plan_id = ANY($1::uuid[])
       AND occurrence_id = ANY($2::text[])
     ORDER BY scheduled_time DESC`,
    [plansResult.rows.map((row) => row.id), occurrenceIds],
  );
  const logByOccurrence = new Map(logsResult.rows.map((row) => [row.occurrence_id, row]));
  for (const dose of doses) {
    const log = logByOccurrence.get(dose.occurrenceId);
    if (!log) continue;
    dose.status = log.status || 'pending';
    dose.takenAt = log.taken_at || null;
    dose.note = log.note || null;
  }

  doses.sort((a, b) => a.time.localeCompare(b.time));
  const summary = doses.reduce(
    (acc, dose) => {
      acc.total += 1;
      acc[dose.status] = (acc[dose.status] || 0) + 1;
      return acc;
    },
    { total: 0, taken: 0, pending: 0, skipped: 0, missed: 0 },
  );
  return { date: dateKey, doses, summary };
}
