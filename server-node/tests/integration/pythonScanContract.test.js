import { jest } from '@jest/globals';

const queryMock = jest.fn();

jest.unstable_mockModule('../../src/config/database.js', () => ({
  query: queryMock,
}));
jest.unstable_mockModule('../../src/config/env.js', () => ({
  env: { PYTHON_API_URL: 'http://python.test' },
}));

const { scanPrescription } = await import('../../src/services/scan.service.js');

function upstreamResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: jest.fn().mockResolvedValue(body),
    text: jest.fn().mockResolvedValue(JSON.stringify(body)),
  };
}

async function expectFailure(response, status, code) {
  global.fetch = jest.fn().mockResolvedValue(response);

  await expect(scanPrescription(
    Buffer.from('image'),
    'user-id',
    'prescription.jpg'
  )).rejects.toMatchObject({ statusCode: status, code });
  expect(queryMock).not.toHaveBeenCalled();
}

beforeEach(() => {
  queryMock.mockReset();
  global.fetch = jest.fn();
});

describe('Python scan failure contract', () => {
  test.each([
    [503, 'PIPELINE_UNAVAILABLE'],
    [500, 'PIPELINE_EXECUTION_FAILED'],
    [422, 'SCAN_PROCESSING_FAILED'],
  ])('preserves upstream HTTP %i and machine code %s', async (status, code) => {
    await expectFailure(upstreamResponse(status, {
      detail: { code, message: `upstream ${code}` },
    }), status, code);
  });

  test('retains timeout status and code without persistence', async () => {
    global.fetch.mockRejectedValue(Object.assign(new Error('aborted'), { name: 'AbortError' }));

    await expect(scanPrescription(
      Buffer.from('image'),
      'user-id',
      'prescription.jpg'
    )).rejects.toMatchObject({ statusCode: 504, code: 'SCAN_TIMEOUT' });
    expect(queryMock).not.toHaveBeenCalled();
  });

  test('rejects a legacy HTTP-200 mock payload before normalization or persistence', async () => {
    await expectFailure(upstreamResponse(200, {
      mock: true,
      medications: [{ drug_name: 'Mock-Paracetamol-500mg' }],
    }), 503, 'PIPELINE_UNAVAILABLE');
  });

  test('rejects a legacy HTTP-200 terminal error before normalization or persistence', async () => {
    await expectFailure(upstreamResponse(200, {
      error: 'No prescription region could be processed',
    }), 422, 'SCAN_PROCESSING_FAILED');
  });

  test('keeps the existing successful payload normalization and persists once', async () => {
    const confirmed = {
      drug_name_raw: 'Paracetamol 500mg',
      drug_name: 'Paracetamol',
      ocr_text: 'Paracetamol 500mg',
      matched_drug_name: 'Paracetamol',
      mapping_status: 'confirmed',
      confidence: 0.95,
      match_score: 0.91,
      match_basis: 'brand_exact',
      strength_state: 'compatible',
      ambiguous: false,
      resolution_reason: 'exact_brand_compatible_strength',
      confirmation_safe: true,
      registration_number: 'REG-PARA-500',
      normalized_candidate_strength: '500 mg',
    };
    const rejected = {
      drug_name_raw: '10ml',
      drug_name: '10ml',
      ocr_text: '10ml',
      mapping_status: 'rejected_noise',
      confidence: 0.8,
      match_score: 0,
      confirmation_safe: false,
    };
    global.fetch.mockResolvedValue(upstreamResponse(200, {
      medications: [confirmed],
      medication_candidates: [confirmed, rejected],
      quality_state: 'GOOD',
      quality_metrics: { blur_score: 100 },
      rejected: false,
    }));
    queryMock.mockResolvedValue({ rows: [] });

    const result = await scanPrescription(
      Buffer.from('image'),
      'user-id',
      'prescription.jpg'
    );

    expect(result.qualityState).toBe('GOOD');
    expect(result.drugs).toHaveLength(1);
    expect(result.drugs[0]).toMatchObject({
      name: 'Paracetamol 500mg',
      ocrText: 'Paracetamol 500mg',
      mappedDrugName: 'Paracetamol',
      mappingStatus: 'confirmed',
      matchBasis: 'brand_exact',
      strengthState: 'compatible',
      ambiguous: false,
      resolutionReason: 'exact_brand_compatible_strength',
      confirmationSafe: true,
      registrationNumber: 'REG-PARA-500',
      normalizedCandidateStrength: '500 mg',
    });
    expect(result.candidates).toHaveLength(2);
    expect(result.candidates[1].mappingStatus).toBe('rejected_noise');
    expect(queryMock).toHaveBeenCalledTimes(1);
  });

  test('keeps legacy mapped name as metadata but does not trust unsafe confirmation', async () => {
    global.fetch.mockResolvedValue(upstreamResponse(200, {
      medications: [{
        drug_name_raw: 'Legacy OCR 50mg',
        ocr_text: 'Legacy OCR 50mg',
        mapped_drug_name: 'Arbitrary Product 50mg',
        mapping_status: 'confirmed',
        confidence: 0.9,
        match_score: 0.99,
      }],
      quality_state: 'GOOD',
      rejected: false,
    }));
    queryMock.mockResolvedValue({ rows: [] });

    const result = await scanPrescription(
      Buffer.from('image'),
      'user-id',
      'legacy-prescription.jpg'
    );

    expect(result.drugs).toHaveLength(1);
    expect(result.drugs[0]).toMatchObject({
      name: 'Legacy OCR 50mg',
      mappedDrugName: 'Arbitrary Product 50mg',
      mappingStatus: 'unmapped_candidate',
      confirmationSafe: false,
    });
    expect(result.unresolvedCount).toBe(1);
    expect(queryMock).toHaveBeenCalledTimes(1);
  });
});
