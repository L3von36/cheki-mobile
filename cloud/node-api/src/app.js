'use strict';

/**
 * Mahtem Cloud API (v1.15.0-node) — Zero-Knowledge OAuth 2.1 / JWT backend.
 *
 * Node.js/Express + MySQL port of `cloud/worker.js` (Cloudflare Worker) for
 * Plesk shared hosting (Phusion Passenger). Route map, request/response
 * shapes, error codes and status codes are identical to the Worker, so the
 * Flutter client (lib/core/cloud/cloud_api.dart) works without changes.
 *
 * PRIVACY CONTRACT (Zero-Knowledge, identical to the Worker):
 *   * Client derives `authKey = PBKDF2(password, "mahtem-cloud-auth-v1")`.
 *     The raw password never reaches this server.
 *   * Stored `identifierHash = SHA-256(identifier)` — never raw email/phone.
 *   * Vault (history backup) is AES-256-GCM encrypted on-device. This server
 *     cannot decrypt it.
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
  try {
    await db.run(
      'INSERT INTO `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `created_at`) VALUES (?, ?, ?, ?)',
      [identifierHash, id, authHash, Date.now()],
    );
  } catch (e) {
    // Lost a create race — it already exists.
    return fail(res, err('exists', 409, 'An account with this identifier already exists.'));
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

/* ── login / session creation ───────────────────────────────────────── */

async function createSession(req, res) {
  const body = req.body || {};
  const identifierHash = body.identifierHash;
  const authKey = body.authKey;
  if (!isHex64(identifierHash) || !isHex64(authKey)) {
    return fail(res, err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.'));
  }
  await db.ensureReady();

  let rows = await db.query('SELECT `user_id`, `auth_hash` FROM `accounts` WHERE `identifier_hash` = ?', [identifierHash]);

  // First sign-in after the hosting switch: import from the old Worker.
  if (!rows.length && config.migrateFromUrl) {
    await migrateImportFromWorker(config.migrateFromUrl, identifierHash, authKey);
    rows = await db.query('SELECT `user_id`, `auth_hash` FROM `accounts` WHERE `identifier_hash` = ?', [identifierHash]);
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
