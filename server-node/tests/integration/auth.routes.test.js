/**
 * Integration tests — Auth routes (POST /api/auth/*)
 *
 * Uses supertest to make real HTTP requests against the Express app.
 */
import request from 'supertest';
import app from '../../src/app.js';
import { cleanTestUsers, pool } from '../helpers/db.js';

const PREFIX = 'test_ci_route_auth_';
const EMAIL = `${PREFIX}user@example.com`;
const PASSWORD = 'Test1234!';

beforeAll(async () => {
  await cleanTestUsers(PREFIX);
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('POST /api/auth/register', () => {
  test('201: register new user', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: EMAIL, password: PASSWORD, name: 'Integration Test' });
    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.user.email).toBe(EMAIL);
    // Must not expose password hash
    expect(res.body.data.user.password_hash).toBeUndefined();
  });

  test('409: duplicate email', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: EMAIL, password: PASSWORD });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DUPLICATE_EMAIL');
  });

  test('400: weak password (too short)', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'newuser@test.com', password: 'short' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  test('400: invalid email', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'not-an-email', password: PASSWORD });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/auth/login', () => {
  test('200: valid login returns tokens', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: EMAIL, password: PASSWORD });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeDefined();
    expect(res.body.data.refreshToken).toBeDefined();
  });

  test('401: wrong password', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: EMAIL, password: 'WrongPass1!' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });
});

describe('POST /api/auth/refresh', () => {
  test('200: valid refresh returns new tokens', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: EMAIL, password: PASSWORD });
    const { refreshToken } = loginRes.body.data;

    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeDefined();
    expect(res.body.data.refreshToken).not.toBe(refreshToken); // rotated
  });

  test('401: invalid token', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: 'fake-token' });
    expect(res.status).toBe(401);
  });
});

describe('POST /api/auth/logout-all', () => {
  test('200: revoke all sessions', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: EMAIL, password: PASSWORD });
    const { accessToken, refreshToken } = loginRes.body.data;

    const res = await request(app)
      .post('/api/auth/logout-all')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(res.status).toBe(200);

    // Verify refresh token no longer works
    const refreshRes = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken });
    expect(refreshRes.status).toBe(401);
  });

  test('401: no token', async () => {
    const res = await request(app).post('/api/auth/logout-all');
    expect(res.status).toBe(401);
  });
});
