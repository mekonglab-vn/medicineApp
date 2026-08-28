/**
 * Unit tests — drugInteraction.service.js backed by local fixtures.
 */
import {
  cleanLookupFixtures,
  pool,
  seedLookupFixtures,
} from '../helpers/db.js';
import * as drugInteractionService from '../../src/services/drugInteraction.service.js';

const PREFIX = 'test_ci_lookup_unit_';

beforeAll(async () => {
  await cleanLookupFixtures(PREFIX);
  await seedLookupFixtures(PREFIX);
});

afterAll(async () => {
  await cleanLookupFixtures(PREFIX);
  await pool.end();
});

describe('drugInteraction.service', () => {
  test('searchActiveIngredients() returns normalized suggestions from local catalog', async () => {
    const result = await drugInteractionService.searchActiveIngredients(`${PREFIX}war`);

    expect(result.keyword).toBe(`${PREFIX}war`);
    expect(result.suggestions[0]).toEqual({ name: `${PREFIX}warfarin` });
  });

  test('listActiveIngredients() paginates local ingredient catalog', async () => {
    const result = await drugInteractionService.listActiveIngredients({
      keyword: PREFIX,
      page: 1,
      limit: 2,
    });

    expect(result.items.length).toBe(2);
    expect(result.total).toBeGreaterThanOrEqual(4);
    expect(result.page).toBe(1);
  });

  test('checkByDrugNames() maps local ingredients back to selected drugs', async () => {
    const result = await drugInteractionService.checkByDrugNames([
      `${PREFIX}warfarin-drug`,
      `${PREFIX}aspirin-drug`,
    ]);

    expect(result.hasInteractions).toBe(true);
    expect(result.totalInteractions).toBe(1);
    expect(result.highestSeverity).toBe('major');
    expect(result.interactions[0].drugA).toBe(`${PREFIX}warfarin-drug`);
    expect(result.interactions[0].drugB).toBe(`${PREFIX}aspirin-drug`);
    expect(result.interactions[0].warning).toContain('chảy máu');
  });

  test('checkByDrugNames() de-duplicates input names by normalized key', async () => {
    const result = await drugInteractionService.checkByDrugNames([
      `${PREFIX}warfarin-drug`,
      `${PREFIX}warfarin-drug`,
      `${PREFIX}aspirin-drug`,
    ]);

    expect(result.requestedDrugNames).toEqual([
      `${PREFIX}warfarin-drug`,
      `${PREFIX}aspirin-drug`,
    ]);
  });

  test('checkByDrugNames() rejects when unique drug count is below 2', async () => {
    await expect(
      drugInteractionService.checkByDrugNames([`${PREFIX}warfarin-drug`])
    ).rejects.toMatchObject({ statusCode: 400, code: 'VALIDATION_ERROR' });
  });

  test('checkByActiveIngredients() returns grouped local interactions', async () => {
    const result = await drugInteractionService.checkByActiveIngredients([
      `${PREFIX}warfarin`,
      `${PREFIX}aspirin`,
    ]);

    expect(result.totalInteractions).toBe(1);
    expect(result.highestSeverity).toBe('major');
    expect(result.groups[0].severity).toBe('major');
    expect(result.groups[0].interactions[0].ingredientA).toBe(`${PREFIX}warfarin`);
  });

  test('checkByActiveIngredients() rejects when unique ingredient count is below 2', async () => {
    await expect(
      drugInteractionService.checkByActiveIngredients([`${PREFIX}warfarin`])
    ).rejects.toMatchObject({ statusCode: 400, code: 'VALIDATION_ERROR' });
  });

  test('getInteractionsByActiveIngredient() returns all matching local interactions', async () => {
    const result = await drugInteractionService.getInteractionsByActiveIngredient(
      `${PREFIX}levocetirizine`
    );

    expect(result.totalInteractions).toBe(1);
    expect(result.interactions[0].ingredientA).toBe(`${PREFIX}levocetirizine`);
    expect(result.interactions[0].ingredientB).toBe(`${PREFIX}theophylline`);
  });
});
