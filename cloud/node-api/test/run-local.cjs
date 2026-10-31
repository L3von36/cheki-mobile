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
