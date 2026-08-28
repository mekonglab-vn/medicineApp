/**
 * Scan service — proxy prescription image to Python FastAPI pipeline.
 */
import crypto from 'node:crypto';
import { query } from '../config/database.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';
import logger from '../middleware/logger.js';

const MIN_GOOD_SCANS_FOR_CONVERGENCE = 2;
const MIN_MERGED_CONFIDENCE = 0.75;
const MAX_UNMAPPED_FOR_CONVERGENCE = 1;
const HIGH_CONFIDENCE_NEW_DRUG = 0.85;
const MAX_CONSECUTIVE_REJECTS = 3;

function toDrugItem(med) {
  const requestedMappingStatus = med.mapping_status
    || med.mappingStatus
    || 'unmapped_candidate';
  const mappedDrugName = med.mapped_drug_name
    || med.mappedDrugName
    || med.matched_drug_name
    || med.matchedDrugName
    || null;
  const matchBasis = med.match_basis || med.matchBasis || 'none';
  const strengthState = med.strength_state || med.strengthState || 'unknown_candidate';
  const ambiguous = Boolean(med.ambiguous);
  const registrationNumber = med.registration_number
    || med.registrationNumber
    || med.so_dang_ky
    || null;
  const normalizedCandidateStrength = med.normalized_candidate_strength
    || med.normalizedCandidateStrength
    || null;
  const declaredConfirmationSafe = med.confirmation_safe ?? med.confirmationSafe ?? false;
  const confirmationSafe = Boolean(
    declaredConfirmationSafe === true
    && matchBasis === 'brand_exact'
    && strengthState === 'compatible'
    && !ambiguous
    && mappedDrugName
    && normalizedCandidateStrength
  );
  const mappingStatus = requestedMappingStatus === 'confirmed' && !confirmationSafe
    ? 'unmapped_candidate'
    : requestedMappingStatus;

  // Plan §9.2: primary name is ALWAYS extracted/OCR text — DB match must not override display
  const rawText = med.drug_name_raw || med.drug_name || med.drugName || med.ocr_text || med.ocrText || '';
  const displayName = rawText; // never use mappedDrugName as the primary display name

  return {
    name: displayName,
    dosage: null,
    confidence: Number(med.confidence || 0),
    matchScore: Number(med.match_score || 0),
    ocrText: med.ocr_text || med.ocrText || rawText,
    mappedDrugName,   // kept as optional secondary metadata
    registrationNumber,
    normalizedCandidateStrength,
    mappingStatus,
    matchBasis,
    strengthState,
    ambiguous,
    resolutionReason: med.resolution_reason || med.resolutionReason || null,
    confirmationSafe,
    bbox: med.bbox || null,
  };
}

function normalizeScanResult(rawResult) {
  const medicationCandidates = Array.isArray(rawResult?.medication_candidates)
    ? rawResult.medication_candidates
    : Array.isArray(rawResult?.medications)
      ? rawResult.medications
      : [];
  const medications = Array.isArray(rawResult?.medications)
    ? rawResult.medications
    : [];
  const candidates = medicationCandidates
    .map(toDrugItem)
    .filter((d) => d.ocrText || d.name);
  const drugs = candidates.filter(
    (d) => d.mappingStatus !== 'rejected_noise' && d.name && d.name.trim().length > 0
  );

  const qualityState = rawResult?.quality_state || 'GOOD';
  const rejectReason = rawResult?.reject_reason || null;

  return {
    scanId: crypto.randomUUID(),
    qualityState,
    rejectReason,
    guidance: rawResult?.guidance || null,
    qualityMetrics: rawResult?.quality_metrics || {},
    roiMode: rawResult?.roi_mode || 'full_image',
    roiBBox: rawResult?.roi_bbox || null,
    roiOffset: rawResult?.roi_offset || [0, 0],
    rejected: Boolean(rawResult?.rejected),
    drugs,
    candidates,
    medications,
    unresolvedCount: drugs.filter((d) => d.mappingStatus === 'unmapped_candidate').length,
    rawText: null,
    stats: rawResult?.stats || {
      total_blocks: 0,
      drugnames: drugs.length,
      others: 0,
    },
    rawResult,
  };
}

function buildSignature(drugs) {
  return drugs
    .map((d) => `${drugIdentity(d)}:${d.mappingStatus}`)
    .sort()
    .join('|');
}

function drugIdentity(drug) {
  const confirmedIdentity = drug.mappingStatus === 'confirmed'
    && drug.confirmationSafe
    && drug.mappedDrugName;
  if (confirmedIdentity && drug.registrationNumber) {
    return `registration:${String(drug.registrationNumber).toLowerCase().trim()}`;
  }
  if (confirmedIdentity) {
    return (
      `product:${String(drug.mappedDrugName).toLowerCase().trim()}`
      + `|strength:${String(drug.normalizedCandidateStrength).toLowerCase().trim()}`
    );
  }
  const value = drug.ocrText || drug.name;
  return `raw:${String(value || '').toLowerCase().trim()}`;
}

function mergeDrugs(existingMap, incoming, sourceQuality = 'GOOD') {
  for (const d of incoming) {
    const key = drugIdentity(d);
    if (key.endsWith(':')) {
      continue;
    }

    const prev = existingMap.get(key);
    if (!prev) {
      existingMap.set(key, {
        name: d.name,
        ocrText: d.ocrText,
        mappedDrugName: d.mappedDrugName,
        registrationNumber: d.registrationNumber,
        normalizedCandidateStrength: d.normalizedCandidateStrength,
        mappingStatus: d.mappingStatus,
        matchBasis: d.matchBasis,
        strengthState: d.strengthState,
        ambiguous: d.ambiguous,
        resolutionReason: d.resolutionReason,
        confirmationSafe: d.confirmationSafe,
        confidence: d.confidence,
        matchScore: d.matchScore,
        frequency: 1,
        sources: [sourceQuality],
      });
      continue;
    }

    prev.frequency += 1;
    prev.confidence = Math.max(prev.confidence, d.confidence);
    prev.matchScore = Math.max(prev.matchScore, d.matchScore);
    if (d.mappingStatus === 'confirmed' && prev.mappingStatus !== 'confirmed') {
      prev.mappingStatus = 'confirmed';
      prev.name = d.name;
      prev.mappedDrugName = d.mappedDrugName;
      prev.registrationNumber = d.registrationNumber;
      prev.normalizedCandidateStrength = d.normalizedCandidateStrength;
      prev.matchBasis = d.matchBasis;
      prev.strengthState = d.strengthState;
      prev.ambiguous = d.ambiguous;
      prev.resolutionReason = d.resolutionReason;
      prev.confirmationSafe = d.confirmationSafe;
    }
    if (!prev.ocrText && d.ocrText) {
      prev.ocrText = d.ocrText;
    }
    if (!prev.sources.includes(sourceQuality)) {
      prev.sources.push(sourceQuality);
    }
  }
}

function getMergedDrugs(existingMap) {
  return Array.from(existingMap.values())
    .sort((a, b) => {
      if (a.mappingStatus !== b.mappingStatus) {
        return a.mappingStatus === 'confirmed' ? -1 : 1;
      }
      return (b.frequency - a.frequency) || (b.confidence - a.confidence);
    });
}

function hydrateSessionRow(row) {
  if (!row) {
    return null;
  }
  const mergedDrugs = Array.isArray(row.merged_result)
    ? row.merged_result
    : typeof row.merged_result === 'string'
      ? JSON.parse(row.merged_result)
      : [];
  return {
    sessionId: row.id,
    status: row.status,
    converged: Boolean(row.converged),
    convergenceReason: row.convergence_reason,
    mergedDrugs,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    closedAt: row.closed_at,
  };
}

async function getSessionRow(sessionId, userId) {
  const result = await query(
    `SELECT id, status, converged, convergence_reason, merged_result,
            created_at, updated_at, closed_at
     FROM scan_sessions
     WHERE id = $1 AND user_id = $2`,
    [sessionId, userId]
  );
  return result.rows[0] || null;
}

async function listSessionScans(sessionId) {
  const result = await query(
    `SELECT id, result, quality_state, reject_reason, scanned_at
     FROM scans
     WHERE session_id = $1
     ORDER BY scanned_at ASC`,
    [sessionId]
  );

  return result.rows.map((row) => {
    const rawResult = typeof row.result === 'string'
      ? JSON.parse(row.result)
      : row.result;
    const normalized = normalizeScanResult(rawResult || {});
    return {
      ...normalized,
      scanId: row.id,
      qualityState: row.quality_state || normalized.qualityState,
      rejectReason: row.reject_reason || normalized.rejectReason,
      scannedAt: row.scanned_at,
    };
  });
}

function evaluateConvergence(images, mergedDrugs) {
  const recentRejects = images.slice(-MAX_CONSECUTIVE_REJECTS);
  if (
    recentRejects.length === MAX_CONSECUTIVE_REJECTS
    && recentRejects.every((image) => image.rejected || image.qualityState === 'REJECT')
  ) {
    return {
      converged: false,
      convergenceReason: 'repeated_bad_images',
    };
  }

  const goodImages = images.filter(
    (image) => !image.rejected && image.qualityState !== 'REJECT'
  );
  if (goodImages.length < MIN_GOOD_SCANS_FOR_CONVERGENCE || mergedDrugs.length === 0) {
    return {
      converged: false,
      convergenceReason: null,
    };
  }

  const recentGoodImages = goodImages.slice(-MIN_GOOD_SCANS_FOR_CONVERGENCE);
  const signatures = recentGoodImages.map((image) => buildSignature(image.drugs));
  const signatureStable = signatures.every((sig) => sig && sig === signatures[0]);
  const unresolvedCount = mergedDrugs.filter((drug) => drug.mappingStatus === 'unmapped_candidate').length;
  const averageConfidence = mergedDrugs.reduce((sum, drug) => sum + Number(drug.confidence || 0), 0) / mergedDrugs.length;

  const latest = goodImages.at(-1);
  const historicalHighConfidence = new Set(
    goodImages
      .slice(0, -1)
      .flatMap((image) => image.drugs)
      .filter((drug) => Number(drug.confidence || 0) >= HIGH_CONFIDENCE_NEW_DRUG)
      .map(drugIdentity)
  );
  const hasNewHighConfidenceDrug = latest.drugs.some((drug) => {
    const key = drugIdentity(drug);
    return Number(drug.confidence || 0) >= HIGH_CONFIDENCE_NEW_DRUG && !historicalHighConfidence.has(key);
  });

  if (
    signatureStable
    && averageConfidence >= MIN_MERGED_CONFIDENCE
    && unresolvedCount <= MAX_UNMAPPED_FOR_CONVERGENCE
    && !hasNewHighConfidenceDrug
  ) {
    return {
      converged: true,
      convergenceReason: 'stable_high_confidence',
    };
  }

  return {
    converged: false,
    convergenceReason: null,
  };
}

async function buildSessionState(sessionId, userId) {
  const row = await getSessionRow(sessionId, userId);
  if (!row) {
    throw new AppError('Session not found', 404, 'SCAN_SESSION_NOT_FOUND');
  }

  const images = await listSessionScans(sessionId);
  const mergedMap = new Map();
  for (const image of images) {
    if (!image.rejected && image.qualityState !== 'REJECT') {
      mergeDrugs(mergedMap, image.drugs, image.qualityState);
    }
  }
  const mergedDrugs = getMergedDrugs(mergedMap);
  const convergence = evaluateConvergence(images, mergedDrugs);

  await query(
    `UPDATE scan_sessions
     SET merged_result = $1::jsonb,
         converged = $2,
         convergence_reason = $3,
         updated_at = NOW()
     WHERE id = $4 AND user_id = $5`,
    [
      JSON.stringify(mergedDrugs),
      convergence.converged,
      convergence.convergenceReason,
      sessionId,
      userId,
    ]
  );

  return {
    ...hydrateSessionRow({ ...row, merged_result: mergedDrugs, converged: convergence.converged, convergence_reason: convergence.convergenceReason }),
    totalImages: images.length,
    images,
  };
}

/**
 * Forward prescription image to Python FastAPI for OCR + NER.
 * @param {Buffer} imageBuffer - Image file buffer
 * @param {string} userId - Authenticated user ID
 * @param {string} originalName - Original filename
 * @returns {Promise<object>} Scan result
 */
export async function scanPrescription(
  imageBuffer,
  userId,
  originalName,
  detectedMime = 'image/jpeg',
  sessionId = null,
  ocrText = null,
  ocrLines = null
) {
  let result;
  let timeout;

  try {
    // Build multipart form for Python API
    const formData = new FormData();
    // Use the actual detected MIME type (not hardcoded)
    const blob = new Blob([imageBuffer], { type: detectedMime });
    formData.append('file', blob, originalName || 'prescription.jpg');
    if (ocrText) {
      formData.append('ocr_text', ocrText);
    }
    if (ocrLines) {
      const ocrLinesPayload = typeof ocrLines === 'string'
        ? ocrLines
        : JSON.stringify(ocrLines);
      formData.append('ocr_lines', ocrLinesPayload);
    }

    const ctrl = new AbortController();
    timeout = setTimeout(() => ctrl.abort(), 30_000); // 30s for OCR

    const resp = await fetch(`${env.PYTHON_API_URL}/api/scan-prescription`, {
      method: 'POST',
      body: formData,
      signal: ctrl.signal,
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      let upstreamError = {};
      try {
        upstreamError = JSON.parse(errBody);
      } catch {
        upstreamError = { detail: errBody };
      }
      const detail = upstreamError?.detail || upstreamError?.error || {};
      const code = typeof detail === 'object' && detail.code
        ? detail.code
        : 'PIPELINE_UNAVAILABLE';
      const message = typeof detail === 'object' && detail.message
        ? detail.message
        : `Python API returned ${resp.status}`;
      throw new AppError(message, resp.status, code);
    }

    result = await resp.json();
    if (result?.mock === true) {
      throw new AppError(
        'AI pipeline unavailable. Please try again later.',
        503,
        'PIPELINE_UNAVAILABLE'
      );
    }
    if (result?.error) {
      throw new AppError(
        String(result.error),
        422,
        'SCAN_PROCESSING_FAILED'
      );
    }
  } catch (err) {
    if (err.name === 'AbortError') {
      throw new AppError('Scan timed out (30s)', 504, 'SCAN_TIMEOUT');
    }
    if (err instanceof AppError) {
      throw err;
    }
    logger.error(`Python API error: ${err.message}`);
    throw new AppError(
      'AI pipeline unavailable. Please try again later.',
      503,
      'PIPELINE_UNAVAILABLE'
    );
  } finally {
    clearTimeout(timeout);
  }

  const normalized = normalizeScanResult(result);

  // Save to scan history
  const drugCount = normalized.drugs.length;
  const qualityScore = Number(normalized.qualityMetrics?.blur_score || 0);
  try {
    await query(
      `INSERT INTO scans
       (user_id, session_id, result, drug_count, quality_state, reject_reason, quality_score)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        userId,
        sessionId,
        JSON.stringify(normalized.rawResult || result),
        drugCount,
        normalized.qualityState,
        normalized.rejectReason,
        qualityScore,
      ]
    );
  } catch (err) {
    logger.warn(`Failed to save scan history: ${err.message}`);
  }

  return normalized;
}

export async function startScanSession(userId) {
  const sessionId = crypto.randomUUID();
  await query(
    `INSERT INTO scan_sessions (id, user_id, status, converged, merged_result)
     VALUES ($1, $2, 'active', false, '[]'::jsonb)`,
    [sessionId, userId]
  );

  return {
    sessionId,
    status: 'active',
  };
}

export async function addImageToSession(sessionId, userId, imageBuffer, originalName, detectedMime = 'image/jpeg') {
  const session = await getSessionRow(sessionId, userId);
  if (!session) {
    throw new AppError('Session not found', 404, 'SCAN_SESSION_NOT_FOUND');
  }
  if (session.status !== 'active') {
    throw new AppError('Session already closed', 400, 'SCAN_SESSION_CLOSED');
  }

  const scanResult = await scanPrescription(
    imageBuffer,
    userId,
    originalName,
    detectedMime,
    sessionId
  );

  const entry = {
    scanId: scanResult.scanId,
    qualityState: scanResult.qualityState,
    rejectReason: scanResult.rejectReason,
    guidance: scanResult.guidance,
    drugs: scanResult.drugs,
    candidates: scanResult.candidates,
    createdAt: new Date().toISOString(),
  };
  const sessionState = await buildSessionState(sessionId, userId);

  return {
    sessionId,
    status: sessionState.status,
    converged: sessionState.converged,
    convergenceReason: sessionState.convergenceReason,
    guidance: scanResult.guidance,
    qualityState: scanResult.qualityState,
    rejectReason: scanResult.rejectReason,
    mergedDrugs: sessionState.mergedDrugs,
    totalImages: sessionState.totalImages,
    latest: entry,
  };
}

export async function getScanSession(sessionId, userId) {
  const sessionState = await buildSessionState(sessionId, userId);

  return {
    sessionId: sessionState.sessionId,
    status: sessionState.status,
    converged: sessionState.converged,
    convergenceReason: sessionState.convergenceReason,
    totalImages: sessionState.totalImages,
    mergedDrugs: sessionState.mergedDrugs,
    images: sessionState.images,
  };
}

export async function stopScanSession(sessionId, userId) {
  const sessionState = await buildSessionState(sessionId, userId);
  await query(
    `UPDATE scan_sessions
     SET status = 'stopped',
         closed_at = NOW(),
         updated_at = NOW()
     WHERE id = $1 AND user_id = $2`,
    [sessionId, userId]
  );

  return {
    sessionId,
    status: 'stopped',
    converged: sessionState.converged,
    convergenceReason: sessionState.convergenceReason,
    totalImages: sessionState.totalImages,
    mergedDrugs: sessionState.mergedDrugs,
  };
}

/**
 * Get scan history for a user.
 * @param {string} userId
 * @param {{ page?: number, limit?: number }} opts
 */
export async function getScanHistory(userId, { page = 1, limit = 20 } = {}) {
  const offset = (page - 1) * limit;

  const result = await query(
    `SELECT id, drug_count, scanned_at, result, quality_state, reject_reason
     FROM scans
     WHERE user_id = $1
     ORDER BY scanned_at DESC
     LIMIT $2 OFFSET $3`,
    [userId, limit, offset]
  );

  const countResult = await query(
    'SELECT COUNT(*) FROM scans WHERE user_id = $1',
    [userId]
  );

  return {
    scans: result.rows,
    total: parseInt(countResult.rows[0].count),
  };
}

export async function getScanHistoryItem(userId, scanId) {
  const result = await query(
    `SELECT id, drug_count, scanned_at, result, quality_state, reject_reason, quality_score
     FROM scans
     WHERE user_id = $1 AND id = $2
     LIMIT 1`,
    [userId, scanId]
  );

  const row = result.rows[0];
  if (!row) {
    throw new AppError('Scan history item not found', 404, 'SCAN_NOT_FOUND');
  }

  const rawResult = typeof row.result === 'string'
    ? JSON.parse(row.result)
    : row.result;
  const normalized = normalizeScanResult(rawResult || {});

  return {
    id: row.id,
    drugCount: row.drug_count,
    scannedAt: row.scanned_at,
    qualityState: row.quality_state || normalized.qualityState,
    rejectReason: row.reject_reason || normalized.rejectReason,
    qualityScore: Number(row.quality_score || 0),
    guidance: normalized.guidance,
    qualityMetrics: normalized.qualityMetrics,
    roiMode: normalized.roiMode,
    rejected: normalized.rejected,
    unresolvedCount: normalized.unresolvedCount,
    drugs: normalized.drugs,
    candidates: normalized.candidates,
  };
}
