'use strict';

/**
 * Mahtem Cloud API — configuration loader.
 *
 * Reads a `.env` file (KEY=VALUE lines) from the application root first and
 * merges it UNDER the real process environment (so Plesk-side environment
 * variables always win). Nothing else needs editing: fill `.env` with the
 * three database values from Plesk → Databases and you are done.
 */

const fs = require('node:fs');
const path = require('node:path');

const APP_ROOT = path.resolve(__dirname, '..');

function loadEnvFile(file) {
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch (_) {
    return; // no .env file — fine
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!m) continue;
    let value = m[2];
    if (
      (value.startsWith('"') && value.endsWith('"') && value.length >= 2) ||
      (value.startsWith("'") && value.endsWith("'") && value.length >= 2)
    ) {
      value = value.slice(1, -1);
    }
    if (!(m[1] in process.env)) process.env[m[1]] = value;
  }
}

loadEnvFile(path.join(APP_ROOT, '.env'));

const driver = (process.env.DB_DRIVER || 'mysql').trim().toLowerCase();

const config = {
  appRoot: APP_ROOT,
  version: '1.15.0-node',

  /** 'mysql' in production. 'sqlite' exists only for local development tests. */
  driver: driver === 'sqlite' ? 'sqlite' : 'mysql',

  mysql: {
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT || 3306) || 3306,
    database: process.env.DB_NAME || '',
    user: process.env.DB_USER || '',
    password: process.env.DB_PASSWORD || '',
  },

  /** Local development / testing only (never used when driver = mysql). */
  sqlitePath:
    process.env.DB_SQLITE_PATH || path.join(APP_ROOT, 'data', 'mahtem.sqlite'),

  /**
   * JWT signing secret. Leave empty to auto-provision a random secret into
   * the `config` table on first use (survives restarts).
   */
  jwtSecret: process.env.MAHTEM_JWT_SECRET || '',

  /**
   * Old Cloudflare Worker — automatic one-time import of existing users on
   * their first sign-in. Set to '' once every user has signed in again.
   */
  migrateFromUrl:
    process.env.MIGRATE_FROM_URL !== undefined
      ? process.env.MIGRATE_FROM_URL.trim()
      : 'https://mahtem-api.mahtem.workers.dev',

  publicDir: path.join(APP_ROOT, 'public'),
};

module.exports = config;
