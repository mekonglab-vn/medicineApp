/**
 * Unit tests — auth.service.js
 *
 * Tests register, login, refresh, logoutAll.
 * Uses real DB (PostgreSQL Docker) with test users cleanup.
 */
import { cleanTestUsers, pool } from '../helpers/db.js';
import * as authService from '../../src/services/auth.service.js';

const PREFIX = 'test_ci_auth_';
const EMAIL = `${PREFIX}user@example.com`;
const PASSWORD = 'Test1234!';

beforeAll(async () => {
  await cleanTestUsers(PREFIX);
});

afterAll(async () => {
  await cleanTestUsers(PREFIX);
  await pool.end();
});

describe('register()', () => {
  test('should register a new user', async () => {
    const user = await authService.register({ email: EMAIL, password: PASSWORD, name: 'Auth Test' });
    expect(user.id).toBeDefined();
    expect(user.email).toBe(EMAIL);
    expect(user.name).toBe('Auth Test');
    // password_hash must NOT be returned
    expect(user.password_hash).toBeUndefined();
  });

  test('should throw 409 if email already taken', async () => {
    await expect(
      authService.register({ email: EMAIL, password: PASSWORD })
    ).rejects.toMatchObject({ statusCode: 409, code: 'DUPLICATE_EMAIL' });
  });
});

describe('login()', () => {
  test('should return tokens for valid credentials', async () => {
    const result = await authService.login({ email: EMAIL, password: PASSWORD });
    expect(result.accessToken).toBeDefined();
    expect(result.refreshToken).toBeDefined();
    expect(result.user.email).toBe(EMAIL);
    // Ensure password_hash not leaked
    expect(result.user.password_hash).toBeUndefined();
  });

  test('should throw 401 for wrong password', async () => {
    await expect(
      authService.login({ email: EMAIL, password: 'WrongPass1!' })
    ).rejects.toMatchObject({ statusCode: 401, code: 'INVALID_CREDENTIALS' });
  });

  test('should throw 401 for unknown email', async () => {
    await expect(
      authService.login({ email: 'nobody@example.com', password: PASSWORD })
    ).rejects.toMatchObject({ statusCode: 401, code: 'INVALID_CREDENTIALS' });
  });
});

describe('refresh()', () => {
  test('should return new token pair for valid refresh token', async () => {
    const { refreshToken } = await authService.login({ email: EMAIL, password: PASSWORD });
    const result = await authService.refresh(refreshToken);
    expect(result.accessToken).toBeDefined();
    expect(result.refreshToken).toBeDefined();
    // New refresh token must differ from old one (rotation)
    expect(result.refreshToken).not.toBe(refreshToken);
  });

  test('should throw 401 for already-used refresh token (rotation)', async () => {
    const { refreshToken } = await authService.login({ email: EMAIL, password: PASSWORD });
    await authService.refresh(refreshToken); // Use it once
    await expect(
      authService.refresh(refreshToken) // Use same token again
    ).rejects.toMatchObject({ statusCode: 401, code: 'INVALID_TOKEN' });
  });

  test('should throw 401 for invalid token', async () => {
    await expect(
      authService.refresh('invalid-token-string')
    ).rejects.toMatchObject({ statusCode: 401, code: 'INVALID_TOKEN' });
  });
});

describe('logoutAll()', () => {
  test('should revoke all refresh tokens for user', async () => {
    const { user, refreshToken } = await authService.login({ email: EMAIL, password: PASSWORD });
    await authService.logoutAll(user.id);
    // After logout-all, refresh token should be invalid
    await expect(
      authService.refresh(refreshToken)
    ).rejects.toMatchObject({ statusCode: 401 });
  });
});
