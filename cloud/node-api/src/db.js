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
 * pool.execute) — same SQL, same safety, no prepared-statement protocol
 * involvement. mysql2 escapes every bound value itself.
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

/** MySQL ODKU upsert statement (pure — asserted by the local test runner). */
function buildUpsertSql(table, columns, updateColumns) {
  // Backtick EVERYTHING: `blob` is a reserved word on MySQL — unquoted in
  // the insert column list it is a syntax error (sqlite/PHP never caught it).
  const cols = columns.map((c) => `\`${c}\``).join(', ');
  const marks = columns.map(() => '?').join(', ');
  const updates = updateColumns.map((c) => `\`${c}\` = VALUES(\`${c}\`)`).join(', ');
  return `INSERT INTO \`${table}\` (${cols}) VALUES (${marks}) ON DUPLICATE KEY UPDATE ${updates}`;
}

/** Driver-neutral upsert (vault + pro_status). */
function upsert(table, columns, updateColumns, params) {
  if (config.driver === 'mysql') {
    return run(buildUpsertSql(table, columns, updateColumns), params);
  }
  const cols = columns.map((c) => `\`${c}\``).join(', ');
  const marks = columns.map(() => '?').join(', ');
  const updates = updateColumns.map((c) => `\`${c}\` = excluded.\`${c}\``).join(', ');
  return run(`INSERT OR REPLACE INTO \`${table}\` (${cols}) VALUES (${marks})`, params);
}

/* ── schema (auto-created on first request, like the PHP port) ──────── */
//
// v1.17.0 — "professional database" pass. The owner reviews accounts in
// phpMyAdmin, so every table now carries:
//   * readable identity: `identifier` (phone/email as the user typed it,
//     normalized on-device), `identifier_type`, `display_name` — the
//     password stays zero-knowledge (auth_hash only, PBKDF2 client-side),
//   * audit columns: epoch-ms timestamps for the API + `_dt` DATETIME
//     mirrors so humans read dates without FROM_UNIXTIME gymnastics,
//   * lifecycle columns: `status` ('active' | 'disabled') and
//     `sign_in_count`,
//   * a `sign_ins` audit trail (90-day retention) and two admin views
//     (`v_user_overview`, `v_receipt_overview`) for one-glance reviews.
// Existing installs migrate in place: best-effort ALTERs backfill the
// new columns; readable identifiers backfill on the account's next
// sign-in (the hash cannot be reversed).

function ensureSchema() {
  const mysql = config.driver === 'mysql';
  const suffix = mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : '';
  const blobType = mysql ? 'MEDIUMTEXT' : 'TEXT';
  const uniq = mysql
    ? 'UNIQUE KEY `ux_accounts_user` (`user_id`)'
    : 'UNIQUE (`user_id`)';
  // Composite-unique + auto-increment id columns differ per dialect
  // (AUTO_INCREMENT vs AUTOINCREMENT, inline KEY syntax).
  const receiptUniq = mysql
    ? 'UNIQUE KEY `ux_receipts_entry` (`user_id`, `entry_id`)'
    : 'UNIQUE (`user_id`, `entry_id`)';
  const idCol = mysql
    ? '`id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,'
    : '`id` INTEGER PRIMARY KEY AUTOINCREMENT,';
  // FROM_UNIXTIME (MySQL) vs datetime(x/1000,'unixepoch') (SQLite).
  // [expr] is a pre-quoted SQL fragment: '`created_at`', 'p.`expires_at`'.
  const fromMs = (expr) =>
    mysql
      ? `FROM_UNIXTIME(FLOOR(${expr} / 1000))`
      : `datetime(${expr} / 1000, 'unixepoch')`;

  const tables = [
    `\`config\` (
        \`k\` VARCHAR(64) NOT NULL PRIMARY KEY,
        \`v\` TEXT NOT NULL
    )${suffix}`,
    `\`accounts\` (
        \`identifier_hash\` CHAR(64) NOT NULL PRIMARY KEY,
        \`user_id\`         CHAR(36) NOT NULL,
        \`auth_hash\`       CHAR(64) NOT NULL,
        \`identifier\`      VARCHAR(255) NULL,
        \`identifier_type\` VARCHAR(16) NULL,
        \`display_name\`    VARCHAR(64) NULL,
        \`status\`          VARCHAR(16) NOT NULL DEFAULT 'active',
        \`sign_in_count\`   BIGINT NOT NULL DEFAULT 0,
        \`created_at\`      BIGINT NOT NULL,
        \`created_dt\`      DATETIME NULL,
        \`last_seen_at\`    BIGINT NULL,
        \`last_seen_dt\`    DATETIME NULL,
        ${uniq}
    )${suffix}`,
    `\`refresh_tokens\` (
        \`token\`      CHAR(64) NOT NULL PRIMARY KEY,
        \`user_id\`    CHAR(64) NOT NULL,
        \`exp\`        BIGINT NOT NULL,
        \`created_at\` BIGINT NOT NULL
    )${suffix}`,
    `\`sign_ins\` (
        ${idCol}
        \`user_id\` CHAR(36) NOT NULL,
        \`at\`      BIGINT NOT NULL,
        \`at_dt\`   DATETIME NULL
    )${suffix}`,
    // Anti-trial-abuse ledger (v1.18.10): free checks are budgeted per
    // DEVICE (hash of the Android SSAID — survives reinstalls and
    // "clear storage", resets only on factory reset) so wiping app data
    // cannot mint fresh trials. Counters are monotonic on the server.
    `\`device_trials\` (
        \`device_hash\`   CHAR(64) NOT NULL PRIMARY KEY,
        \`checks_used\`   BIGINT NOT NULL DEFAULT 0,
        \`first_used_at\` BIGINT NOT NULL,
        \`first_used_dt\` DATETIME NULL,
        \`last_used_at\`  BIGINT NOT NULL,
        \`last_used_dt\`  DATETIME NULL
    )${suffix}`,
    `\`account_trials\` (
      \`user_id\`       CHAR(36) NOT NULL PRIMARY KEY,
      \`checks_used\`   BIGINT NOT NULL DEFAULT 0,
      \`first_used_at\` BIGINT NOT NULL,
      \`first_used_dt\` DATETIME NULL,
      \`last_used_at\`  BIGINT NOT NULL,
      \`last_used_dt\`  DATETIME NULL
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
    `\`verified_receipts\` (
        ${idCol}
        \`user_id\`       CHAR(36) NOT NULL,
        \`entry_id\`      VARCHAR(64) NOT NULL,
        \`bank_id\`       VARCHAR(32) NOT NULL,
        \`bank_name\`     VARCHAR(64) NOT NULL,
        \`reference\`     VARCHAR(255) NOT NULL,
        \`raw_payload\`   TEXT NULL,
        \`sender_name\`   VARCHAR(128) NULL,
        \`receiver_name\` VARCHAR(128) NULL,
        \`amount\`        DECIMAL(18, 2) NULL,
        \`currency\`      VARCHAR(8) NULL,
        \`receipt_date\`  VARCHAR(64) NULL,
        \`status\`        VARCHAR(16) NOT NULL,
        \`message\`       VARCHAR(512) NULL,
        \`reason\`        VARCHAR(255) NULL,
        \`verified_at\`   BIGINT NOT NULL,
        \`verified_dt\`   DATETIME NULL,
        \`created_at\`    BIGINT NOT NULL,
        \`created_dt\`    DATETIME NULL,
        ${receiptUniq}
    )${suffix}`,
  ];

  // Columns added after an install's first boot. Each ALTER is
  // individually best-effort: "duplicate column" on the happy path, and a
  // database user without ALTER rights must never break API requests.
  const alterStatements = [
    'ALTER TABLE `accounts` ADD COLUMN `last_seen_at` BIGINT NULL',
    'ALTER TABLE `accounts` ADD COLUMN `identifier` VARCHAR(255) NULL',
    'ALTER TABLE `accounts` ADD COLUMN `identifier_type` VARCHAR(16) NULL',
    'ALTER TABLE `accounts` ADD COLUMN `display_name` VARCHAR(64) NULL',
    "ALTER TABLE `accounts` ADD COLUMN `status` VARCHAR(16) NOT NULL DEFAULT 'active'",
    'ALTER TABLE `accounts` ADD COLUMN `sign_in_count` BIGINT NOT NULL DEFAULT 0',
    'ALTER TABLE `accounts` ADD COLUMN `created_dt` DATETIME NULL',
    'ALTER TABLE `accounts` ADD COLUMN `last_seen_dt` DATETIME NULL',
    'ALTER TABLE `verified_receipts` ADD COLUMN `verified_dt` DATETIME NULL',
    'ALTER TABLE `verified_receipts` ADD COLUMN `created_dt` DATETIME NULL',
  ];

  // Admin-facing readability indexes. MySQL lacks CREATE INDEX IF NOT
  // EXISTS (MariaDB has it — the try/catch covers both), SQLite supports
  // the IF NOT EXISTS form.
  const indexStatements = mysql
    ? [
        'CREATE INDEX `ix_accounts_identifier` ON `accounts` (`identifier`(191))',
        'CREATE INDEX `ix_sign_ins_user_time` ON `sign_ins` (`user_id`, `at`)',
        'CREATE INDEX `ix_receipts_user_time` ON `verified_receipts` (`user_id`, `verified_at`)',
      ]
    : [
        'CREATE INDEX IF NOT EXISTS `ix_accounts_identifier` ON `accounts` (`identifier`)',
        'CREATE INDEX IF NOT EXISTS `ix_sign_ins_user_time` ON `sign_ins` (`user_id`, `at`)',
        'CREATE INDEX IF NOT EXISTS `ix_receipts_user_time` ON `verified_receipts` (`user_id`, `verified_at`)',
      ];

  // One-glance phpMyAdmin screens: identity + plan + activity per user,
  // and the receipt ledger joined with who ran each check.
  const viewStatements = [
    `CREATE VIEW \`v_user_overview\` AS
     SELECT a.\`user_id\`,
            a.\`identifier\`,
            a.\`identifier_type\` AS \`type\`,
            a.\`display_name\`    AS \`name\`,
            a.\`status\`,
            a.\`sign_in_count\`   AS \`signins\`,
            a.\`created_dt\`      AS \`member_since\`,
            a.\`last_seen_dt\`    AS \`last_seen\`,
            ${fromMs('p.`expires_at`')} AS \`pro_until\`,
            (SELECT COUNT(*) FROM \`verified_receipts\` r
              WHERE r.\`user_id\` = a.\`user_id\`) AS \`checks\`
     FROM \`accounts\` a
     LEFT JOIN \`pro_status\` p ON p.\`user_id\` = a.\`user_id\``,
    `CREATE VIEW \`v_receipt_overview\` AS
     SELECT r.\`verified_dt\`  AS \`when\`,
            a.\`identifier\`,
            a.\`display_name\` AS \`name\`,
            r.\`bank_name\`    AS \`bank\`,
            r.\`reference\`,
            r.\`sender_name\`  AS \`sender\`,
            r.\`receiver_name\` AS \`receiver\`,
            r.\`amount\`,
            r.\`currency\`,
            r.\`status\`,
            r.\`reason\`
     FROM \`verified_receipts\` r
     LEFT JOIN \`accounts\` a ON a.\`user_id\` = r.\`user_id\``,
  ];

  return (async () => {
    for (const ddl of tables) {
      await run(`CREATE TABLE IF NOT EXISTS ${ddl}`);
    }
    for (const ddl of alterStatements) {
      try {
        await run(ddl);
      } catch (_) {
        // Duplicate column (or no ALTER permission) — column exists or
        // the code paths using it degrade gracefully.
      }
    }
    // Backfill the DATETIME mirrors for rows created before the columns
    // existed. Idempotent (only NULLs); skipped silently on failure.
    try {
      await run(
        'UPDATE `accounts` SET `created_dt` = ' + fromMs('`created_at`') + ' WHERE `created_dt` IS NULL',
      );
      await run(
        'UPDATE `accounts` SET `last_seen_dt` = ' + fromMs('`last_seen_at`') + ' WHERE `last_seen_dt` IS NULL AND `last_seen_at` IS NOT NULL',
      );
      await run(
        'UPDATE `verified_receipts` SET `verified_dt` = ' + fromMs('`verified_at`') + ' WHERE `verified_dt` IS NULL',
      );
      await run(
        'UPDATE `verified_receipts` SET `created_dt` = ' + fromMs('`created_at`') + ' WHERE `created_dt` IS NULL',
      );
    } catch (_) {
      // Mirrors are cosmetic; API timestamps (epoch ms) stay authoritative.
    }
    for (const ddl of indexStatements) {
      try {
        await run(ddl);
      } catch (_) {
        // Duplicate index name on MySQL — already created.
      }
    }
    for (const ddl of viewStatements) {
      // DROP+CREATE keeps the view definitions in sync with this release
      // on both dialects (MySQL has no CREATE VIEW IF NOT EXISTS).
      const viewName = ddl.match(/CREATE VIEW `([^`]+)`/)[1];
      await run(`DROP VIEW IF EXISTS \`${viewName}\``);
      await run(ddl);
    }
    await run(`${INSERT_IGNORE} \`config\` (\`k\`, \`v\`) VALUES ('schema', '2')`);
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
  buildUpsertSql,
  ensureReady,
  getJwtSecret,
  healthCheck,
};
