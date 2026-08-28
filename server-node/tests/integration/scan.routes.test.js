/**
 * Integration tests — Scan routes (/api/scan/*)
 */
import { jest } from '@jest/globals';
import request from 'supertest';

import app from '../../src/app.js';
import { cleanTestUsers, pool, query } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';

const PREFIX = 'test_ci_route_scan_';
const EMAIL = `${PREFIX}user@example.com`;

let accessToken;
let userId;

const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7YtF4AAAAASUVORK5CYII=',
  'base64'
);

function buildMedication({
  ocrText,
  drugName,
  mappedDrugName = null,
  mappingStatus = 'confirmed',
  confidence = 0.92,
  matchScore = 0.9,
  matchBasis = 'brand_exact',
  strengthState = 'compatible',
  ambiguous = false,
  confirmationSafe = true,
  registrationNumber = 'REG-TEST',
  normalizedCandidateStrength = '500 mg',
}) {
  return {
    ocr_text: ocrText,
    drug_name: drugName,
    mapped_drug_name: mappedDrugName,
    mapping_status: mappingStatus,
    confidence,
    match_score: matchScore,
    match_basis: matchBasis,
    strength_state: strengthState,
    ambiguous,
    confirmation_safe: confirmationSafe,
    registration_number: registrationNumber,
    normalized_candidate_strength: normalizedCandidateStrength,
    bbox: [1, 2, 10, 12],
  };
}

async function ensureScanSchema() {
  await query('ALTER TABLE scans ADD COLUMN IF NOT EXISTS session_id UUID');
  await query("ALTER TABLE scans ADD COLUMN IF NOT EXISTS quality_state VARCHAR(20) DEFAULT 'GOOD'");
  await query('ALTER TABLE scans ADD COLUMN IF NOT EXISTS reject_reason VARCHAR(80)');
  await query('ALTER TABLE scans ADD COLUMN IF NOT EXISTS quality_score NUMERIC(6,3)');
  await query(`CREATE TABLE IF NOT EXISTS scan_sessions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    converged BOOLEAN DEFAULT false,
    convergence_reason VARCHAR(80),
    merged_result JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ
  )`);
}

beforeAll(async () => {
  await ensureScanSchema();
  await cleanTestUsers(PREFIX);

  const user = await authService.register({
    email: EMAIL,
    password: 'Test1234!',
    name: 'Scan Route Test',
  });
  userId = user.id;

  const tokens = await authService.login({
    email: EMAIL,
    password: 'Test1234!',
  });
  accessToken = tokens.accessToken;
});

beforeEach(async () => {
  global.fetch = jest.fn();
  await query('DELETE FROM scans WHERE user_id = $1', [userId]);
  await query('DELETE FROM scan_sessions WHERE user_id = $1', [userId]);
});

afterAll(async () => {
  await query('DELETE FROM scans WHERE user_id = $1', [userId]);
  await query('DELETE FROM scan_sessions WHERE user_id = $1', [userId]);
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('POST /api/scan', () => {
  test('200: uploads image and returns normalized drugs', async () => {
    const med = buildMedication({
      ocrText: 'Paracetamol 500mg',
      drugName: 'Paracetamol',
      mappedDrugName: 'Paracetamol',
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [med],
        medication_candidates: [med],
        quality_state: 'GOOD',
        quality_metrics: { blur_score: 120 },
        rejected: false,
      }),
    });

    const res = await request(app)
      .post('/api/scan')
      .set('Authorization', `Bearer ${accessToken}`)
      .attach('file', tinyPng, {
        filename: 'rx.png',
        contentType: 'image/png',
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data.drugs)).toBe(true);
    expect(res.body.data.drugs.length).toBeGreaterThan(0);
    expect(res.body.data.qualityState).toBe('GOOD');

    // Verify required contract alignment fields
    const drug0 = res.body.data.drugs[0];
    expect(drug0.ocrText).toBe('Paracetamol 500mg');
    expect(drug0.mappedDrugName).toBe('Paracetamol');
    expect(drug0.mappingStatus).toBe('confirmed');
    expect(drug0.matchScore).toBeDefined();
    expect(res.body.data.unresolvedCount).toBeDefined();
  });

  test('400: rejects non-image payload', async () => {
    const res = await request(app)
      .post('/api/scan')
      .set('Authorization', `Bearer ${accessToken}`)
      .attach('file', Buffer.from('not-an-image'), {
        filename: 'bad.txt',
        contentType: 'text/plain',
      });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_FILE_TYPE');
  });
});

describe('scan session flow', () => {
  test('start -> add-image -> get -> stop works', async () => {
    const med = buildMedication({
      ocrText: 'Loratadine',
      drugName: 'Loratadine',
      mappedDrugName: 'Loratadine',
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [med],
        medication_candidates: [med],
        quality_state: 'GOOD',
        quality_metrics: { blur_score: 100 },
        rejected: false,
      }),
    });

    const started = await request(app)
      .post('/api/scan/session/start')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(started.status).toBe(201);
    const sessionId = started.body.data.sessionId;
    expect(sessionId).toBeDefined();

    const added = await request(app)
      .post(`/api/scan/session/${sessionId}/add-image`)
      .set('Authorization', `Bearer ${accessToken}`)
      .attach('file', tinyPng, {
        filename: 'session.png',
        contentType: 'image/png',
      });
    expect(added.status).toBe(200);
    expect(Array.isArray(added.body.data.mergedDrugs)).toBe(true);

    const current = await request(app)
      .get(`/api/scan/session/${sessionId}`)
      .set('Authorization', `Bearer ${accessToken}`);
    expect(current.status).toBe(200);
    expect(current.body.data.sessionId).toBe(sessionId);

    const stopped = await request(app)
      .post(`/api/scan/session/${sessionId}/stop`)
      .set('Authorization', `Bearer ${accessToken}`);
    expect(stopped.status).toBe(200);
    expect(stopped.body.data.status).toBe('stopped');
  });
});

describe('GET /api/scan/history', () => {
  test('200: returns paginated history', async () => {
    const med = buildMedication({
      ocrText: 'Celecoxib',
      drugName: 'Celecoxib',
      mappedDrugName: 'Celecoxib',
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [med],
        medication_candidates: [med],
        quality_state: 'GOOD',
        quality_metrics: { blur_score: 90 },
        rejected: false,
      }),
    });

    await request(app)
      .post('/api/scan')
      .set('Authorization', `Bearer ${accessToken}`)
      .attach('file', tinyPng, {
        filename: 'history.png',
        contentType: 'image/png',
      });

    const res = await request(app)
      .get('/api/scan/history?page=1&limit=10')
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.pagination).toBeDefined();
  });

  test('200: returns detail for a single scan history item', async () => {
    const med = buildMedication({
      ocrText: 'Aspirin 81mg',
      drugName: 'Aspirin',
      mappedDrugName: 'Aspirin',
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [med],
        medication_candidates: [med],
        quality_state: 'GOOD',
        quality_metrics: { blur_score: 91 },
        guidance: 'Anh tot',
        rejected: false,
      }),
    });

    const created = await request(app)
      .post('/api/scan')
      .set('Authorization', `Bearer ${accessToken}`)
      .attach('file', tinyPng, {
        filename: 'detail.png',
        contentType: 'image/png',
      });

    const history = await request(app)
      .get('/api/scan/history?page=1&limit=10')
      .set('Authorization', `Bearer ${accessToken}`);
    const scanId = history.body.data[0].id;

    const res = await request(app)
      .get(`/api/scan/history/${scanId}`)
      .set('Authorization', `Bearer ${accessToken}`);

    expect(created.status).toBe(200);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.id).toBe(scanId);
    expect(Array.isArray(res.body.data.drugs)).toBe(true);
  });
});
