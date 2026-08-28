import { jest } from '@jest/globals';

import { readDeploymentIdentity } from '../../src/config/retirePhaseBSchema.js';

describe('Phase B schema deployment identity', () => {
  test('builds the identity from the PostgreSQL server result', async () => {
    const client = {
      query: jest.fn().mockResolvedValue({
        rows: [{
          system_identifier: '7523456789012345678',
          database_name: 'medicineapp',
          user_name: 'medicineapp_role',
          server_address: '10.0.0.12',
          server_port: 5432,
          unix_socket_directories: '/var/run/postgresql',
          configured_port: 5432,
        }],
      }),
    };

    const result = await readDeploymentIdentity(client);

    expect(client.query.mock.calls[0][0]).toContain('pg_control_system()');
    expect(JSON.parse(result.deploymentIdentity)).toEqual({
      systemIdentifier: '7523456789012345678',
      database: 'medicineapp',
      user: 'medicineapp_role',
      transport: 'tcp',
      server: '10.0.0.12',
      port: 5432,
    });
  });

  test('uses server socket directories and configured port for Unix sockets', async () => {
    const client = {
      query: jest.fn().mockResolvedValue({
        rows: [{
          system_identifier: '7523456789012345678',
          database_name: 'medicineapp',
          user_name: 'medicineapp_role',
          server_address: null,
          server_port: null,
          unix_socket_directories: '/var/run/postgresql',
          configured_port: 5440,
        }],
      }),
    };

    const result = await readDeploymentIdentity(client);

    expect(JSON.parse(result.deploymentIdentity)).toMatchObject({
      transport: 'unix',
      server: '/var/run/postgresql',
      port: 5440,
    });
  });

  test('fails closed when the role cannot execute pg_control_system', async () => {
    const client = {
      query: jest.fn().mockRejectedValue(new Error('permission denied for function pg_control_system')),
    };

    await expect(readDeploymentIdentity(client)).rejects.toThrow(
      'Cannot retrieve PostgreSQL cluster system identifier: permission denied'
    );
  });

  test('fails closed when the server does not return a system identifier', async () => {
    const client = {
      query: jest.fn().mockResolvedValue({
        rows: [{
          system_identifier: null,
          database_name: 'medicineapp',
          user_name: 'medicineapp_role',
          server_address: '10.0.0.12',
          server_port: 5432,
          unix_socket_directories: '/var/run/postgresql',
          configured_port: 5432,
        }],
      }),
    };

    await expect(readDeploymentIdentity(client)).rejects.toThrow(
      'Cannot retrieve PostgreSQL cluster system identifier: PostgreSQL cluster system identifier is unavailable'
    );
  });
});
