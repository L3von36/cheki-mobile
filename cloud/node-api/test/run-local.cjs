#!/usr/bin/env node
/**
 * Local one-shot test runner: starts the API on a throwaway SQLite database
 * and runs the full HTTP behaviour suite (test_api.mjs, the same suite used
 * for the PHP port and production) against it.
 *
 *   npm test        (from cloud/node-api/)
 */

const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8917;
const BASE = `http://127.0.0.1:${PORT}`;
const dbFile = path.join(os.tmpdir(), `mahtem-test-${Date.now()}.sqlite`);

const server = spawn(process.execPath, ['server.js'], {
  cwd: path.resolve(__dirname, '..'),
  env: {
    ...process.env,
    PORT: String(PORT),
    DB_DRIVER: 'sqlite',
    DB_SQLITE_PATH: dbFile,
    MIGRATE_FROM_URL: '', // no live network calls during tests
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

/* Static regression guard: every identifier in the MySQL upsert SQL must be
   backticked. `blob` is a reserved word on MySQL — it once shipped as a bare
   column name and only failed on real MySQL (sqlite/PHP never caught it). */
{
  const db = require('../src/db');
  const sql = db.buildUpsertSql(
    'vaults',
    ['user_id', 'blob', 'revision', 'updated_at'],
    ['blob', 'revision', 'updated_at']
  );
  const offenders = [...sql.matchAll(/[(,]\s*(?!`)([a-z_]+)/gi)].map((m) => m[1]);
  if (offenders.length) {
    console.error(`FAIL: unquoted identifiers in upsert SQL: ${offenders.join(', ')}\n  ${sql}`);
    process.exit(1);
  }
  console.log(`static check: upsert SQL fully backticked ok\n  ${sql}`);
}

let serverLog = '';
server.stdout.on('data', (d) => (serverLog += d));
server.stderr.on('data', (d) => (serverLog += d));

async function waitForHealth(retries = 60) {
  for (let i = 0; i < retries; i++) {
    try {
      const r = await fetch(`${BASE}/v1/health`, {
        headers: { 'X-Mahtem-Client': 'mahtem-android' },
      });
      if (r.ok) return true;
    } catch (_) { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

(async () => {
  const up = await waitForHealth();
  if (!up) {
    console.error('Server failed to start:\n' + serverLog);
    server.kill('SIGKILL');
    process.exit(1);
  }

  const tester = spawn(process.execPath, [path.join(__dirname, 'test_api.mjs'), BASE], {
    stdio: 'inherit',
  });
  tester.on('exit', (code) => {
    server.kill('SIGTERM');
    if (code === 0) {
      // Direct-DB check: the admin views must exist and be queryable after
      // the suite's traffic (schema migration ran on the first request).
      try {
        const { DatabaseSync } = require('node:sqlite');
        const raw = new DatabaseSync(dbFile);
        const users = raw.prepare('SELECT COUNT(*) AS n FROM `v_user_overview`').get();
        const receipts = raw.prepare('SELECT COUNT(*) AS n FROM `v_receipt_overview`').get();
        const signIns = raw.prepare('SELECT COUNT(*) AS n FROM `sign_ins`').get();
        const named = raw
          .prepare('SELECT identifier, name, signins FROM `v_user_overview` WHERE identifier IS NOT NULL LIMIT 1')
          .get();
        console.log(
          `views: v_user_overview=${users.n} rows, v_receipt_overview=${receipts.n} rows, sign_ins=${signIns.n} rows`,
        );
        if (named && named.identifier) {
          console.log(
            `readable account check: identifier=${named.identifier} name=${named.name ?? '—'} signins=${named.signins}`,
          );
        }
        raw.close();
      } catch (e) {
        console.error('FAIL: admin views query failed: ' + e.message);
        process.exit(1);
      }
    }
    try {
      fs.rmSync(dbFile, { force: true });
      fs.rmSync(dbFile + '-wal', { force: true });
      fs.rmSync(dbFile + '-shm', { force: true });
    } catch (_) { /* best effort */ }
    process.exit(code || 0);
  });
})();

server.on('exit', (code) => {
  if (code && code !== 0) {
    console.error(`Server exited early (code ${code}):\n` + serverLog);
    process.exit(1);
  }
});
