import { jest } from '@jest/globals';
import { cleanTestUsers, pool, query } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';
import * as scanService from '../../src/services/scan.service.js';

const PREFIX = 'test_ci_scan_';
const EMAIL = `${PREFIX}user@example.com`;

let userId;

function buildMedication({
  ocrText,
  drugName,
  mappedDrugName = null,
  mappingStatus,
  confidence,
  matchScore = 0,
  matchBasis = 'none',
  strengthState = 'unknown_candidate',
  ambiguous = false,
  resolutionReason = null,
  confirmationSafe = false,
  registrationNumber = null,
  normalizedCandidateStrength = null,
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
    resolution_reason: resolutionReason,
    confirmation_safe: confirmationSafe,
    registration_number: registrationNumber,
    normalized_candidate_strength: normalizedCandidateStrength,
    bbox: [1, 2, 3, 4],
  };
}

async function ensureScanSessionSchema() {
  await query(`ALTER TABLE scans ADD COLUMN IF NOT EXISTS session_id UUID;`);
  await query(`ALTER TABLE scans ADD COLUMN IF NOT EXISTS quality_state VARCHAR(20) DEFAULT 'GOOD';`);
  await query(`ALTER TABLE scans ADD COLUMN IF NOT EXISTS reject_reason VARCHAR(80);`);
  await query(`ALTER TABLE scans ADD COLUMN IF NOT EXISTS quality_score NUMERIC(6,3);`);
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
  );`);
}

async function ensureMedicationLogOccurrenceSchema() {
  await query('ALTER TABLE medication_logs ADD COLUMN IF NOT EXISTS occurrence_id VARCHAR(120)');
  await query('DROP INDEX IF EXISTS uq_logs_plan_occurrence');
  await query('CREATE UNIQUE INDEX IF NOT EXISTS uq_logs_plan_occurrence_all ON medication_logs(plan_id, occurrence_id)');
}

beforeAll(async () => {
  await ensureScanSessionSchema();
  await ensureMedicationLogOccurrenceSchema();
  await cleanTestUsers(PREFIX);
  const user = await authService.register({
    email: EMAIL,
    password: 'Test1234!',
    name: 'Scan Test',
  });
  userId = user.id;
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

describe('scan sessions', () => {
  test('start/add/get/stop persists session state in DB', async () => {
    const confirmed = buildMedication({
      ocrText: 'Paracetamol 500mg',
      drugName: 'Paracetamol',
      mappedDrugName: 'Paracetamol',
      mappingStatus: 'confirmed',
      confidence: 0.96,
      matchScore: 0.93,
      matchBasis: 'brand_exact',
      strengthState: 'compatible',
      resolutionReason: 'exact_brand_compatible_strength',
      confirmationSafe: true,
      registrationNumber: 'REG-PARA-500',
      normalizedCandidateStrength: '500 mg',
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [confirmed],
        medication_candidates: [confirmed],
        quality_state: 'GOOD',
        quality_metrics: { blur_score: 120 },
        roi_mode: 'table_roi',
        roi_bbox: [10, 20, 300, 420],
        roi_offset: [10, 20],
        rejected: false,
      }),
    });

    const started = await scanService.startScanSession(userId);
    const added = await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image'),
      'scan.jpg',
      'image/jpeg'
    );
    const current = await scanService.getScanSession(started.sessionId, userId);
    const stopped = await scanService.stopScanSession(started.sessionId, userId);

    expect(added.mergedDrugs).toHaveLength(1);
    expect(current.images).toHaveLength(1);
    expect(stopped.status).toBe('stopped');

    const persisted = await query(
      'SELECT status, merged_result FROM scan_sessions WHERE id = $1 AND user_id = $2',
      [started.sessionId, userId]
    );
    expect(persisted.rows[0].status).toBe('stopped');
    expect(persisted.rows[0].merged_result[0].name).toBe('Paracetamol');
    expect(persisted.rows[0].merged_result[0]).toMatchObject({
      matchBasis: 'brand_exact',
      strengthState: 'compatible',
      ambiguous: false,
      resolutionReason: 'exact_brand_compatible_strength',
      confirmationSafe: true,
    });
  });

  test('does not converge early on low-confidence repeated results', async () => {
    const unresolved = buildMedication({
      ocrText: 'Mystery Capsule',
      drugName: 'Mystery Capsule',
      mappingStatus: 'unmapped_candidate',
      confidence: 0.52,
      matchScore: 0,
    });

    global.fetch
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          medications: [unresolved],
          medication_candidates: [unresolved],
          quality_state: 'GOOD',
          quality_metrics: { blur_score: 95 },
          rejected: false,
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          medications: [unresolved],
          medication_candidates: [unresolved],
          quality_state: 'GOOD',
          quality_metrics: { blur_score: 96 },
          rejected: false,
        }),
      });

    const started = await scanService.startScanSession(userId);
    await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image-1'),
      'scan-1.jpg',
      'image/jpeg'
    );
    const second = await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image-2'),
      'scan-2.jpg',
      'image/jpeg'
    );

    expect(second.converged).toBe(false);
    expect(second.convergenceReason).toBeNull();
    expect(second.mergedDrugs[0].mappingStatus).toBe('unmapped_candidate');
  });

  test('keeps unsafe candidates distinct by raw identity despite the same mapped product', async () => {
    const first = buildMedication({
      ocrText: 'Sharedol 10mg',
      drugName: 'Sharedol 10mg',
      mappedDrugName: 'Shared Brand A',
      mappingStatus: 'unmapped_candidate',
      confidence: 0.94,
      matchScore: 1,
      matchBasis: 'ingredient_exact',
      strengthState: 'compatible',
      resolutionReason: 'ingredient_only',
      confirmationSafe: false,
    });
    const second = buildMedication({
      ocrText: 'Sharedol 20mg',
      drugName: 'Sharedol 20mg',
      mappedDrugName: 'Shared Brand A',
      mappingStatus: 'unmapped_candidate',
      confidence: 0.93,
      matchScore: 1,
      matchBasis: 'ingredient_exact',
      strengthState: 'mismatch',
      resolutionReason: 'ingredient_only',
      confirmationSafe: false,
    });

    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        medications: [first, second],
        medication_candidates: [first, second],
        quality_state: 'GOOD',
        rejected: false,
      }),
    });

    const started = await scanService.startScanSession(userId);
    const added = await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image'),
      'unsafe-candidates.jpg',
      'image/jpeg'
    );

    expect(added.mergedDrugs).toHaveLength(2);
    expect(added.mergedDrugs.map((drug) => drug.name).sort()).toEqual([
      'Sharedol 10mg',
      'Sharedol 20mg',
    ]);
    expect(added.mergedDrugs.filter(
      (drug) => drug.mappingStatus === 'unmapped_candidate'
    )).toHaveLength(2);
  });

  test('keeps confirmed same-brand products distinct and does not falsely converge', async () => {
    const fifty = buildMedication({
      ocrText: 'Cardiol',
      drugName: 'Cardiol',
      mappedDrugName: 'Cardiol',
      mappingStatus: 'confirmed',
      confidence: 0.98,
      matchScore: 1,
      matchBasis: 'brand_exact',
      strengthState: 'compatible',
      resolutionReason: 'exact_brand_compatible_strength',
      confirmationSafe: true,
      registrationNumber: 'REG-CARDIOL-50',
      normalizedCandidateStrength: '50 mg',
    });
    const hundred = buildMedication({
      ocrText: 'Cardiol',
      drugName: 'Cardiol',
      mappedDrugName: 'Cardiol',
      mappingStatus: 'confirmed',
      confidence: 0.98,
      matchScore: 1,
      matchBasis: 'brand_exact',
      strengthState: 'compatible',
      resolutionReason: 'exact_brand_compatible_strength',
      confirmationSafe: true,
      registrationNumber: 'REG-CARDIOL-100',
      normalizedCandidateStrength: '100 mg',
    });

    global.fetch
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          medications: [fifty],
          medication_candidates: [fifty],
          quality_state: 'GOOD',
          rejected: false,
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          medications: [hundred],
          medication_candidates: [hundred],
          quality_state: 'GOOD',
          rejected: false,
        }),
      });

    const started = await scanService.startScanSession(userId);
    await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image-50'),
      'cardiol-50.jpg',
      'image/jpeg'
    );
    const second = await scanService.addImageToSession(
      started.sessionId,
      userId,
      Buffer.from('fake-image-100'),
      'cardiol-100.jpg',
      'image/jpeg'
    );

    expect(second.mergedDrugs).toHaveLength(2);
    expect(second.mergedDrugs.map((drug) => drug.registrationNumber).sort()).toEqual([
      'REG-CARDIOL-100',
      'REG-CARDIOL-50',
    ]);
    expect(second.converged).toBe(false);
    expect(second.convergenceReason).toBeNull();
  });
});
