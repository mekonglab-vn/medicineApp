/**
 * Integration tests — Drug routes + Health endpoint
 */
import request from 'supertest';
import app from '../../src/app.js';
import { cleanTestUsers, pool } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';

const PREFIX = 'test_ci_route_drug_';
const EMAIL = `${PREFIX}user@example.com`;
let accessToken;

beforeAll(async () => {
  await cleanTestUsers(PREFIX);
  await authService.register({ email: EMAIL, password: 'Test1234!', name: 'Drug Route Test' });
  const tokens = await authService.login({ email: EMAIL, password: 'Test1234!' });
  accessToken = tokens.accessToken;
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('GET /api/health', () => {
  test('200: returns server + DB status', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.data.server).toBe('ok');
    expect(res.body.data.database.ok).toBe(true);
  });
});

describe('GET /api/drugs/search', () => {
  test('200: fuzzy search returns results', async () => {
    const res = await request(app)
      .get('/api/drugs/search?q=paracetamol')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);
    expect(res.body.pagination.total).toBeGreaterThan(0);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  test('400: limit > 50 is rejected by validation', async () => {
    const res = await request(app)
      .get('/api/drugs/search?q=thuoc&limit=100') // over limit
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(400); // Zod rejects limit > 50
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  test('400: query too short', async () => {
    const res = await request(app)
      .get('/api/drugs/search?q=a')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  test('401: no auth', async () => {
    const res = await request(app).get('/api/drugs/search?q=paracetamol');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/drugs/:name', () => {
  test('200: get drug from cache', async () => {
    const res = await request(app)
      .get('/api/drugs/Hapacol')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data._cached).toBe(true);
  });

  test('401: no auth', async () => {
    const res = await request(app).get('/api/drugs/Hapacol');
    expect(res.status).toBe(401);
  });
});

describe('404 handler', () => {
  test('404: unknown route returns structured error', async () => {
    const res = await request(app).get('/api/nonexistent-route');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});
