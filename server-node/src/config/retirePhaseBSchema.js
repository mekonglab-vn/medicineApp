/**
 * Explicit retirement command for the obsolete Phase B PostgreSQL tables.
 * Dry-run is the default; applying requires database, deployment, and backup gates.
 */
import pg from 'pg';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const { Client } = pg;

export const PHASE_B_TABLES = Object.freeze([
  'pill_verification_assignments',
  'pill_verification_sessions',
  'pill_reference_images',
  'pill_reference_sets',
  'dose_verification_feedback_events',
  'dose_verification_detections',
  'dose_verification_sessions',
]);

const USAGE = `Usage:
  npm run schema:retire-phase-b
  npm run schema:retire-phase-b -- --apply --confirm-database <exact-name> --confirm-deployment '<exact-dry-run-identity>' --backup-confirmed

The default mode is a read-only dry-run that prints the server-reported deployment
identity. --apply requires exact database and deployment confirmations plus
--backup-confirmed.`;

export function parseArgs(argv) {
  const options = {
    apply: false,
    backupConfirmed: false,
    confirmedDatabase: null,
    confirmedDeployment: null,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--backup-confirmed') {
      options.backupConfirmed = true;
    } else if (arg === '--confirm-database') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-database requires the exact database name');
      }
      options.confirmedDatabase = value;
      index += 1;
    } else if (arg === '--confirm-deployment') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-deployment requires the exact dry-run identity');
      }
      options.confirmedDeployment = value;
      index += 1;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (options.apply && !options.confirmedDatabase) {
    throw new Error('--apply requires --confirm-database <exact-name>');
  }
  if (options.apply && !options.backupConfirmed) {
    throw new Error('--apply requires --backup-confirmed');
  }
  if (options.apply && !options.confirmedDeployment) {
    throw new Error('--apply requires --confirm-deployment <exact-dry-run-identity>');
  }

  return options;
}

async function listExistingTables(client) {
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

async function listExternalForeignKeys(client) {
  const result = await client.query(
    `SELECT source_ns.nspname AS source_schema,
            source.relname AS source_table,
            constraint_row.conname AS constraint_name,
            target.relname AS target_table
       FROM pg_catalog.pg_constraint AS constraint_row
       JOIN pg_catalog.pg_class AS source
         ON source.oid = constraint_row.conrelid
       JOIN pg_catalog.pg_namespace AS source_ns
         ON source_ns.oid = source.relnamespace
       JOIN pg_catalog.pg_class AS target
         ON target.oid = constraint_row.confrelid
       JOIN pg_catalog.pg_namespace AS target_ns
         ON target_ns.oid = target.relnamespace
      WHERE constraint_row.contype = 'f'
        AND target_ns.nspname = 'public'
        AND target.relname = ANY($1::text[])
        AND NOT (
          source_ns.nspname = 'public'
          AND source.relname = ANY($1::text[])
        )
      ORDER BY source_ns.nspname, source.relname, constraint_row.conname`,
    [PHASE_B_TABLES]
  );
  return result.rows;
}

function buildDeploymentIdentity(row) {
  const systemIdentifier = String(row.system_identifier ?? '').trim();
  if (!/^\d+$/.test(systemIdentifier) || systemIdentifier === '0') {
    throw new Error('PostgreSQL cluster system identifier is unavailable');
  }

  const usingUnixSocket = row.server_address === null;
  return JSON.stringify({
    systemIdentifier,
    database: row.database_name,
    user: row.user_name,
    transport: usingUnixSocket ? 'unix' : 'tcp',
    server: usingUnixSocket ? row.unix_socket_directories : row.server_address,
    port: Number(row.server_port ?? row.configured_port),
  });
}

export async function readDeploymentIdentity(client) {
  let identityResult;
  try {
    identityResult = await client.query(
      `SELECT (pg_control_system()).system_identifier::text AS system_identifier,
              current_database() AS database_name,
              current_user AS user_name,
              inet_server_addr()::text AS server_address,
              inet_server_port() AS server_port,
              current_setting('unix_socket_directories') AS unix_socket_directories,
              current_setting('port')::integer AS configured_port`
    );
  } catch (error) {
    throw new Error(
      `Cannot retrieve PostgreSQL cluster system identifier: ${error.message}`,
      { cause: error }
    );
  }

  const row = identityResult.rows[0];
  if (!row) {
    throw new Error('Cannot retrieve PostgreSQL cluster system identifier: server returned no identity');
  }

  try {
    return {
      databaseName: row.database_name,
      deploymentIdentity: buildDeploymentIdentity(row),
    };
  } catch (error) {
    throw new Error(
      `Cannot retrieve PostgreSQL cluster system identifier: ${error.message}`,
      { cause: error }
    );
  }
}

export async function retirePhaseBSchema({ connectionString, ...options }) {
  if (!connectionString) {
    throw new Error('DATABASE_URL is required');
  }
  if (options.apply && !options.confirmedDatabase) {
    throw new Error('--apply requires --confirm-database <exact-name>');
  }
  if (options.apply && options.backupConfirmed !== true) {
    throw new Error('--apply requires --backup-confirmed');
  }
  if (options.apply && !options.confirmedDeployment) {
    throw new Error('--apply requires --confirm-deployment <exact-dry-run-identity>');
  }

  const client = new Client({ connectionString });
  let transactionOpen = false;

  try {
    await client.connect();
    await client.query(options.apply ? 'BEGIN' : 'BEGIN READ ONLY');
    transactionOpen = true;

    const { databaseName, deploymentIdentity } = await readDeploymentIdentity(client);

    if (options.apply && options.confirmedDatabase !== databaseName) {
      throw new Error(
        `Database confirmation mismatch: connected to "${databaseName}", received "${options.confirmedDatabase}"`
      );
    }
    if (options.apply && options.confirmedDeployment !== deploymentIdentity) {
      throw new Error(
        `Deployment confirmation mismatch: server reports '${deploymentIdentity}'`
      );
    }

    await client.query(
      `SELECT pg_advisory_xact_lock(hashtext('medicineapp:retire-phase-b-schema'))`
    );

    const existingTables = await listExistingTables(client);
    const externalForeignKeys = await listExternalForeignKeys(client);
    if (externalForeignKeys.length > 0) {
      const details = externalForeignKeys
        .map(
          (foreignKey) =>
            `${foreignKey.source_schema}.${foreignKey.source_table}.${foreignKey.constraint_name} -> public.${foreignKey.target_table}`
        )
        .join(', ');
      throw new Error(`Refusing retirement because external foreign keys exist: ${details}`);
    }

    if (!options.apply) {
      await client.query('ROLLBACK');
      transactionOpen = false;
      return { applied: false, databaseName, deploymentIdentity, existingTables };
    }

    for (const table of PHASE_B_TABLES) {
      await client.query(`DROP TABLE IF EXISTS public.${table}`);
    }

    await client.query('COMMIT');
    transactionOpen = false;
    return { applied: true, databaseName, deploymentIdentity, droppedTables: existingTables };
  } catch (error) {
    if (transactionOpen) {
      await client.query('ROLLBACK');
    }
    throw error;
  } finally {
    await client.end().catch(() => {});
  }
}

export async function runCli(argv = process.argv.slice(2), environment = process.env) {
  const options = parseArgs(argv);
  if (options.help) {
    console.log(USAGE);
    return;
  }

  const result = await retirePhaseBSchema({
    connectionString: environment.DATABASE_URL,
    ...options,
  });
  if (result.applied) {
    console.log(`Applied Phase B schema retirement to database "${result.databaseName}".`);
    console.log(`Deployment identity: ${result.deploymentIdentity}`);
    console.log(`Dropped tables: ${result.droppedTables.join(', ') || '(none found)'}`);
  } else {
    console.log(`DRY RUN for database "${result.databaseName}"; no schema changes were committed.`);
    console.log(`Deployment identity: ${result.deploymentIdentity}`);
    console.log(`Tables that would be dropped: ${result.existingTables.join(', ') || '(none found)'}`);
  }
}

const isMain = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  runCli().catch((error) => {
    console.error(`Phase B schema retirement failed: ${error.message}`);
    process.exitCode = 1;
  });
}
