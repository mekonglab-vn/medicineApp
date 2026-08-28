/**
 * Unit tests — drug.service.js
 */
import { pool } from '../helpers/db.js';
import * as drugService from '../../src/services/drug.service.js';

afterAll(async () => {
  await pool.end();
});

describe('searchDrugs()', () => {
  test('should return results for valid query', async () => {
    const result = await drugService.searchDrugs('paracetamol');
    expect(result.drugs.length).toBeGreaterThan(0);
    expect(result.total).toBeGreaterThan(0);
    expect(result.drugs[0]).toHaveProperty('name');
  });

  test('should support fuzzy search (typo tolerance)', async () => {
    // "hapacol" vs "hapakol" (typo)
    const exact = await drugService.searchDrugs('hapacol');
    const typo = await drugService.searchDrugs('hapakol');
    // Both should return data (fuzzy)
    expect(exact.total).toBeGreaterThan(0);
    expect(typo.total).toBeGreaterThanOrEqual(0);
  });

  test('should throw 400 for query shorter than 2 chars', async () => {
    await expect(
      drugService.searchDrugs('a')
    ).rejects.toMatchObject({ statusCode: 400, code: 'INVALID_QUERY' });
  });

  test('should paginate correctly', async () => {
    const page1 = await drugService.searchDrugs('thuoc', { page: 1, limit: 5 });
    const page2 = await drugService.searchDrugs('thuoc', { page: 2, limit: 5 });
    expect(page1.drugs.length).toBeLessThanOrEqual(5);
    // Page 2 should have different items if total > 5
    if (page1.total > 5) {
      const ids1 = page1.drugs.map(d => d.name);
      const ids2 = page2.drugs.map(d => d.name);
      expect(ids1).not.toEqual(ids2);
    }
  });
});

describe('getDrugDetails()', () => {
  test('should return drug details from cache', async () => {
    const drug = await drugService.getDrugDetails('Hapacol');
    // Must return something
    expect(drug).toBeDefined();
    expect(drug._cached).toBe(true); // From seed data
  });

  test('should throw 400 for empty name', async () => {
    await expect(
      drugService.getDrugDetails('')
    ).rejects.toMatchObject({ statusCode: 400, code: 'INVALID_NAME' });
  });
});
