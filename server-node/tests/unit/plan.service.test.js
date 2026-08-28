/**
 * Unit tests — plan.service.js
 */
import { cleanTestUsers, pool, query } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';
import * as planService from '../../src/services/plan.service.js';

const PREFIX = 'test_ci_plan_';
const EMAIL = `${PREFIX}user@example.com`;

let userId;

async function ensurePlanGroupSchema() {
  await query('ALTER TABLE medication_logs ADD COLUMN IF NOT EXISTS occurrence_id VARCHAR(120)');
  await query('DROP INDEX IF EXISTS uq_logs_plan_occurrence');
  await query('CREATE UNIQUE INDEX IF NOT EXISTS uq_logs_plan_occurrence_all ON medication_logs(plan_id, occurrence_id)');
  await query(`CREATE TABLE IF NOT EXISTS prescription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    total_days INTEGER,
    start_date DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN DEFAULT true,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  )`);
  await query(`CREATE TABLE IF NOT EXISTS prescription_plan_drugs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID REFERENCES prescription_plans(id) ON DELETE CASCADE,
    drug_name VARCHAR(255) NOT NULL,
    dosage VARCHAR(100),
    notes TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
  )`);
  await query(`CREATE TABLE IF NOT EXISTS prescription_plan_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID REFERENCES prescription_plans(id) ON DELETE CASCADE,
    time VARCHAR(5) NOT NULL,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(plan_id, time)
  )`);
  await query(`CREATE TABLE IF NOT EXISTS prescription_plan_slot_drugs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id UUID REFERENCES prescription_plan_slots(id) ON DELETE CASCADE,
    drug_id UUID REFERENCES prescription_plan_drugs(id) ON DELETE CASCADE,
    pills INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(slot_id, drug_id)
  )`);
  await query(`CREATE TABLE IF NOT EXISTS prescription_plan_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID REFERENCES prescription_plans(id) ON DELETE CASCADE,
    occurrence_id VARCHAR(120) NOT NULL,
    slot_time VARCHAR(5) NOT NULL,
    scheduled_time TIMESTAMPTZ NOT NULL,
    taken_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(plan_id, occurrence_id)
  )`);
}

function planPayload(overrides = {}) {
  return {
    title: 'Kế hoạch tim mạch',
    drugs: [
      { id: 'draft-drug-0', drugName: 'Paracetamol 500mg', dosage: '500mg', sortOrder: 0 },
    ],
    slots: [
      {
        id: 'draft-slot-0',
        time: '08:00',
        sortOrder: 0,
        items: [
          { drugId: 'draft-drug-0', drugName: 'Paracetamol 500mg', dosage: '500mg', pills: 1 },
        ],
      },
    ],
    startDate: '2026-03-10',
    totalDays: 7,
    ...overrides,
  };
}

beforeAll(async () => {
  await ensurePlanGroupSchema();
  await cleanTestUsers(PREFIX);
  // register() returns { id, email, name, created_at } directly (not { user: {...} })
  const user = await authService.register({ email: EMAIL, password: 'Test1234!', name: 'Plan Test' });
  userId = user.id;
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('createPlan()', () => {
  test('should create a medication plan', async () => {
    const plan = await planService.createPlan(userId, planPayload());
    expect(plan.id).toBeDefined();
    expect(plan.title).toBe('Kế hoạch tim mạch');
    expect(plan.drugs[0].drugName).toBe('Paracetamol 500mg');
    expect(plan.is_active).toBe(true);
  });

  test('should create a medication plan with doseSchedule', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch huyết áp',
      drugs: [{ id: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', sortOrder: 0 }],
      slots: [
        { id: 'draft-slot-0', time: '08:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', pills: 2 }] },
        { id: 'draft-slot-1', time: '20:00', sortOrder: 1, items: [{ drugId: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', pills: 1 }] },
      ],
    }));

    expect(plan.slots).toHaveLength(2);
    expect(plan.slots.find((slot) => slot.time === '08:00').items[0].pills).toBe(2);
    expect(plan.slots.find((slot) => slot.time === '20:00').items[0].pills).toBe(1);
  });
});

describe('getUserPlans()', () => {
  test('should return only active plans by default', async () => {
    // Create one more plan then delete it
    const activePlan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch kháng sinh',
      drugs: [{ id: 'draft-drug-0', drugName: 'Amoxicillin', dosage: '500mg', sortOrder: 0 }],
    }));
    // Deactivate it
    await planService.deletePlan(userId, activePlan.id);

    const { plans, total } = await planService.getUserPlans(userId, { activeOnly: true });
    expect(plans.every(p => p.is_active === true)).toBe(true);
    // Total should only count active
    const allRes = await planService.getUserPlans(userId, { activeOnly: false });
    expect(allRes.total).toBeGreaterThan(total);
  });

  test('should paginate correctly', async () => {
    const { plans } = await planService.getUserPlans(userId, { page: 1, limit: 1 });
    expect(plans.length).toBeLessThanOrEqual(1);
  });
});

describe('updatePlan()', () => {
  test('should update allowed fields', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch giảm đau',
      drugs: [{ id: 'draft-drug-0', drugName: 'Ibuprofen 400mg', dosage: '400mg', sortOrder: 0 }],
    }));
    const updated = await planService.updatePlan(userId, plan.id, {
      notes: 'Uống sau ăn',
      pillsPerDose: 2,
    });
    expect(updated.notes).toBe('Uống sau ăn');
  });

  test('should throw 400 if no fields to update', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch vitamin',
      drugs: [{ id: 'draft-drug-0', drugName: 'Vitamin C', dosage: '500mg', sortOrder: 0 }],
    }));
    await expect(
      planService.updatePlan(userId, plan.id, {})
    ).rejects.toMatchObject({ statusCode: 400, code: 'NO_UPDATES' });
  });

  test('should throw 404 for wrong user (ownership check)', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch aspirin',
      drugs: [{ id: 'draft-drug-0', drugName: 'Aspirin', dosage: '81mg', sortOrder: 0 }],
    }));
    const fakeUserId = '00000000-0000-0000-0000-000000000000';
    await expect(
      planService.updatePlan(fakeUserId, plan.id, { notes: 'hack' })
    ).rejects.toMatchObject({ statusCode: 404, code: 'PLAN_NOT_FOUND' });
  });
});

describe('deletePlan()', () => {
  test('should soft-delete plan (set is_active=false)', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch dị ứng',
      drugs: [{ id: 'draft-drug-0', drugName: 'Cetirizine', dosage: '10mg', sortOrder: 0 }],
      slots: [{ id: 'draft-slot-0', time: '22:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Cetirizine', dosage: '10mg', pills: 1 }] }],
    }));
    await planService.deletePlan(userId, plan.id);

    const result = await query(
      'SELECT is_active FROM prescription_plans WHERE id = $1',
      [plan.id]
    );
    expect(result.rows[0].is_active).toBe(false);
  });
});

describe('logMedication()', () => {
  test('should log a taken dose', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch dạ dày',
      drugs: [{ id: 'draft-drug-0', drugName: 'Omeprazole', dosage: '20mg', sortOrder: 0 }],
    }));
    const log = await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'taken',
    });
    expect(log.status).toBe('taken');
    expect(log.taken_at).not.toBeNull();
  });

  test('should set taken_at=null for missed dose', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch đái tháo đường',
      drugs: [{ id: 'draft-drug-0', drugName: 'Metformin', dosage: '500mg', sortOrder: 0 }],
    }));
    const log = await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'missed',
    });
    expect(log.status).toBe('missed');
    expect(log.taken_at).toBeNull();
  });

  test('should upsert log by occurrenceId (idempotent)', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch huyết áp 2',
      drugs: [{ id: 'draft-drug-0', drugName: 'Amlodipine', dosage: '5mg', sortOrder: 0 }],
    }));

    const occurrenceId = `${plan.id}:2026-03-10:08:00`;
    const first = await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'skipped',
      occurrenceId,
    });
    const second = await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'taken',
      occurrenceId,
    });

    expect(second.id).toBe(first.id);
    expect(second.status).toBe('taken');
  });
});

describe('getPlanLogs()', () => {
  test('should return logs for a plan', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch mỡ máu',
      drugs: [{ id: 'draft-drug-0', drugName: 'Atorvastatin', dosage: '10mg', sortOrder: 0 }],
    }));
    await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'taken',
    });
    const logs = await planService.getPlanLogs(plan.id, userId);
    expect(logs.length).toBeGreaterThan(0);
  });

  test('should throw 404 for unauthorized plan access', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch test',
      drugs: [{ id: 'draft-drug-0', drugName: 'Test Drug', dosage: '10mg', sortOrder: 0 }],
    }));
    const fakeUserId = '00000000-0000-0000-0000-000000000000';
    await expect(
      planService.getPlanLogs(plan.id, fakeUserId)
    ).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe('getTodaySchedule()', () => {
  test('should return expanded doses with status summary', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch mỡ máu 2',
      drugs: [{ id: 'draft-drug-0', drugName: 'Rosuvastatin', dosage: '10mg', sortOrder: 0 }],
      slots: [
        { id: 'draft-slot-0', time: '08:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Rosuvastatin', dosage: '10mg', pills: 1 }] },
        { id: 'draft-slot-1', time: '20:00', sortOrder: 1, items: [{ drugId: 'draft-drug-0', drugName: 'Rosuvastatin', dosage: '10mg', pills: 1 }] },
      ],
    }));

    await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-10T08:00:00Z',
      status: 'taken',
      occurrenceId: `${plan.id}:2026-03-10:08:00`,
    });

    const schedule = await planService.getTodaySchedule(userId, {
      date: '2026-03-10',
    });

    expect(schedule.date).toBe('2026-03-10');
    expect(schedule.doses.length).toBeGreaterThan(0);
    expect(schedule.summary.total).toBe(schedule.doses.length);
    expect(schedule.summary.taken).toBeGreaterThanOrEqual(1);
  });

  test('should expand doseSchedule with correct pills per occurrence', async () => {
    const plan = await planService.createPlan(userId, planPayload({
      title: 'Kế hoạch perindopril',
      drugs: [{ id: 'draft-drug-0', drugName: 'Perindopril 4mg', dosage: '4mg', sortOrder: 0 }],
      slots: [
        { id: 'draft-slot-0', time: '08:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Perindopril 4mg', dosage: '4mg', pills: 2 }] },
        { id: 'draft-slot-1', time: '20:00', sortOrder: 1, items: [{ drugId: 'draft-drug-0', drugName: 'Perindopril 4mg', dosage: '4mg', pills: 1 }] },
      ],
    }));

    const schedule = await planService.getTodaySchedule(userId, {
      date: '2026-03-10',
    });

    const doses = schedule.doses.filter((dose) => dose.planId === plan.id);
    expect(doses).toHaveLength(2);
    expect(doses.find((dose) => dose.time === '08:00').pillsPerDose).toBe(2);
    expect(doses.find((dose) => dose.time === '20:00').pillsPerDose).toBe(1);
  });
});

describe('getUserMedicationLogs()', () => {
  test('should return cross-plan logs for user', async () => {
    const plan = await planService.createPlan(userId, {
      title: 'Kế hoạch tăng huyết áp',
      drugs: [{ id: 'draft-drug-0', drugName: 'Perindopril', dosage: '4mg', sortOrder: 0 }],
      slots: [{ id: 'draft-slot-0', time: '07:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Perindopril', dosage: '4mg', pills: 1 }] }],
      startDate: '2026-03-11',
    });

    await planService.logMedication(plan.id, userId, {
      scheduledTime: '2026-03-11T07:00:00Z',
      status: 'taken',
      occurrenceId: `${plan.id}:2026-03-11:07:00`,
    });

    const result = await planService.getUserMedicationLogs(userId, {
      date: '2026-03-11',
      page: 1,
      limit: 20,
    });

    expect(result.total).toBeGreaterThan(0);
    expect(result.logs.length).toBeGreaterThan(0);
    expect(result.logs[0].drug_name).toBeDefined();
  });
});
