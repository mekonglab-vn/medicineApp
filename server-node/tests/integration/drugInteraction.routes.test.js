/**
 * Integration tests — drug interaction routes (/api/drug-interactions/*)
 */
import request from 'supertest';

import app from '../../src/app.js';
import * as authService from '../../src/services/auth.service.js';
import {
  cleanLookupFixtures,
  cleanTestUsers,
  pool,
  seedLookupFixtures,
} from '../helpers/db.js';

const PREFIX = 'test_ci_route_drug_interaction_';
const LOOKUP_PREFIX = 'test_ci_lookup_route_';
const EMAIL = `${PREFIX}user@example.com`;

let accessToken;

beforeAll(async () => {
  await cleanTestUsers(PREFIX);
  await cleanLookupFixtures(LOOKUP_PREFIX);
  await seedLookupFixtures(LOOKUP_PREFIX);

  await authService.register({
    email: EMAIL,
    password: 'Test1234!',
    name: 'Drug Interaction Route Test',
  });
  const tokens = await authService.login({
    email: EMAIL,
    password: 'Test1234!',
  });
  accessToken = tokens.accessToken;
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await cleanLookupFixtures(LOOKUP_PREFIX);
  await pool.end();
});

describe('POST /api/drug-interactions/check-by-drugs', () => {
  test('200: returns normalized interactions from local dataset', async () => {
    const res = await request(app)
      .post('/api/drug-interactions/check-by-drugs')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        drugNames: [
          `${LOOKUP_PREFIX}warfarin-drug`,
          `${LOOKUP_PREFIX}aspirin-drug`,
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.hasInteractions).toBe(true);
    expect(res.body.data.interactions[0].severity).toBe('major');
    expect(res.body.data.totalInteractions).toBe(1);
  });

  test('400: validation rejects only one drug', async () => {
    const res = await request(app)
      .post('/api/drug-interactions/check-by-drugs')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ drugNames: [`${LOOKUP_PREFIX}warfarin-drug`] });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  test('401: no auth token', async () => {
    const res = await request(app)
      .post('/api/drug-interactions/check-by-drugs')
      .send({
        drugNames: [
          `${LOOKUP_PREFIX}warfarin-drug`,
          `${LOOKUP_PREFIX}aspirin-drug`,
        ],
      });

    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('AUTH_REQUIRED');
  });
});

describe('GET /api/drug-interactions/search-active-ingredients', () => {
  test('200: returns suggestions from local catalog', async () => {
    const res = await request(app)
      .get(`/api/drug-interactions/search-active-ingredients?keyword=${LOOKUP_PREFIX}war`)
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.suggestions[0].name).toBe(`${LOOKUP_PREFIX}warfarin`);
  });
});

describe('GET /api/drug-interactions/active-ingredients', () => {
  test('200: returns paginated ingredient catalog', async () => {
    const res = await request(app)
      .get(`/api/drug-interactions/active-ingredients?keyword=${LOOKUP_PREFIX}&page=1&limit=2`)
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.pagination.limit).toBe(2);
    expect(res.body.pagination.total).toBeGreaterThanOrEqual(4);
  });
});

describe('POST /api/drug-interactions/check-by-active-ingredients', () => {
  test('200: supports grouped response from local dataset', async () => {
    const res = await request(app)
      .post('/api/drug-interactions/check-by-active-ingredients')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        activeIngredients: [`${LOOKUP_PREFIX}warfarin`, `${LOOKUP_PREFIX}aspirin`],
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.highestSeverity).toBe('major');
    expect(res.body.data.groups.length).toBe(1);
    expect(res.body.data.requestedActiveIngredients.length).toBe(2);
  });

  test('400: rejects payload with < 2 unique active ingredients', async () => {
    const res = await request(app)
      .post('/api/drug-interactions/check-by-active-ingredients')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ activeIngredients: [`${LOOKUP_PREFIX}warfarin`] });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });
});

describe('GET /api/drug-interactions/by-active-ingredient', () => {
  test('200: returns interaction list for one ingredient', async () => {
    const res = await request(app)
      .get(
        `/api/drug-interactions/by-active-ingredient?ingredientName=${LOOKUP_PREFIX}levocetirizine`
      )
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.totalInteractions).toBe(1);
    expect(res.body.data.interactions[0].ingredientA).toBe(`${LOOKUP_PREFIX}levocetirizine`);
  });
});
