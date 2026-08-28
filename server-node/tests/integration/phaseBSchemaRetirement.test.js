import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

import { PHASE_B_TABLES } from '../../src/config/retirePhaseBSchema.js';

const { Client } = pg;
const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const serverDirectory = path.resolve(testDirectory, '../..');
const migrationScript = path.join(serverDirectory, 'src/config/migrate.js');
const retirementScript = path.join(serverDirectory, 'src/config/retirePhaseBSchema.js');
const connectionString = process.env.CLEAN07_DISPOSABLE_DATABASE_URL;
const describeWithDisposableDatabase = connectionString ? describe : describe.skip;

function getDatabaseName(url) {
  return decodeURIComponent(new URL(url).pathname.slice(1));
}

function runNode(script, args = []) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: serverDirectory,
    encoding: 'utf8',
    env: {
      ...process.env,
      DATABASE_URL: connectionString,
      JWT_SECRET: 'clean07-disposable-test-secret',
      NODE_ENV: 'test',
    },
  });
}

async function listPhaseBTables(client) {
  const result = await client.query(
    `SELECT tablename
       FROM pg_catalog.pg_tables
      WHERE schemaname = 'public'
        AND tablename = ANY($1::text[])
      ORDER BY tablename`,
    [PHASE_B_TABLES]
  );
  return result.rows.map((row) => row.tablename);
}

async function createRetiredTables(client) {
  await client.query(`
    CREATE TABLE pill_verification_sessions (id UUID PRIMARY KEY);
    CREATE TABLE pill_verification_assignments (
      id UUID PRIMARY KEY,
      session_id UUID REFERENCES pill_verification_sessions(id)
    );
    CREATE TABLE pill_reference_sets (id UUID PRIMARY KEY);
    CREATE TABLE pill_reference_images (
      id UUID PRIMARY KEY,
      reference_set_id UUID REFERENCES pill_reference_sets(id)
    );
    CREATE TABLE dose_verification_sessions (id UUID PRIMARY KEY);
    CREATE TABLE dose_verification_detections (
      id UUID PRIMARY KEY,
      session_id UUID REFERENCES dose_verification_sessions(id)
    );
    CREATE TABLE dose_verification_feedback_events (
      id UUID PRIMARY KEY,
      session_id UUID REFERENCES dose_verification_sessions(id)
    );
  `);
}

describeWithDisposableDatabase('Phase B schema retirement on a disposable PostgreSQL database', () => {
  let client;
  let databaseName;
  let deploymentIdentity;

  beforeAll(async () => {
    databaseName = getDatabaseName(connectionString);
    if (!databaseName.startsWith('medicineapp_clean07_disposable_')) {
      throw new Error(`Refusing non-disposable database: ${databaseName}`);
    }

    client = new Client({ connectionString });
    await client.connect();
    const existing = await client.query(
      `SELECT COUNT(*)::integer AS count
         FROM pg_catalog.pg_tables
        WHERE schemaname = 'public'`
    );
    if (existing.rows[0].count !== 0) {
      throw new Error(`Disposable database must start empty: ${databaseName}`);
    }
  });

  afterAll(async () => {
    await client?.end();
  });

  test('fresh bootstrap does not create any retired Phase B table', async () => {
    const migration = runNode(migrationScript);
    expect(migration.status).toBe(0);
    expect(await listPhaseBTables(client)).toEqual([]);
  });

  test('default dry-run reports targets without dropping them', async () => {
    await createRetiredTables(client);

    const dryRun = runNode(retirementScript);

    expect(dryRun.status).toBe(0);
    expect(dryRun.stdout).toContain('DRY RUN');
    const identityLine = dryRun.stdout
      .split('\n')
      .find((line) => line.startsWith('Deployment identity: '));
    deploymentIdentity = identityLine.slice('Deployment identity: '.length);
    const serverIdentity = await client.query(
      `SELECT (pg_control_system()).system_identifier::text AS system_identifier,
              current_database() AS database_name,
              current_user AS user_name,
              inet_server_addr()::text AS server_address,
              inet_server_port() AS server_port,
              current_setting('unix_socket_directories') AS unix_socket_directories,
              current_setting('port')::integer AS configured_port`
    );
    const identityRow = serverIdentity.rows[0];
    expect(JSON.parse(deploymentIdentity)).toEqual({
      systemIdentifier: identityRow.system_identifier,
      database: identityRow.database_name,
      user: identityRow.user_name,
      transport: identityRow.server_address === null ? 'unix' : 'tcp',
      server: identityRow.server_address ?? identityRow.unix_socket_directories,
      port: Number(identityRow.server_port ?? identityRow.configured_port),
    });
    expect(await listPhaseBTables(client)).toEqual([...PHASE_B_TABLES].sort());
  });

  test('apply requires backup, database, and deployment confirmations', () => {
    const missingDatabase = runNode(retirementScript, [
      '--apply',
      '--backup-confirmed',
      '--confirm-deployment',
      deploymentIdentity,
    ]);
    expect(missingDatabase.status).toBe(1);
    expect(missingDatabase.stderr).toContain('--apply requires --confirm-database <exact-name>');

    const missingBackup = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      databaseName,
      '--confirm-deployment',
      deploymentIdentity,
    ]);
    expect(missingBackup.status).toBe(1);
    expect(missingBackup.stderr).toContain('--apply requires --backup-confirmed');

    const missingDeployment = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      databaseName,
      '--backup-confirmed',
    ]);
    expect(missingDeployment.status).toBe(1);
    expect(missingDeployment.stderr).toContain(
      '--apply requires --confirm-deployment <exact-dry-run-identity>'
    );

    const wrongDatabase = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      `${databaseName}_wrong`,
      '--confirm-deployment',
      deploymentIdentity,
      '--backup-confirmed',
    ]);
    expect(wrongDatabase.status).toBe(1);
    expect(wrongDatabase.stderr).toContain('Database confirmation mismatch');
  });

  test('a different PostgreSQL system identifier refuses apply', async () => {
    const identity = JSON.parse(deploymentIdentity);
    const wrongDeployment = JSON.stringify({
      ...identity,
      systemIdentifier: (BigInt(identity.systemIdentifier) + 1n).toString(),
    });
    const apply = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      databaseName,
      '--confirm-deployment',
      wrongDeployment,
      '--backup-confirmed',
    ]);

    expect(apply.status).toBe(1);
    expect(apply.stderr).toContain('Deployment confirmation mismatch');
    expect(apply.stderr).toContain(deploymentIdentity);
    expect(await listPhaseBTables(client)).toEqual([...PHASE_B_TABLES].sort());
  });

  test('apply safely drops exactly the retired tables and keeps other tables', async () => {
    await client.query('CREATE TABLE clean07_retirement_sentinel (id INTEGER PRIMARY KEY)');

    const apply = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      databaseName,
      '--confirm-deployment',
      deploymentIdentity,
      '--backup-confirmed',
    ]);

    expect(apply.status).toBe(0);
    expect(apply.stdout).toContain('Applied Phase B schema retirement');
    expect(await listPhaseBTables(client)).toEqual([]);
    const sentinel = await client.query(`SELECT to_regclass('public.clean07_retirement_sentinel') AS name`);
    expect(sentinel.rows[0].name).toBe('clean07_retirement_sentinel');
  });

  test('an external foreign key refuses apply and rolls back every target drop', async () => {
    await createRetiredTables(client);
    await client.query(`
      CREATE TABLE clean07_external_reference (
        id UUID PRIMARY KEY,
        phase_b_session_id UUID REFERENCES pill_verification_sessions(id)
      )
    `);

    const apply = runNode(retirementScript, [
      '--apply',
      '--confirm-database',
      databaseName,
      '--confirm-deployment',
      deploymentIdentity,
      '--backup-confirmed',
    ]);

    expect(apply.status).toBe(1);
    expect(apply.stderr).toContain('Refusing retirement because external foreign keys exist');
    expect(apply.stderr).toContain('clean07_external_reference');
    expect(await listPhaseBTables(client)).toEqual([...PHASE_B_TABLES].sort());
    const externalTable = await client.query(
      `SELECT to_regclass('public.clean07_external_reference') AS name`
    );
    expect(externalTable.rows[0].name).toBe('clean07_external_reference');
  });
});
