import { jest } from '@jest/globals';
import request from 'supertest';

import app from '../../src/app.js';

const retiredEndpoints = [
  ['POST', '/api/pill-verifications/start'],
  ['POST', '/api/pill-references/enroll/start'],
];

describe('retired Phase B routes', () => {
  test.each(retiredEndpoints)('%s %s returns the normal 404 without proxying Python', async (method, path) => {
    const fetchMock = jest.fn();
    global.fetch = fetchMock;

    const response = await request(app)[method.toLowerCase()](path).send({});

    expect(response.status).toBe(404);
    expect(response.body).toEqual({
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: `Route ${method} ${path} not found`,
      },
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
