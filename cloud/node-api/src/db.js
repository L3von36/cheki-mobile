'use strict';

/**
 * Mahtem Cloud API — data layer.
 *
 * Production runs MySQL (mysql2 pool) on Plesk. A built-in `node:sqlite`
 * driver (lazy-required, Node >= 22.5) exists only for local development
 * tests — the same trick the PHP port uses. Both drivers share every SQL
 * statement through positional `?` placeholders; the only dialect
 * difference is INSERT IGNORE vs INSERT OR IGNORE.
 *
 * NOTE: the MySQL driver uses client-side escaping (pool.query, not
 * pool.execute). Server-side prepared statements hit protocol quirks on
 * some Plesk MariaDB builds (e.g. INSERT … ON DUPLICATE KEY UPDATE with
 * several string params failing while the same statement runs via the
 * text protocol); client-side escaping is immune and plenty safe —
 * mysql2 escapes every bound value itself.
 *
 * All timestamps are epoch MILLISECONDS (BIGINT), exactly like the
 * Cloudflare Worker's KV records.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const config = require('./config');

const INSERT_IGNORE = config.driver === 'mysql' ? 'INSERT IGNORE INTO' : 'INSERT OR IGNORE INTO';

let pool = null;
let readyPromise = null;
let jwtSecret = null;

/* ── connection ─────────────────────────────────────────────────────── */

function getPool() {
  if (pool) return pool;

  if (config.driver === 'mysql') {
    const mysql = require('mysql2/promise');
    pool = mysql.createPool({
      host: config.mysql.host,
      port: config.mysql.port,
      database: config.mysql.database,
      user: config.mysql.user,
      password: config.mysql.password,
      waitForConnections: true,
      connectionLimit: 5,
      queueLimit: 0,
      charset: 'utf8mb4',
      enableKeepAlive: true,
      namedPlaceholders: false,
    });
  } else {
    const { DatabaseSync } = require('node:sqlite');
    const file = config.sqlitePath;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const db = new DatabaseSync(file);
    db.exec('PRAGMA journal_mode=WAL;');
    db.exec('PRAGMA busy_timeout=5000;');
    pool = { __sqlite: db };
  }
  return pool;
}

/** SELECT → array of row objects. */
async function query(sql, params) {
  const p = getPool();
  if (config.driver === 'mysql') {
    const [rows] = await p.query(sql, params || []);
    return Array.isArray(rows) ? rows : [];
  }
  return p.__sqlite.prepare(sql).all(...(params || []));
}

/** INSERT/UPDATE/DELETE → { affectedRows }. */
async function run(sql, params) {
  const p = getPool();
  if (config.driver === 'mysql') {
    const [result] = await p.query(sql, params || []);
    return { affectedRows: (result && result.affectedRows) || 0 };
  }
  const info = p.__sqlite.prepare(sql).run(...(params || []));
  return { affectedRows: Number(info.changes) || 0 };
}

/** Driver-neutral upsert (vault + pro_status). */
function upsert(table, columns, updateColumns, params) {
  const cols = columns.join(', ');
  const marks = columns.map(() => '?').join(', ');
  if (config.driver === 'mysql') {
    const updates = updateColumns.map((c) => `\`${c}\` = VALUES(\`${c}\`)`).join(', ');
    return run(`INSERT INTO \`${table}\` (${cols}) VALUES (${marks}) ON DUPLICATE KEY UPDATE ${updates}`, params);
  }
  const updates = updateColumns.map((c) => `\`${c}\` = excluded.\`${c}\``).join(', ');
  return run(`INSERT OR REPLACE INTO \`${table}\` (${cols}) VALUES (${marks})`, params);
}

/* ── schema (auto-created on first request, like the PHP port) ──────── */

function ensureSchema() {
  const mysql = config.driver === 'mysql';
  const suffix = mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : '';
  const blobType = mysql ? 'MEDIUMTEXT' : 'TEXT';
  const uniq = mysql
    ? 'UNIQUE KEY `ux_accounts_user` (`user_id`)'
    : 'UNIQUE (`user_id`)';

  const tables = [
    `\`config\` (
        \`k\` VARCHAR(64) NOT NULL PRIMARY KEY,
        \`v\` TEXT NOT NULL
    )${suffix}`,
    `\`accounts\` (
        \`identifier_hash\` CHAR(64) NOT NULL PRIMARY KEY,
        \`user_id\`         CHAR(36) NOT NULL,
        \`auth_hash\`       CHAR(64) NOT NULL,
        \`created_at\`      BIGINT NOT NULL,
        ${uniq}
    )${suffix}`,
    `\`refresh_tokens\` (
        \`token\`      CHAR(64) NOT NULL PRIMARY KEY,
        \`user_id\`    CHAR(64) NOT NULL,
        \`exp\`        BIGINT NOT NULL,
        \`created_at\` BIGINT NOT NULL
    )${suffix}`,
    `\`vaults\` (
        \`user_id\`    CHAR(36) NOT NULL PRIMARY KEY,
        \`blob\`       ${blobType} NOT NULL,
        \`revision\`   BIGINT NOT NULL,
        \`updated_at\` BIGINT NOT NULL
    )${suffix}`,
    `\`pro_receipts\` (
        \`receipt_hash\` CHAR(64) NOT NULL PRIMARY KEY,
        \`user_id\`      CHAR(64) NOT NULL,
        \`amount_etb\`   INT NOT NULL,
        \`plan_days\`    INT NOT NULL,
        \`paid_at_ms\`   BIGINT NULL,
        \`claimed_at\`   BIGINT NOT NULL,
        \`expires_at\`   BIGINT NOT NULL
    )${suffix}`,
    `\`pro_status\` (
        \`user_id\`    CHAR(36) NOT NULL PRIMARY KEY,
        \`expires_at\` BIGINT NOT NULL,
        \`updated_at\` BIGINT NOT NULL
    )${suffix}`,
  ];

  return (async () => {
    for (const ddl of tables) {
      await run(`CREATE TABLE IF NOT EXISTS ${ddl}`);
    }
    await run(`${INSERT_IGNORE} \`config\` (\`k\`, \`v\`) VALUES ('schema', '1')`);
  })().catch((e) => {
    readyPromise = null; // allow a retry on the next request
    throw e;
  });
}

/** Connect + ensure schema exactly once per process. */
function ensureReady() {
  if (!readyPromise) {
    readyPromise = (async () => {
      getPool();
      await ensureSchema();
    })();
  }
  return readyPromise;
}

/* ── JWT secret (env override → config table → auto-provision) ──────── */

async function getJwtSecret() {
  if (config.jwtSecret && config.jwtSecret.length >= 32) return config.jwtSecret;

  if (jwtSecret) return jwtSecret;

  const rows = await query("SELECT v FROM `config` WHERE k = 'jwt_secret'");
  if (rows.length && typeof rows[0].v === 'string' && rows[0].v.length >= 32) {
    jwtSecret = rows[0].v;
    return jwtSecret;
  }
  const secret = crypto.randomBytes(32).toString('hex');
  await run(`${INSERT_IGNORE} \`config\` (\`k\`, \`v\`) VALUES ('jwt_secret', ?)`, [secret]);
  const after = await query("SELECT v FROM `config` WHERE k = 'jwt_secret'");
  jwtSecret = String(after[0].v);
  return jwtSecret;
}

/* ── misc ───────────────────────────────────────────────────────────── */

async function healthCheck() {
  try {
    await ensureReady();
    await query('SELECT 1');
    return true;
  } catch (_) {
    return false;
  }
}

module.exports = {
  INSERT_IGNORE,
  driver: config.driver,
  query,
  run,
  upsert,
  ensureReady,
  getJwtSecret,
  healthCheck,
};
