'use strict';

/**
 * Mahtem Cloud API (v1.15.0-node) — Zero-Knowledge OAuth 2.1 / JWT backend.
 *
 * Node.js/Express + MySQL port of `cloud/worker.js` (Cloudflare Worker) for
 * Plesk shared hosting (Phusion Passenger). Route map, request/response
 * shapes, error codes and status codes are identical to the Worker, so the
 * Flutter client (lib/core/cloud/cloud_api.dart) works without changes.
 *
 * PRIVACY CONTRACT (zero-knowledge credentials; readable account + receipt
 * ledger for the owner):
 *   * Client derives `authKey = PBKDF2(password, "mahtem-cloud-auth-v1")`.
 *     The raw password never reaches this server. `auth_hash` is the only
 *     credential material stored.
 *   * v1.17.0: the account row also carries the readable identifier
 *     (phone/email as normalized on-device), optional display name, sign-in
 *     count/times and a sign_ins audit trail — the owner reviews accounts
 *     in phpMyAdmin (see v_user_overview / v_receipt_overview views).
 *   * Vault (history backup) is AES-256-GCM encrypted on-device. This server
 *     cannot decrypt it.
 *   * Each verification is recorded in `verified_receipts` (bank, reference,
 *     scanned payload, parties, amount, outcome) under the user's account.
 *
 * TOKEN ARCHITECTURE (identical to the Worker):
 *   * Short-lived access token: JWT HS256, 15 minutes, stateless verification.
 *   * Rotating single-use refresh token: 30 days, reuse-detecting.
 *   * JWT secret auto-provisioned into the `config` table on first use.
 *
 * Every request must carry the `X-Mahtem-Client` header (cheap bot screen).
 */

const express = require('express');
const crypto = require('node:crypto');
const config = require('./config');
const db = require('./db');
const { signAccessToken, verifyAccessToken } = require('./jwt');
const { migrateImportFromWorker } = require('./migrate');

const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const PLAN_DAYS = 31;
const PLAN_AMOUNT_ETB = 300;
const PLAN_MS = 31 * 24 * 60 * 60 * 1000;
const MAX_BLOB_CHARS = 4_000_000; // base64 vault ciphertext cap

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Mahtem-Client',
  'X-Content-Type-Options': 'nosniff',
};

/* ── helpers ────────────────────────────────────────────────────────── */

const isHex64 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
const isBase64ish = (s) => typeof s === 'string' && s.length > 16 && s.length <= MAX_BLOB_CHARS;

function hashAuthKey(authKey, userId) {
  return crypto.createHash('sha256').update(`${userId}:${authKey}`).digest('hex');
}

const err = (code, status, message) => ({ code, status, message });

/** Async wrapper: express 4 does not catch rejected promises by itself. */
const h = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function fail(res, e) {
  return res.status(e.status).json({ error: e.code, message: e.message });
}

async function issueSessionTokens(userId) {
  const secret = await db.getJwtSecret();
  const jwt = signAccessToken(userId, secret);
  const refreshToken = crypto.randomBytes(32).toString('hex');
  const exp = Math.floor(Date.now() / 1000) + REFRESH_TOKEN_TTL_SECONDS;
  await db.run(
    'INSERT INTO `refresh_tokens` (`token`, `user_id`, `exp`, `created_at`) VALUES (?, ?, ?, ?)',
    [refreshToken, userId, exp, Date.now()],
  );
  // Opportunistic cleanup of expired refresh tokens (~5% of logins).
  if (Math.random() < 0.05) {
    await db.run('DELETE FROM `refresh_tokens` WHERE `exp` < ?', [
      Math.floor(Date.now() / 1000),
    ]);
  }
  return {
    accessToken: jwt.jwt,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: jwt.expiresIn,
    expiresAt: jwt.expiresAt,
    sessionToken: jwt.jwt, // backwards-compatible field for existing clients
    userId,
  };
}

/** Bearer-token session check (JWT only — legacy sess: KV tokens are gone). */
async function requireSession(req) {
  const auth = req.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) {
    return { ok: false, status: 401, error: 'missing_token', message: 'Session token required.' };
  }

  if (token.split('.').length === 3) {
    const secret = await db.getJwtSecret();
    const v = verifyAccessToken(token, secret);
    if (v.ok && v.payload && typeof v.payload.sub === 'string' && v.payload.sub) {
      return {
        ok: true,
        token,
        userId: v.payload.sub,
        exp: typeof v.payload.exp === 'number' ? v.payload.exp : null,
      };
    }
    if (v.error === 'expired') {
      return { ok: false, status: 401, error: 'token_expired', message: 'Access token has expired. Use /v1/session/refresh to renew.' };
    }
    return { ok: false, status: 401, error: 'invalid_token', message: 'Access token is invalid or signature check failed.' };
  }

  return { ok: false, status: 401, error: 'unauthorized', message: 'Session missing or expired.' };
}

function guard(res, session) {
  if (!session.ok) {
    fail(res, { code: session.error, status: session.status, message: session.message });
    return false;
  }
  return true;
}

/* ── app ────────────────────────────────────────────────────────────── */

const app = express();
app.disable('x-powered-by');

// CORS on everything, preflight short-circuits before the bot screen.
app.use((req, res, next) => {
  for (const [k, v] of Object.entries(CORS_HEADERS)) res.setHeader(k, v);
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  next();
});

// The landing page and privacy policy are served by this same process.
app.use(express.static(config.publicDir, { index: 'index.html', extensions: ['html'] }));

// Cheap bot screen — the app always sends this header.
app.use((req, res, next) => {
  if (!req.get('X-Mahtem-Client')) {
    fail(res, err('client_required', 400, 'Missing X-Mahtem-Client header.'));
    return;
  }
  next();
});

// Accept large encrypted vault uploads (base64 ciphertext up to 4 M chars).
app.use(express.json({ limit: '16mb' }));

// Mount-anywhere: whether Passenger exposes us at "/" or "/api", route on
// the "/v1/…" part only (mirrors the PHP front controller's request_path()).
app.use((req, res, next) => {
  const i = req.url.indexOf('/v1/');
  if (i > 0) req.url = req.url.slice(i);
  next();
});

const api = express.Router();

/* ── liveness probe ─────────────────────────────────────────────────── */

api.get('/v1/health', h(async (req, res) => {
  const dbOk = await db.healthCheck();
  res.json({
    ok: true,
    service: 'mahtem-api',
    auth: 'OAuth 2.0 / JWT (HS256) + Zero-Knowledge',
    version: config.version,
    db: dbOk,
    time: new Date().toISOString(),
  });
}));

/* ── account creation ───────────────────────────────────────────────── */

/** Server-side DATETIME mirror of an epoch-ms instant (audit columns). */
function dtOf(ms) {
  return new Date(ms).toISOString().slice(0, 19).replace('T', ' ');
}

/** Reads the optional readable-identity fields the client sends along. */
function readIdentity(body) {
  const str = (v, max) =>
    typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null;
  const identifier = str(body.identifier, 255);
  const displayName = str(body.displayName, 64);
  return {
    identifier,
    identifierType: identifier
      ? identifier.includes('@')
        ? 'email'
        : 'phone'
      : null,
    displayName,
  };
}

api.post('/v1/accounts', h(async (req, res) => {
  const body = req.body || {};
  const identifierHash = body.identifierHash;
  const authKey = body.authKey;
  if (!isHex64(identifierHash) || !isHex64(authKey)) {
    return fail(res, err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.'));
  }
  await db.ensureReady();

  const existing = await db.query('SELECT `user_id` FROM `accounts` WHERE `identifier_hash` = ?', [identifierHash]);
  if (existing.length) {
    return fail(res, err('exists', 409, 'An account with this identifier already exists.'));
  }

  const id = crypto.randomUUID();
  const authHash = hashAuthKey(authKey, id);
  const now = Date.now();
  const identity = readIdentity(body);
  try {
    await db.run(
      'INSERT INTO `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `identifier`, `identifier_type`, `display_name`, `status`, `sign_in_count`, `created_at`, `created_dt`) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
      [identifierHash, id, authHash, identity.identifier, identity.identifierType, identity.displayName, 'active', now, dtOf(now)],
    );
  } catch (e) {
    // Degraded install (identity columns missing) → retry the minimal
    // legacy insert so account creation never dead-ends on schema drift.
    try {
      await db.run(
        'INSERT INTO `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `created_at`) VALUES (?, ?, ?, ?)',
        [identifierHash, id, authHash, now],
      );
    } catch (_) {
      // Lost a create race — it already exists.
      return fail(res, err('exists', 409, 'An account with this identifier already exists.'));
    }
  }
  res.status(201).json({ userId: id });
}));

api.post('/v1/accounts/lookup', h(async (req, res) => {
  const body = req.body || {};
  const identifierHash = body.identifierHash;
  if (!isHex64(identifierHash)) {
    return fail(res, err('bad_input', 400, 'identifierHash must be a 64-hex digest.'));
  }
  await db.ensureReady();
  const rows = await db.query('SELECT `created_at` FROM `accounts` WHERE `identifier_hash` = ?', [identifierHash]);
  if (!rows.length) return res.json({ exists: false });
  res.json({ exists: true, createdAt: Number(rows[0].created_at) || null });
}));

/* ── account profile (display name) ─────────────────────────────────── */

api.get('/v1/account', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();
  const rows = await db.query(
    'SELECT `user_id`, `identifier`, `identifier_type`, `display_name`, `status`, `sign_in_count`, `created_at`, `last_seen_at` FROM `accounts` WHERE `user_id` = ?',
    [session.userId],
  );
  if (!rows.length) return fail(res, err('not_found', 404, 'Account not found.'));
  const r = rows[0];
  res.json({
    ok: true,
    userId: String(r.user_id),
    identifier: r.identifier || null,
    identifierType: r.identifier_type || null,
    displayName: r.display_name || null,
    status: String(r.status || 'active'),
    signInCount: Number(r.sign_in_count) || 0,
    createdAt: Number(r.created_at) || null,
    lastSeenAt: r.last_seen_at == null ? null : Number(r.last_seen_at),
  });
}));

api.patch('/v1/account', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const body = req.body || {};
  if (typeof body.displayName !== 'string' || body.displayName.trim().length > 64) {
    return fail(res, err('bad_input', 400, 'displayName string (≤ 64 chars) is required.'));
  }
  const now = Date.now();
  try {
    await db.run('UPDATE `accounts` SET `display_name` = ? WHERE `user_id` = ?', [
      body.displayName.trim() || null,
      session.userId,
    ]);
  } catch (_) {
    return fail(res, err('server', 500, 'Profile storage unavailable.'));
  }
  res.json({ ok: true });
}));

/* ── login / session creation ───────────────────────────────────────── */

async function createSession(req, res) {
  const body = req.body || {};
  const identifierHash = body.identifierHash;
  const authKey = body.authKey;
  if (!isHex64(identifierHash) || !isHex64(authKey)) {
    return fail(res, err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.'));
  }
  await db.ensureReady();

  let rows = await db.query(
    'SELECT `user_id`, `auth_hash`, `status`, `identifier`, `display_name`, `sign_in_count` FROM `accounts` WHERE `identifier_hash` = ?',
    [identifierHash],
  );

  // First sign-in after the hosting switch: import from the old Worker.
  if (!rows.length && config.migrateFromUrl) {
    await migrateImportFromWorker(config.migrateFromUrl, identifierHash, authKey);
    rows = await db.query(
      'SELECT `user_id`, `auth_hash`, `status`, `identifier`, `display_name`, `sign_in_count` FROM `accounts` WHERE `identifier_hash` = ?',
      [identifierHash],
    );
  }
  if (!rows.length) {
    return fail(res, err('no_account', 404, 'No account for this identifier.'));
  }

  const record = rows[0];
  const authHash = hashAuthKey(authKey, String(record.user_id));
  const stored = String(record.auth_hash);
  const a = Buffer.from(authHash, 'hex');
  const b = Buffer.from(stored, 'hex');
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return fail(res, err('bad_credentials', 401, 'Wrong identifier or password.'));
  }

  // Owner-set lifecycle flag: a disabled account cannot open sessions.
  if (String(record.status || 'active') === 'disabled') {
    return fail(res, err('account_disabled', 403, 'This account has been disabled.'));
  }

  // ── activity + identity audit (all best-effort: a degraded schema —
  // missing columns — must never block a login) ─────────────────────────
  try {
    const now = Date.now();
    const identity = readIdentity(body);
    const sets = ['`last_seen_at` = ?', '`last_seen_dt` = ?', '`sign_in_count` = COALESCE(`sign_in_count`, 0) + 1'];
    const params = [now, dtOf(now)];
    // Backfill the readable identifier / display name the first time an
    // updated client signs in. First source wins — never overwrite.
    if (identity.identifier && !record.identifier) {
      sets.push('`identifier` = COALESCE(`identifier`, ?)', '`identifier_type` = COALESCE(`identifier_type`, ?)');
      params.push(identity.identifier, identity.identifierType);
    }
    if (identity.displayName && !record.display_name) {
      sets.push('`display_name` = COALESCE(`display_name`, ?)');
      params.push(identity.displayName);
    }
    params.push(String(record.user_id));
    await db.run(`UPDATE \`accounts\` SET ${sets.join(', ')} WHERE \`user_id\` = ?`, params);
    await db.run('INSERT INTO `sign_ins` (`user_id`, `at`, `at_dt`) VALUES (?, ?, ?)', [
      String(record.user_id),
      now,
      dtOf(now),
    ]);
    // Retention: keep 90 days of sign-in history (~5% of logins).
    if (Math.random() < 0.05) {
      await db.run('DELETE FROM `sign_ins` WHERE `at` < ?', [now - 90 * 24 * 3600 * 1000]);
    }
  } catch (_) {
    // Pre-migration table / no ALTER rights — API timestamps still move.
  }

  res.json(await issueSessionTokens(String(record.user_id)));
}

api.post('/v1/session', h((req, res) => createSession(req, res)));
api.post('/v1/auth/token', h((req, res) => createSession(req, res)));

/* ── refresh token rotation (single-use, reuse-detecting) ───────────── */

async function refreshSession(req, res) {
  const body = req.body || {};
  const refreshToken = body.refreshToken;
  if (!refreshToken || typeof refreshToken !== 'string') {
    return fail(res, err('bad_input', 400, 'refreshToken string is required.'));
  }
  await db.ensureReady();

  const rows = await db.query('SELECT `user_id`, `exp` FROM `refresh_tokens` WHERE `token` = ?', [refreshToken]);
  if (!rows.length) {
    return fail(res, err('invalid_grant', 401, 'Refresh token is invalid, expired, or already used.'));
  }
  const row = rows[0];
  if (!row.user_id || Number(row.exp) * 1000 < Date.now()) {
    await db.run('DELETE FROM `refresh_tokens` WHERE `token` = ?', [refreshToken]);
    return fail(res, err('invalid_grant', 401, 'Refresh token has expired.'));
  }

  // Single-use rotation: consume the old token, then issue fresh ones.
  await db.run('DELETE FROM `refresh_tokens` WHERE `token` = ?', [refreshToken]);
  res.json(await issueSessionTokens(String(row.user_id)));
}

api.post('/v1/session/refresh', h((req, res) => refreshSession(req, res)));
api.post('/v1/auth/refresh', h((req, res) => refreshSession(req, res)));

/* ── session revocation / check ─────────────────────────────────────── */

async function revoke(req, res) {
  const body = req.body || {};
  const refreshToken = body.refreshToken;
  if (refreshToken && typeof refreshToken === 'string') {
    await db.ensureReady();
    await db.run('DELETE FROM `refresh_tokens` WHERE `token` = ?', [refreshToken]);
  }
  res.json({ ok: true });
}

api.delete('/v1/session', h((req, res) => revoke(req, res)));
api.post('/v1/auth/revoke', h((req, res) => revoke(req, res)));

async function checkSession(req, res) {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  res.json({ userId: session.userId, exp: session.exp, ok: true });
}

api.get('/v1/session', h((req, res) => checkSession(req, res)));
api.get('/v1/auth/me', h((req, res) => checkSession(req, res)));

/* ── encrypted vault sync ───────────────────────────────────────────── */

api.put('/v1/vault', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const body = req.body || {};
  const blob = body.blob;
  const revision = Number(body.revision);
  if (!isBase64ish(blob) || !Number.isFinite(revision) || revision <= 0) {
    return fail(res, err('bad_input', 400, 'blob must be base64 and revision a positive number.'));
  }

  const existing = await db.query('SELECT `revision`, `updated_at` FROM `vaults` WHERE `user_id` = ?', [session.userId]);

  // Optimistic concurrency check (mirrors the Worker exactly).
  if (
    existing.length &&
    body.baseRevision !== undefined &&
    body.baseRevision !== null
  ) {
    if (Number(existing[0].revision) > Number(body.baseRevision)) {
      return res.status(409).json({
        error: 'conflict',
        revision: Number(existing[0].revision),
        updatedAt: Number(existing[0].updated_at),
      });
    }
  }

  const updatedAt = Date.now();
  await db.upsert('vaults', ['user_id', 'blob', 'revision', 'updated_at'], ['blob', 'revision', 'updated_at'], [
    session.userId,
    String(blob),
    revision,
    updatedAt,
  ]);
  res.json({ ok: true, revision, updatedAt });
}));

api.get('/v1/vault', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const rows = await db.query('SELECT `blob`, `revision`, `updated_at` FROM `vaults` WHERE `user_id` = ?', [session.userId]);
  if (!rows.length) {
    return fail(res, err('empty', 404, 'No vault stored yet.'));
  }
  const vault = rows[0];
  const since = req.query.sinceRevision;
  if (since !== undefined && Number(since) === Number(vault.revision)) {
    return res.json({ notModified: true, revision: Number(vault.revision) });
  }
  res.json({
    blob: String(vault.blob),
    revision: Number(vault.revision),
    updatedAt: Number(vault.updated_at),
  });
}));

api.delete('/v1/vault', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();
  await db.run('DELETE FROM `vaults` WHERE `user_id` = ?', [session.userId]);
  res.json({ ok: true });
}));

/* ── monthly Pro receipt ledger ─────────────────────────────────────── */
// The app verifies the Telebirr/M-Pesa receipt first, then submits only its
// SHA-256 reference fingerprint through the user's normal session.

api.post('/v1/pro/claim', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const body = req.body || {};
  const receiptHash = body.receiptHash;
  const amountEtb = Number(body.amountEtb);
  const planDays = Number(body.planDays);
  const paidAtMs = Number(body.paidAtMs);
  if (!isHex64(receiptHash) || amountEtb !== PLAN_AMOUNT_ETB || planDays !== PLAN_DAYS) {
    return fail(res, err('bad_input', 400, 'A monthly claim requires a receipt hash, 300 ETB, and 31 days.'));
  }

  const existing = await db.query('SELECT `user_id`, `expires_at` FROM `pro_receipts` WHERE `receipt_hash` = ?', [receiptHash]);
  if (existing.length) {
    const row = existing[0];
    if (String(row.user_id) !== session.userId) {
      return fail(res, err('receipt_used', 409, 'This payment has already been used by another account.'));
    }
    return res.json({ ok: true, alreadyClaimed: true, expiresAt: Number(row.expires_at) || Date.now() });
  }

  const prior = await db.query('SELECT `expires_at` FROM `pro_status` WHERE `user_id` = ?', [session.userId]);
  const currentExpiry = prior.length ? Number(prior[0].expires_at) || 0 : 0;
  const expiresAt = Math.max(Date.now(), currentExpiry) + PLAN_MS;

  await db.run(
    'INSERT INTO `pro_receipts` (`receipt_hash`, `user_id`, `amount_etb`, `plan_days`, `paid_at_ms`, `claimed_at`, `expires_at`) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      receiptHash,
      session.userId,
      PLAN_AMOUNT_ETB,
      PLAN_DAYS,
      Number.isFinite(paidAtMs) ? paidAtMs : null,
      Date.now(),
      expiresAt,
    ],
  );
  await db.upsert('pro_status', ['user_id', 'expires_at', 'updated_at'], ['expires_at', 'updated_at'], [
    session.userId,
    expiresAt,
    Date.now(),
  ]);

  res.json({ ok: true, alreadyClaimed: false, expiresAt });
}));

api.get('/v1/pro/status', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const rows = await db.query('SELECT `expires_at` FROM `pro_status` WHERE `user_id` = ?', [session.userId]);
  if (!rows.length) return res.json({ entitled: false, expiresAt: null });
  const expiresAt = Number(rows[0].expires_at) || 0;
  res.json({ entitled: expiresAt > Date.now(), expiresAt });
}));

/* ── verified receipt ledger ────────────────────────────────────────── */
// Every verification the app runs while the user is signed in is mirrored
// here (bank, reference, the payload it was checked with, parties, amount,
// outcome) so the receipt history lives in the Plesk database per account,
// not only in the encrypted vault. Writes are idempotent per history-entry
// id, so client retries after a lost response never duplicate rows.

function receiptRowView(r) {
  return {
    id: Number(r.id),
    entryId: r.entry_id,
    bankId: r.bank_id,
    bankName: r.bank_name,
    reference: r.reference,
    rawPayload: r.raw_payload,
    senderName: r.sender_name,
    receiverName: r.receiver_name,
    amount: r.amount == null ? null : Number(r.amount),
    currency: r.currency,
    receiptDate: r.receipt_date,
    status: r.status,
    message: r.message,
    reason: r.reason,
    verifiedAt: Number(r.verified_at),
    createdAt: Number(r.created_at),
  };
}

const RECEIPT_STR_MAX = {
  bankId: 32,
  bankName: 64,
  reference: 255,
  rawPayload: 4000,
  senderName: 128,
  receiverName: 128,
  currency: 8,
  receiptDate: 64,
  message: 512,
  reason: 255,
};

api.post('/v1/receipts', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const body = req.body || {};
  const clip = (v, max) => (typeof v === 'string' ? v.slice(0, max) : null);
  const entryId = clip(body.entryId, 64);
  if (!entryId || typeof body.bankId !== 'string' || !body.bankId.trim()) {
    return fail(res, err('bad_input', 400, 'entryId and bankId are required.'));
  }
  if (body.status !== 'verified' && body.status !== 'failed') {
    return fail(res, err('bad_input', 400, "status must be 'verified' or 'failed'."));
  }
  const amount = Number(body.amount);

  const row = {
    user_id: session.userId,
    entry_id: entryId,
    bank_id: clip(body.bankId.trim(), RECEIPT_STR_MAX.bankId),
    bank_name: clip(body.bankName, RECEIPT_STR_MAX.bankName) || '',
    reference: clip(body.reference, RECEIPT_STR_MAX.reference) || '',
    raw_payload: clip(body.rawPayload, RECEIPT_STR_MAX.rawPayload),
    sender_name: clip(body.senderName, RECEIPT_STR_MAX.senderName),
    receiver_name: clip(body.receiverName, RECEIPT_STR_MAX.receiverName),
    amount: Number.isFinite(amount) ? amount : null,
    currency: clip(body.currency, RECEIPT_STR_MAX.currency),
    receipt_date: clip(body.receiptDate, RECEIPT_STR_MAX.receiptDate),
    status: body.status,
    message: clip(body.message, RECEIPT_STR_MAX.message),
    reason: clip(body.reason, RECEIPT_STR_MAX.reason),
    verified_at: Number(body.verifiedAt) || Date.now(),
    created_at: Date.now(),
  };

  const existing = await db.query(
    'SELECT `id` FROM `verified_receipts` WHERE `user_id` = ? AND `entry_id` = ?',
    [row.user_id, row.entry_id],
  );
  if (existing.length) {
    // Already recorded (lost-response retry). Only the user's reason note
    // may move — the first verification answer stays authoritative.
    if (row.reason) {
      await db.run(
        'UPDATE `verified_receipts` SET `reason` = ? WHERE `user_id` = ? AND `entry_id` = ?',
        [row.reason, row.user_id, row.entry_id],
      );
    }
    return res.json({ ok: true, duplicate: true, id: Number(existing[0].id) });
  }

  await db.run(
    'INSERT INTO `verified_receipts` (`user_id`, `entry_id`, `bank_id`, `bank_name`, `reference`, `raw_payload`, `sender_name`, `receiver_name`, `amount`, `currency`, `receipt_date`, `status`, `message`, `reason`, `verified_at`, `verified_dt`, `created_at`, `created_dt`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      row.user_id,
      row.entry_id,
      row.bank_id,
      row.bank_name,
      row.reference,
      row.raw_payload,
      row.sender_name,
      row.receiver_name,
      row.amount,
      row.currency,
      row.receipt_date,
      row.status,
      row.message,
      row.reason,
      row.verified_at,
      dtOf(row.verified_at),
      row.created_at,
      dtOf(row.created_at),
    ],
  );
  res.status(201).json({ ok: true, duplicate: false });
}));

api.get('/v1/receipts', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();

  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);
  const rows = await db.query(
    'SELECT * FROM `verified_receipts` WHERE `user_id` = ? ORDER BY `verified_at` DESC, `id` DESC LIMIT ' + limit,
    [session.userId],
  );
  res.json({ ok: true, count: rows.length, receipts: rows.map(receiptRowView) });
}));

api.delete('/v1/receipts', h(async (req, res) => {
  const session = await requireSession(req);
  if (!guard(res, session)) return;
  await db.ensureReady();
  await db.run('DELETE FROM `verified_receipts` WHERE `user_id` = ?', [session.userId]);
  res.json({ ok: true });
}));

/* ── geo-block relay (strict allowlist — never an open proxy) ───────── */
// Telebirr and M-Pesa receipt endpoints refuse non-Ethiopian client IPs.
// The app asks THIS server to fetch the receipt page on the user's behalf;
// only those two banks' own receipt hosts are ever fetched, GET only.

const ALLOWED_RELAY_HOSTS = {
  telebirr: ['transactioninfo.ethiotelecom.et'],
  mpesa: ['m-pesabusiness.safaricom.et'],
};

api.post('/v1/relay', h(async (req, res) => {
  const body = req.body || {};
  const bank = body.bank;
  const target = body.url;

  if (!Object.prototype.hasOwnProperty.call(ALLOWED_RELAY_HOSTS, bank)) {
    return fail(res, err('bad_bank', 400, 'bank must be telebirr or mpesa.'));
  }
  if (typeof target !== 'string' || target === '') {
    return fail(res, err('bad_url', 400, 'url must be an absolute URL.'));
  }
  let u;
  try {
    u = new URL(target);
  } catch (_) {
    return fail(res, err('bad_url', 400, 'url must be an absolute URL.'));
  }
  if (u.protocol !== 'https:') {
    return fail(res, err('bad_url', 400, 'url must be an absolute URL.'));
  }
  if (!ALLOWED_RELAY_HOSTS[bank].includes(u.hostname.toLowerCase())) {
    return fail(res, err('bad_host', 400, 'url host is not relay-allowed.'));
  }

  try {
    const upstream = await fetch(u.toString(), {
      method: 'GET',
      redirect: 'follow',
      signal: AbortSignal.timeout(12_000),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        Accept: 'text/html,application/json,*/*',
      },
    });
    let text = await upstream.text();
    if (text.length > 1_000_000) text = text.slice(0, 1_000_000);
    res.json({ ok: true, status: upstream.status, body: text });
  } catch (_) {
    return fail(res, err('relay_failed', 502, 'Could not reach the bank.'));
  }
}));

/* ── fallthrough ────────────────────────────────────────────────────── */

api.use('/v1', (req, res) => {
  res.status(404).json({ error: 'not_found', message: 'Unknown route.' });
});

app.use(api);

// Malformed JSON bodies and unexpected errors (never leak diagnostics).
app.use((e, req, res, next) => { // eslint-disable-line no-unused-vars
  if (e && (e.type === 'entity.parse.failed' || e instanceof SyntaxError)) {
    return res.status(400).json({ error: 'bad_input', message: 'Malformed JSON body.' });
  }
  if (e && e.type === 'entity.too.large') {
    return res.status(413).json({ error: 'bad_input', message: 'Request body too large.' });
  }
  console.error('[mahtem-api]', req.method, req.originalUrl, '-', e && (e.stack || e.message || e));
  res.status(500).json({ error: 'server', message: 'Unexpected server error.' });
});

module.exports = app;
