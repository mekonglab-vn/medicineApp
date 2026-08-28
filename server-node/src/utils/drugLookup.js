/**
 * Shared normalization helpers for drug lookup and interaction data.
 */

function removeDiacritics(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D');
}

export function normalizeDisplayText(value) {
  return String(value || '').trim().replace(/\s+/g, ' ');
}

export function normalizeLookupKey(value) {
  return removeDiacritics(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

export function buildInteractionPairKey(first, second) {
  const keys = [normalizeLookupKey(first), normalizeLookupKey(second)]
    .filter(Boolean)
    .sort();
  return keys.join(' || ');
}

export const INTERACTION_SEVERITY_ORDER = {
  contraindicated: 0,
  major: 1,
  moderate: 2,
  minor: 3,
  caution: 4,
  unknown: 5,
};

export function normalizeInteractionSeverity(rawValue) {
  const value = normalizeLookupKey(rawValue);
  if (!value) {
    return 'unknown';
  }

  if (
    value.includes('chong chi dinh')
    || value.includes('contraindicated')
    || value.includes('khong duoc khuyen cao')
  ) {
    return 'contraindicated';
  }

  if (
    value.includes('nghiem trong')
    || value.includes('major')
    || value.includes('nguy co cao')
  ) {
    return 'major';
  }

  if (
    value.includes('trung binh')
    || value.includes('moderate')
    || value.includes('nguy co trung binh')
  ) {
    return 'moderate';
  }

  if (value.includes('nhe') || value.includes('minor')) {
    return 'minor';
  }

  if (
    value.includes('than trong')
    || value.includes('khong nen phoi hop')
    || value.includes('khong nen dung')
    || value.includes('khong khuyen cao')
    || value.includes('can phai chu y')
    || value.includes('can than trong')
    || value.includes('nen tranh')
    || value.includes('can can nhac')
    || value.includes('can xem xet')
    || value.includes('caution')
  ) {
    return 'caution';
  }

  return 'unknown';
}

export function interactionSeverityRank(value) {
  return INTERACTION_SEVERITY_ORDER[value] ?? INTERACTION_SEVERITY_ORDER.unknown;
}
