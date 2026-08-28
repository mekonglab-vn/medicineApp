/**
 * Integration tests — Plan routes (CRUD /api/plans)
 */
import request from 'supertest';
import app from '../../src/app.js';
import { cleanTestUsers, pool, query } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';

const PREFIX = 'test_ci_route_plan_';
const EMAIL = `${PREFIX}user@example.com`;

let accessToken;
let planId;

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
    title: 'Kế hoạch thuốc thử',
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
    notes: 'Uống sau ăn',
    ...overrides,
  };
}

beforeAll(async () => {
  await ensurePlanGroupSchema();
  await cleanTestUsers(PREFIX);
  await authService.register({ email: EMAIL, password: 'Test1234!', name: 'Plan Route Test' });
  const tokens = await authService.login({ email: EMAIL, password: 'Test1234!' });
  accessToken = tokens.accessToken;
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('POST /api/plans', () => {
  test('201: create valid plan', async () => {
    const res = await request(app)
      .post('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(planPayload());
    expect(res.status).toBe(201);
    expect(res.body.data.drugs[0].drugName).toBe('Paracetamol 500mg');
    expect(res.body.data.is_active).toBe(true);
    planId = res.body.data.id;
  });

  test('400: invalid slot payload', async () => {
    const res = await request(app)
      .post('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ ...planPayload(), slots: [] });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  test('400: invalid time format', async () => {
    const res = await request(app)
      .post('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        ...planPayload(),
        slots: [
          {
            id: 'draft-slot-0',
            time: '8am',
            sortOrder: 0,
            items: [{ drugId: 'draft-drug-0', drugName: 'Paracetamol 500mg', dosage: '500mg', pills: 1 }],
          },
        ],
      });
    expect(res.status).toBe(400);
  });

  test('401: no auth', async () => {
    const res = await request(app).post('/api/plans').send(planPayload());
    expect(res.status).toBe(401);
  });

  test('201: create plan with doseSchedule per time', async () => {
    const res = await request(app)
      .post('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(planPayload({
        title: 'Kế hoạch huyết áp',
        drugs: [{ id: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', sortOrder: 0 }],
        slots: [
          { id: 'draft-slot-0', time: '08:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', pills: 2 }] },
          { id: 'draft-slot-1', time: '20:00', sortOrder: 1, items: [{ drugId: 'draft-drug-0', drugName: 'Losartan 50mg', dosage: '50mg', pills: 1 }] },
        ],
      }));

    expect(res.status).toBe(201);
    expect(res.body.data.slots).toHaveLength(2);
    expect(res.body.data.slots.find((slot) => slot.time === '08:00').items[0].pills).toBe(2);
  });
});

describe('GET /api/plans', () => {
  test('200: returns paginated active plans', async () => {
    const res = await request(app)
      .get('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.pagination).toBeDefined();
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  test('200: active=false returns all plans', async () => {
    const res = await request(app)
      .get('/api/plans?active=false')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);
  });
});

describe('PUT /api/plans/:id', () => {
  test('200: update plan notes', async () => {
    const res = await request(app)
      .put(`/api/plans/${planId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ notes: 'Updated note' });
    expect(res.status).toBe(200);
    expect(res.body.data.notes).toBe('Updated note');
  });

  test('404: plan not found for update', async () => {
    const res = await request(app)
      .put('/api/plans/00000000-0000-0000-0000-000000000000')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ notes: 'hack' });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/plans/:id/log', () => {
  test('201: log medication as taken', async () => {
    const res = await request(app)
      .post(`/api/plans/${planId}/log`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        scheduledTime: '2026-03-10T08:00:00.000Z',
        status: 'taken',
      });
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('taken');
    expect(res.body.data.taken_at).not.toBeNull();
  });

  test('201 + idempotent: same occurrenceId updates existing log', async () => {
    const occurrenceId = `${planId}:2026-03-10:20:00`;

    const first = await request(app)
      .post(`/api/plans/${planId}/log`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        scheduledTime: '2026-03-10T20:00:00.000Z',
        status: 'skipped',
        occurrenceId,
      });
    expect(first.status).toBe(201);
    expect(first.body.data.status).toBe('skipped');

    const second = await request(app)
      .post(`/api/plans/${planId}/log`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        scheduledTime: '2026-03-10T20:00:00.000Z',
        status: 'taken',
        occurrenceId,
      });
    expect(second.status).toBe(201);
    expect(second.body.data.id).toBe(first.body.data.id);
    expect(second.body.data.status).toBe('taken');
  });

  test('400: invalid status', async () => {
    const res = await request(app)
      .post(`/api/plans/${planId}/log`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        scheduledTime: '2026-03-10T08:00:00.000Z',
        status: 'forgot', // invalid
      });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/plans/:id', () => {
  test('200: soft delete plan', async () => {
    const res = await request(app)
      .delete(`/api/plans/${planId}`)
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);

    // Deleted plan should not appear in active list
    const listRes = await request(app)
      .get('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`);
    const ids = listRes.body.data.map(p => p.id);
    expect(ids).not.toContain(planId);
  });
});

describe('GET /api/plans/today/summary', () => {
  test('200: returns expanded dose list for a date', async () => {
    const res = await request(app)
      .get('/api/plans/today/summary?date=2026-03-10')
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.date).toBe('2026-03-10');
    expect(Array.isArray(res.body.data.doses)).toBe(true);
  });

  test('200: returns per-time pill counts from doseSchedule', async () => {
    const createRes = await request(app)
      .post('/api/plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(planPayload({
        title: 'Kế hoạch telmisartan',
        drugs: [{ id: 'draft-drug-0', drugName: 'Telmisartan 40mg', dosage: '40mg', sortOrder: 0 }],
        slots: [
          { id: 'draft-slot-0', time: '08:00', sortOrder: 0, items: [{ drugId: 'draft-drug-0', drugName: 'Telmisartan 40mg', dosage: '40mg', pills: 2 }] },
          { id: 'draft-slot-1', time: '20:00', sortOrder: 1, items: [{ drugId: 'draft-drug-0', drugName: 'Telmisartan 40mg', dosage: '40mg', pills: 1 }] },
        ],
      }));

    const createdPlanId = createRes.body.data.id;
    const res = await request(app)
      .get('/api/plans/today/summary?date=2026-03-10')
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    const doses = res.body.data.doses.filter((dose) => dose.planId === createdPlanId);
    expect(doses).toHaveLength(2);
    expect(doses.find((dose) => dose.time === '08:00').pillsPerDose).toBe(2);
    expect(doses.find((dose) => dose.time === '20:00').pillsPerDose).toBe(1);
  });
});

describe('GET /api/plans/logs/all', () => {
  test('200: returns logs across all plans', async () => {
    const res = await request(app)
      .get('/api/plans/logs/all?page=1&limit=20')
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.pagination).toBeDefined();
  });
});
