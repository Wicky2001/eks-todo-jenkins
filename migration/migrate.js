const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const { createPool } = require('./db');

const migrationsDir = path.join(__dirname, 'migrations');
const direction = process.argv[2] === 'down' ? 'down' : 'up';

// Any fixed number works. It makes two migration runs wait for each other
// instead of changing the database at the same time.
const MIGRATION_LOCK_ID = 727274;

async function run() {
  const pool = createPool();
  const client = await pool.connect();

  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_ID]);

    await client.query(`
      CREATE TABLE IF NOT EXISTS migrations (
        name TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);

    const migrations = fs
      .readdirSync(migrationsDir)
      .filter((fileName) => fileName.endsWith('.js'))
      .sort();

    const { rows } = await client.query('SELECT name FROM migrations ORDER BY name');
    const appliedNames = rows.map((row) => row.name);

    if (direction === 'up') {
      for (const fileName of migrations) {
        if (appliedNames.includes(fileName)) {
          continue;
        }

        const migration = require(path.join(migrationsDir, fileName));

        if (typeof migration.up !== 'function') {
          throw new Error(`Migration ${fileName} does not export an up function`);
        }

        await applyInTransaction(client, async () => {
          await migration.up(client);
          await client.query('INSERT INTO migrations (name) VALUES ($1)', [fileName]);
        });

        console.log(`Applied ${fileName}`);
      }
    } else {
      for (const fileName of [...appliedNames].reverse()) {
        const migration = require(path.join(migrationsDir, fileName));

        await applyInTransaction(client, async () => {
          if (typeof migration.down === 'function') {
            await migration.down(client);
          }

          await client.query('DELETE FROM migrations WHERE name = $1', [fileName]);
        });

        console.log(`Reverted ${fileName}`);
      }
    }
  } finally {
    client.release();
    await pool.end();
  }
}

async function applyInTransaction(client, work) {
  await client.query('BEGIN');

  try {
    await work();
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
