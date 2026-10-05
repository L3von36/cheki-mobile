/**
 * Mahtem Cloud API (v1.15.0) — Zero-Knowledge OAuth 2.1 / JWT Authentication.
 *
 * Runs on Cloudflare Workers with a KV namespace binding (KV).
 * Deployed at https://mahtem-api.mahtem.workers.dev
 *
 * PRIVACY CONTRACT (Zero-Knowledge intact):
 *   * Client derives `authKey = PBKDF2(password, "mahtem-cloud-auth-v1")` on-device.
 *     The raw password never reaches us.
 *   * Stored `identifierHash = SHA-256(identifier)` — never raw email/phone.
 *   * Vault (history backup) is AES-GCM encrypted on-device. The server cannot decrypt it.
 *
 * PROFESSIONAL TOKEN ARCHITECTURE:
 *   * Short-lived Access Token (JWT, HS256) signed with Web Crypto HMAC-SHA256.
 *     - Expiry: 15 minutes (900 seconds).
 *     - Stateless verification: Zero KV read overhead for protected API requests!
 *   * Rotating Refresh Token stored in KV:
 *     - Expiry: 30 days.
 *     - Single-use: Every refresh issues a new refresh token and deletes the old one.
 *     - Reuse detection: If an expired or already-used token is submitted, access is rejected.
 *   * Instant Revocation:
 *     - Explicit logout revokes the refresh token from KV immediately.
 *   * Backwards Compatibility:
 *     - Existing legacy session tokens continue to be accepted during rollout.
 *
 * ADMIN (owner-only; v1.15.0 dashboard, v1.16.0 email+password sign-in,
 * v1.17.0 per-account drill-down + 30-day series):
 *   * GET /admin  — single-page owner dashboard (browser, no client header).
 *   * GET /v1/admin/overview — aggregates every account + vault: totals,
 *     bank popularity (with verified counts), 30-day scan series,
 *     per-account rows, recent scans.
 *   * GET /v1/admin/account/<8-hex prefix> — one account's detail: bank
 *     breakdown, 30-day series, recent events (metadata only, no blob).
 *   * Owner account: ONE owner record (email + PBKDF2-SHA-256 hash, 100k
 *     iterations, per-record random salt — the password never touches
 *     storage). First-run setup creates it; login mints opaque 32-byte
 *     session tokens stored in KV (`adm_s:<token>`, 30-day TTL); login is
 *     rate limited per email. Change-password rotates every session.
 *     Break-glass: POST /v1/admin/auth/reset with the ADMIN_KEY removes
 *     the owner + all sessions (forgotten-password recovery path).
 *   * `/v1/admin/overview` accepts BOTH the legacy `Authorization: Bearer
 *     <ADMIN_KEY>` (pre-v1.1.0 clients + break-glass) and owner sessions.
 *   * Analytics piggyback: vault PUTs may carry `stats` — bank-only events
 *     {b,n,t,v}. NO receipt contents, names, amounts or references exist
 *     outside the encrypted blob; zero-knowledge stays intact.
 */

const CLIENT_HEADER = 'x-mahtem-client';
const ACCESS_TOKEN_TTL_SECONDS = 15 * 60; // 15 minutes
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const LEGACY_SESSION_TTL_SECONDS = 90 * 24 * 3600; // 90 days

// Admin owner account (email + password) — v1.16.0
const ADMIN_OWNER_KEY = 'adm_owner';
const ADMIN_SESSION_PREFIX = 'adm_s:';
const ADMIN_SESSION_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const ADMIN_PBKDF2_ITERATIONS = 100_000;
const ADMIN_LOGIN_WINDOW_MS = 15 * 60 * 1000;
const ADMIN_LOGIN_MAX_ATTEMPTS = 8;
const ADMIN_EMAIL_RE = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Mahtem-Client',
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', ...CORS_HEADERS },
  });

const err = (code, status, message) => json({ error: code, message }, status);

// ── Web Crypto Helpers ──────────────────────────────────────────────────────

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function randomToken(byteCount = 32) {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function base64UrlEncode(bufferOrString) {
  const bytes =
    typeof bufferOrString === 'string'
      ? new TextEncoder().encode(bufferOrString)
      : new Uint8Array(bufferOrString);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function base64UrlDecode(str) {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// ── JWT Engine (Web Crypto HS256) ───────────────────────────────────────────

let _cachedJwtSecretKey = null;
let _cachedJwtSecret = null;

async function getOrInitJwtKey(env) {
  let secret = env.JWT_SECRET;
  if (!secret || typeof secret !== 'string' || secret.length < 32) {
    // Persistent secret stored in KV
    const kvKey = 'config:jwt_secret';
    secret = await env.KV.get(kvKey);
    if (!secret) {
      secret = randomToken(32);
      await env.KV.put(kvKey, secret);
    }
  }

  if (_cachedJwtSecretKey && _cachedJwtSecret === secret) {
    return _cachedJwtSecretKey;
  }

  _cachedJwtSecret = secret;
  _cachedJwtSecretKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
  return _cachedJwtSecretKey;
}

async function signAccessToken(userId, env) {
  const key = await getOrInitJwtKey(env);
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ACCESS_TOKEN_TTL_SECONDS;
  const payload = {
    sub: userId,
    iss: 'mahtem-api',
    type: 'access',
    iat: now,
    exp,
    jti: crypto.randomUUID(),
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const data = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);
  const signature = await crypto.subtle.sign('HMAC', key, data);
  const encodedSignature = base64UrlEncode(signature);

  return {
    jwt: `${encodedHeader}.${encodedPayload}.${encodedSignature}`,
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    expiresAt: exp * 1000,
  };
}

async function verifyAccessToken(token, env) {
  if (typeof token !== 'string') return { ok: false, error: 'invalid' };
  const parts = token.split('.');
  if (parts.length !== 3) return { ok: false, error: 'invalid' };

  try {
    const [h64, p64, s64] = parts;
    const data = new TextEncoder().encode(`${h64}.${p64}`);
    const signature = base64UrlDecode(s64);
    const key = await getOrInitJwtKey(env);

    const valid = await crypto.subtle.verify('HMAC', key, signature, data);
    if (!valid) return { ok: false, error: 'invalid_signature' };

    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(p64)));
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) {
      return { ok: false, error: 'expired', payload };
    }
    return { ok: true, payload };
  } catch (_) {
    return { ok: false, error: 'malformed' };
  }
}

/** Server-side pepper for authKey */
async function hashAuthKey(authKey, userId) {
  return sha256Hex(`${userId}:${authKey}`);
}

const isHex64 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
const isBase64 = (s) =>
  typeof s === 'string' && s.length > 16 && s.length <= 4_000_000;

const MAX_STATS_EVENTS = 1000; // per-vault cap, newest kept

/** Canonicalizes one analytics piggyback event; null when malformed. */
function canonStatEvent(e) {
  if (!e || typeof e !== 'object') return null;
  const b = typeof e.b === 'string' ? e.b.trim().slice(0, 40) : '';
  const n = typeof e.n === 'string' ? e.n.trim().slice(0, 60) : '';
  const t = Number(e.t);
  if (!b || !Number.isFinite(t) || t <= 0) return null;
  return { b, n, t: Math.floor(t), v: e.v === 1 || e.v === true ? 1 : 0 };
}

async function readJson(request) {
  try {
    return await request.json();
  } catch (_) {
    return null;
  }
}

/**
 * Session verification:
 * 1. Checks if Authorization header is a signed JWT. If valid -> returns userId with 0 KV reads!
 * 2. Checks legacy sess:${token} in KV if not a JWT (backwards compatible).
 */
async function requireSession(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return { ok: false, status: 401, error: 'missing_token', message: 'Session token required.' };

  // 1. Fast Stateless JWT Check
  if (token.split('.').length === 3) {
    const verification = await verifyAccessToken(token, env);
    if (verification.ok && verification.payload?.sub) {
      return {
        ok: true,
        token,
        userId: verification.payload.sub,
        exp: verification.payload.exp,
      };
    }
    if (verification.error === 'expired') {
      return {
        ok: false,
        status: 401,
        error: 'token_expired',
        message: 'Access token has expired. Use /v1/auth/refresh to renew.',
      };
    }
    return {
      ok: false,
      status: 401,
      error: 'invalid_token',
      message: 'Access token is invalid or signature check failed.',
    };
  }

  // 2. Fallback to Legacy KV Session Store
  const raw = await env.KV.get(`sess:${token}`);
  if (!raw) return { ok: false, status: 401, error: 'unauthorized', message: 'Session missing or expired.' };
  let session;
  try {
    session = JSON.parse(raw);
  } catch (_) {
    return { ok: false, status: 401, error: 'unauthorized', message: 'Session corrupted.' };
  }
  if (!session.userId || (session.exp || 0) * 1000 < Date.now()) {
    return { ok: false, status: 401, error: 'unauthorized', message: 'Session expired.' };
  }
  return { ok: true, token, userId: session.userId, exp: session.exp };
}

// ── Admin (owner-only, v1.15.0; email+password v1.16.0) ─────────────────────

function bytesToHex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/** Constant-time compare of two equal-length hex strings. */
function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** PBKDF2-SHA-256 password hash (hex). Runs in Web Crypto — native code. */
async function hashPassword(password, saltHex, iterations) {
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      hash: 'SHA-256',
      salt: hexToBytes(saltHex),
      iterations,
    },
    keyMaterial,
    256,
  );
  return bytesToHex(new Uint8Array(bits));
}

const normalizeEmail = (raw) =>
  typeof raw === 'string' ? raw.trim().toLowerCase() : '';

const isValidEmail = (s) =>
  typeof s === 'string' && s.length <= 254 && ADMIN_EMAIL_RE.test(s);

const isValidPassword = (s) =>
  typeof s === 'string' && s.length >= 10 && s.length <= 256;

async function getOwner(env) {
  const raw = await env.KV.get(ADMIN_OWNER_KEY);
  if (!raw) return null;
  try {
    const r = JSON.parse(raw);
    if (
      r &&
      typeof r.email === 'string' &&
      typeof r.hash === 'string' &&
      typeof r.salt === 'string'
    ) {
      return r;
    }
    return null;
  } catch (_) {
    return null;
  }
}

async function createAdminSession(env, email) {
  const token = randomToken(32);
  const now = Date.now();
  const exp = now + ADMIN_SESSION_TTL_SECONDS * 1000;
  await env.KV.put(
    `${ADMIN_SESSION_PREFIX}${token}`,
    JSON.stringify({
      e: email,
      iat: Math.floor(now / 1000),
      exp: Math.floor(exp / 1000),
    }),
    { expirationTtl: ADMIN_SESSION_TTL_SECONDS },
  );
  return { token, email, expiresAt: exp };
}

/** Validates the Bearer token of an admin auth endpoint (sessions only). */
async function requireAdminSession(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) {
    return {
      ok: false,
      status: 401,
      error: 'admin_required',
      message: 'Sign in required.',
    };
  }
  const raw = await env.KV.get(`${ADMIN_SESSION_PREFIX}${token}`);
  if (!raw) {
    return {
      ok: false,
      status: 401,
      error: 'admin_session_expired',
      message: 'Session expired — sign in again.',
    };
  }
  let sess = null;
  try {
    sess = JSON.parse(raw);
  } catch (_) {
    sess = null;
  }
  if (!sess || !sess.e || (sess.exp || 0) * 1000 < Date.now()) {
    return {
      ok: false,
      status: 401,
      error: 'admin_session_expired',
      message: 'Session expired — sign in again.',
    };
  }
  return { ok: true, token, email: sess.e, exp: sess.exp };
}

async function checkLoginAllowed(env, email) {
  const raw = await env.KV.get(`adm_rl:${email}`);
  if (!raw) return true;
  try {
    const r = JSON.parse(raw);
    return !(r && r.reset > Date.now() && (r.c || 0) >= ADMIN_LOGIN_MAX_ATTEMPTS);
  } catch (_) {
    return true;
  }
}

async function recordLoginFailure(env, email) {
  const key = `adm_rl:${email}`;
  const raw = await env.KV.get(key);
  let c = 0;
  let reset = Date.now() + ADMIN_LOGIN_WINDOW_MS;
  if (raw) {
    try {
      const r = JSON.parse(raw);
      if (r && r.reset > Date.now()) {
        c = r.c || 0;
        reset = r.reset;
      }
    } catch (_) {
      /* fresh window */
    }
  }
  await env.KV.put(key, JSON.stringify({ c: c + 1, reset }), {
    expirationTtl: Math.max(60, Math.ceil((reset - Date.now()) / 1000)),
  });
}

/**
 * Admin gate for /v1/admin/overview. Accepts, in order:
 *   1. An owner session token (email+password sign-in, `adm_s:*` in KV).
 *   2. The legacy ADMIN_KEY secret (pre-v1.1.0 clients + break-glass).
 * 503 only when the deployment has neither an owner nor an ADMIN_KEY.
 */
async function requireAdmin(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) {
    return {
      ok: false,
      status: 401,
      error: 'admin_required',
      message: 'Sign in required.',
    };
  }
  const raw = await env.KV.get(`${ADMIN_SESSION_PREFIX}${token}`);
  if (raw) {
    try {
      const sess = JSON.parse(raw);
      if (sess && sess.e && (sess.exp || 0) * 1000 >= Date.now()) {
        return { ok: true, email: sess.e };
      }
    } catch (_) {
      /* fall through to the legacy path */
    }
  }
  const expected = env.ADMIN_KEY;
  const keyConfigured =
    typeof expected === 'string' && expected.length >= 16;
  if (keyConfigured) {
    // Digest comparison — no timing side channel on the secret.
    const [a, b] = await Promise.all([sha256Hex(token), sha256Hex(expected)]);
    if (a === b) return { ok: true, legacy: true };
  }
  if (!keyConfigured && !(await getOwner(env))) {
    return {
      ok: false,
      status: 503,
      error: 'admin_disabled',
      message:
        'Admin access is not configured on this deployment (no owner account, ADMIN_KEY secret missing).',
    };
  }
  return {
    ok: false,
    status: 401,
    error: 'admin_required',
    message: 'Session expired — sign in again.',
  };
}

async function listAllKeys(env, prefix) {
  const names = [];
  let cursor;
  do {
    const page = await env.KV.list(
      cursor ? { prefix, cursor } : { prefix },
    );
    for (const k of page.keys) names.push(k.name);
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return names;
}

async function buildAdminOverview(env) {
  const now = Date.now();
  const dayMs = 24 * 3600 * 1000;
  const todayStart = Math.floor(now / dayMs) * dayMs;

  // Accounts (identifier hashes + creation dates).
  const accounts = [];
  for (const name of await listAllKeys(env, 'user:')) {
    const raw = await env.KV.get(name);
    if (!raw) continue;
    try {
      const r = JSON.parse(raw);
      accounts.push({
        id: typeof r.id === 'string' ? r.id : name.slice(5),
        hash: name.slice(5, 13), // 8-hex prefix — never the full digest
        createdAt: r.createdAt ?? null,
      });
    } catch (_) {
      /* skip corrupt record */
    }
  }
  const createdOf = new Map(accounts.map((a) => [a.id, a.createdAt]));

  // Vaults + piggybacked analytics events.
  const perBank = new Map();
  const perDay = new Map();
  const accountRows = [];
  const recent = [];
  let vaultCount = 0;
  let totalScans = 0;
  let verifiedScans = 0;
  let scansToday = 0;
  let scans7d = 0;
  let scans30d = 0;

  for (const name of await listAllKeys(env, 'vault:')) {
    const raw = await env.KV.get(name);
    if (!raw) continue;
    let v;
    try {
      v = JSON.parse(raw);
    } catch (_) {
      continue;
    }
    vaultCount++;
    const uid = name.slice(6);
    const events = Array.isArray(v.stats) ? v.stats : [];
    let lastScanAt = null;
    let topBank = null;
    let topCount = 0;
    const bankCount = new Map();
    for (const ev of events) {
      totalScans++;
      if (ev.v === 1) verifiedScans++;
      if (ev.t >= todayStart) scansToday++;
      if (ev.t >= now - 7 * dayMs) scans7d++;
      if (ev.t >= now - 30 * dayMs) scans30d++;
      const day = new Date(ev.t).toISOString().slice(0, 10);
      perDay.set(day, (perDay.get(day) || 0) + 1);
      const bk = perBank.get(ev.b) || { id: ev.b, name: ev.b, count: 0, verified: 0 };
      bk.count++;
      if (ev.v === 1) bk.verified++;
      if (ev.n) bk.name = ev.n;
      perBank.set(ev.b, bk);
      const bc = (bankCount.get(ev.b) || 0) + 1;
      bankCount.set(ev.b, bc);
      if (bc > topCount) {
        topCount = bc;
        topBank = ev.n || ev.b;
      }
      if (lastScanAt === null || ev.t > lastScanAt) lastScanAt = ev.t;
      recent.push({
        t: ev.t,
        b: ev.b,
        n: ev.n || ev.b,
        v: ev.v === 1 ? 1 : 0,
        u: uid.slice(0, 8),
      });
    }
    accountRows.push({
      id: uid.slice(0, 8),
      createdAt: createdOf.get(uid) ?? null,
      revision: v.revision ?? null,
      updatedAt: v.updatedAt ?? null,
      scans: events.length,
      lastScanAt,
      topBank,
    });
  }
  accountRows.sort(
    (a, b) => b.scans - a.scans || (b.updatedAt || 0) - (a.updatedAt || 0),
  );
  const banks = [...perBank.values()].sort((a, b) => b.count - a.count);
  recent.sort((a, b) => b.t - a.t);
  const days = [];
  for (let i = 29; i >= 0; i--) {
    const d = new Date(todayStart - i * dayMs).toISOString().slice(0, 10);
    days.push({ day: d, count: perDay.get(d) || 0 });
  }

  return {
    generatedAt: now,
    totals: {
      accounts: accounts.length,
      vaults: vaultCount,
      scans: totalScans,
      verified: verifiedScans,
      scansToday,
      scans7d,
      scans30d,
      scanningAccounts7d: accountRows.filter(
        (r) => r.lastScanAt && r.lastScanAt >= now - 7 * dayMs,
      ).length,
    },
    banks: banks.slice(0, 24),
    days,
    accounts: accountRows.slice(0, 500),
    recent: recent.slice(0, 100),
  };
}

/**
 * Per-account drill-down for the admin console (v1.17.0). Served from the
 * same vault record the overview aggregates — still metadata only: bank
 * names, outcomes and timestamps. The encrypted blob is never returned.
 */
async function buildAdminAccountDetail(env, uidPrefix) {
  const now = Date.now();
  const dayMs = 24 * 3600 * 1000;
  const todayStart = Math.floor(now / dayMs) * dayMs;

  // Resolve the prefix (8-hex shown to admins, or a full 64-hex uid) to
  // exactly one vault. Ambiguous prefixes are rejected so the console can
  // never show the wrong account's data.
  const matches = await listAllKeys(env, `vault:${uidPrefix}`);
  if (matches.length === 0) return { notFound: true };
  if (matches.length > 1) {
    return {
      ambiguous: true,
      ids: matches.map((n) => n.slice(6, 14)),
    };
  }
  const uid = matches[0].slice(6);

  const [vaultRaw, userRaw] = await Promise.all([
    env.KV.get(matches[0]),
    env.KV.get(`user:${uid}`),
  ]);
  if (!vaultRaw) return { notFound: true };
  let vault;
  try {
    vault = JSON.parse(vaultRaw);
  } catch (_) {
    return { notFound: true };
  }
  let createdAt = null;
  if (userRaw) {
    try {
      createdAt = JSON.parse(userRaw).createdAt ?? null;
    } catch (_) {
      /* createdAt stays null */
    }
  }

  const events = Array.isArray(vault.stats) ? vault.stats : [];
  const perBank = new Map();
  const perDay = new Map();
  let verified = 0;
  let lastScanAt = null;
  for (const ev of events) {
    if (ev.v === 1) verified++;
    const bk = perBank.get(ev.b) || { id: ev.b, name: ev.b, count: 0, verified: 0 };
    bk.count++;
    if (ev.v === 1) bk.verified++;
    if (ev.n) bk.name = ev.n;
    perBank.set(ev.b, bk);
    const day = new Date(ev.t).toISOString().slice(0, 10);
    perDay.set(day, (perDay.get(day) || 0) + 1);
    if (lastScanAt === null || ev.t > lastScanAt) lastScanAt = ev.t;
  }
  const banks = [...perBank.values()].sort((a, b) => b.count - a.count);
  const days = [];
  for (let i = 29; i >= 0; i--) {
    const d = new Date(todayStart - i * dayMs).toISOString().slice(0, 10);
    days.push({ day: d, count: perDay.get(d) || 0 });
  }

  return {
    id: uid.slice(0, 8),
    createdAt,
    revision: vault.revision ?? null,
    updatedAt: vault.updatedAt ?? null,
    scans: events.length,
    verified,
    lastScanAt,
    banks,
    days,
    events: events.slice(0, 200).map((ev) => ({
      t: ev.t,
      b: ev.b,
      n: ev.n || ev.b,
      v: ev.v === 1 ? 1 : 0,
    })),
  };
}

// ── Refresh Token Management ────────────────────────────────────────────────

async function issueSessionTokens(userId, env) {
  const { jwt, expiresIn, expiresAt } = await signAccessToken(userId, env);
  const refreshToken = randomToken(32);
  const exp = Math.floor(Date.now() / 1000) + REFRESH_TOKEN_TTL_SECONDS;

  // Store refresh token in KV with auto-expiry
  await env.KV.put(
    `ref:${refreshToken}`,
    JSON.stringify({ userId, exp, createdAt: Date.now() }),
    { expirationTtl: REFRESH_TOKEN_TTL_SECONDS },
  );

  return {
    accessToken: jwt,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn,
    expiresAt,
    sessionToken: jwt, // Backwards compatibility for existing clients
    userId,
  };
}

// ── Request Handler ─────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;

    // Cheap bot screen — the app always sends this header. The /admin
    // dashboard is opened in a plain browser, so it is exempt.
    if (
      request.headers.get(CLIENT_HEADER) === null &&
      url.pathname !== '/admin' &&
      url.pathname !== '/admin/'
    ) {
      return err('client_required', 400, 'Missing X-Mahtem-Client header.');
    }

    try {
      // ── admin per-account detail (owner-only, dynamic path) ──────────
      const adminAccount = route.match(/^GET \/v1\/admin\/account\/([0-9a-fA-F]{8,64})$/);
      if (adminAccount) {
        const admin = await requireAdmin(request, env);
        if (!admin.ok) return err(admin.error, admin.status, admin.message);
        const detail = await buildAdminAccountDetail(env, adminAccount[1].toLowerCase());
        if (detail.notFound) return err('not_found', 404, 'No account matches this prefix.');
        if (detail.ambiguous) {
          return json(
            {
              error: 'ambiguous',
              message: 'Prefix matches several accounts.',
              ids: detail.ids,
            },
            409,
          );
        }
        return json(detail);
      }

      switch (route) {
        case 'GET /v1/health':
          return json({
            ok: true,
            service: 'mahtem-api',
            auth: 'OAuth 2.0 / JWT (HS256) + Zero-Knowledge',
            time: new Date().toISOString(),
          });

        // ── account creation ────────────────────────────────────────────
        case 'POST /v1/accounts': {
          const body = await readJson(request);
          const identifierHash = body?.identifierHash;
          const authKey = body?.authKey;
          if (!isHex64(identifierHash) || !isHex64(authKey)) {
            return err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.');
          }
          const key = `user:${identifierHash}`;
          if (await env.KV.get(key)) {
            return err('exists', 409, 'An account with this identifier already exists.');
          }
          const id = crypto.randomUUID();
          const record = {
            id,
            authHash: await hashAuthKey(authKey, id),
            createdAt: Date.now(),
          };
          await env.KV.put(key, JSON.stringify(record));
          return json({ userId: id }, 201);
        }

        case 'POST /v1/accounts/lookup': {
          const body = await readJson(request);
          const identifierHash = body?.identifierHash;
          if (!isHex64(identifierHash)) {
            return err('bad_input', 400, 'identifierHash must be a 64-hex digest.');
          }
          const raw = await env.KV.get(`user:${identifierHash}`);
          if (!raw) return json({ exists: false });
          let record;
          try {
            record = JSON.parse(raw);
          } catch (_) {
            return json({ exists: false });
          }
          return json({ exists: true, createdAt: record.createdAt ?? null });
        }

        // ── login / session creation ────────────────────────────────────
        case 'POST /v1/session':
        case 'POST /v1/auth/token': {
          const body = await readJson(request);
          const identifierHash = body?.identifierHash;
          const authKey = body?.authKey;
          if (!isHex64(identifierHash) || !isHex64(authKey)) {
            return err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.');
          }
          const raw = await env.KV.get(`user:${identifierHash}`);
          if (!raw) return err('no_account', 404, 'No account for this identifier.');
          let record;
          try {
            record = JSON.parse(raw);
          } catch (_) {
            return err('server', 500, 'Corrupt record.');
          }

          const authHash = await hashAuthKey(authKey, record.id);
          if (authHash !== record.authHash) {
            return err('bad_credentials', 401, 'Wrong identifier or password.');
          }

          const tokens = await issueSessionTokens(record.id, env);
          return json(tokens);
        }

        // ── refresh token rotation ──────────────────────────────────────
        case 'POST /v1/session/refresh':
        case 'POST /v1/auth/refresh': {
          const body = await readJson(request);
          const refreshToken = body?.refreshToken;
          if (!refreshToken || typeof refreshToken !== 'string') {
            return err('bad_input', 400, 'refreshToken string is required.');
          }

          const raw = await env.KV.get(`ref:${refreshToken}`);
          if (!raw) {
            return err('invalid_grant', 401, 'Refresh token is invalid, expired, or already used.');
          }

          let sessionData;
          try {
            sessionData = JSON.parse(raw);
          } catch (_) {
            return err('invalid_grant', 401, 'Invalid refresh token data.');
          }

          if (!sessionData.userId || (sessionData.exp || 0) * 1000 < Date.now()) {
            await env.KV.delete(`ref:${refreshToken}`);
            return err('invalid_grant', 401, 'Refresh token has expired.');
          }

          // Single-use token rotation: delete used refresh token
          await env.KV.delete(`ref:${refreshToken}`);

          // Issue brand new JWT and rotated refresh token
          const tokens = await issueSessionTokens(sessionData.userId, env);
          return json(tokens);
        }

        // ── session revocation ──────────────────────────────────────────
        case 'DELETE /v1/session':
        case 'POST /v1/auth/revoke': {
          const body = await readJson(request);
          const refreshToken = body?.refreshToken;
          if (refreshToken && typeof refreshToken === 'string') {
            await env.KV.delete(`ref:${refreshToken}`);
          }

          // Check if bearer was passed as legacy session
          const auth = request.headers.get('Authorization') || '';
          const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
          if (token && token.split('.').length !== 3) {
            await env.KV.delete(`sess:${token}`);
          }

          return json({ ok: true });
        }

        // ── check current session ───────────────────────────────────────
        case 'GET /v1/session':
        case 'GET /v1/auth/me': {
          const session = await requireSession(request, env);
          if (!session.ok) {
            return err(session.error, session.status, session.message);
          }
          return json({ userId: session.userId, exp: session.exp, ok: true });
        }

        // ── admin dashboard (owner-only, v1.15.0) ────────────────────
        case 'GET /admin':
        case 'GET /admin/':
          return new Response(adminDashboardHtml(), {
            status: 200,
            headers: {
              'content-type': 'text/html; charset=utf-8',
              'cache-control': 'no-store',
              ...CORS_HEADERS,
            },
          });

        // ── admin owner account: email + password (v1.16.0) ───────────
        case 'GET /v1/admin/auth/status': {
          const owner = await getOwner(env);
          return json({ hasAdmin: !!owner });
        }

        case 'POST /v1/admin/auth/setup': {
          // First run only — creates THE owner account, then signs in.
          if (await getOwner(env)) {
            return err(
              'exists',
              409,
              'An owner account already exists. Please sign in.',
            );
          }
          const body = await readJson(request);
          const email = normalizeEmail(body?.email);
          if (!isValidEmail(email)) {
            return err('bad_input', 400, 'Enter a valid email address.');
          }
          if (!isValidPassword(body?.password)) {
            return err(
              'weak_password',
              400,
              'Password must be at least 10 characters.',
            );
          }
          const salt = randomToken(16);
          const record = {
            email,
            hash: await hashPassword(
              body.password,
              salt,
              ADMIN_PBKDF2_ITERATIONS,
            ),
            salt,
            iter: ADMIN_PBKDF2_ITERATIONS,
            createdAt: Date.now(),
          };
          await env.KV.put(ADMIN_OWNER_KEY, JSON.stringify(record));
          const session = await createAdminSession(env, email);
          return json({ ok: true, ...session });
        }

        case 'POST /v1/admin/auth/login': {
          const body = await readJson(request);
          const email = normalizeEmail(body?.email);
          if (!isValidEmail(email) || typeof body?.password !== 'string') {
            return err('bad_input', 400, 'Enter your email and password.');
          }
          if (!(await checkLoginAllowed(env, email))) {
            return err(
              'rate_limited',
              429,
              'Too many attempts. Try again in about 15 minutes.',
            );
          }
          const owner = await getOwner(env);
          if (!owner) {
            return err(
              'no_admin',
              404,
              'No owner account exists yet. Create one first.',
            );
          }
          if (email !== owner.email) {
            await recordLoginFailure(env, email);
            return err('bad_credentials', 401, 'Wrong email or password.');
          }
          const candidate = await hashPassword(
            body.password,
            owner.salt,
            owner.iter || ADMIN_PBKDF2_ITERATIONS,
          );
          if (!timingSafeEqualHex(candidate, owner.hash)) {
            await recordLoginFailure(env, email);
            return err('bad_credentials', 401, 'Wrong email or password.');
          }
          await env.KV.delete(`adm_rl:${email}`);
          const session = await createAdminSession(env, owner.email);
          return json({ ok: true, ...session });
        }

        case 'GET /v1/admin/auth/me': {
          const s = await requireAdminSession(request, env);
          if (!s.ok) return err(s.error, s.status, s.message);
          const owner = await getOwner(env);
          return json({
            email: s.email,
            expiresAt: s.exp ? s.exp * 1000 : null,
            ownerCreatedAt: owner?.createdAt ?? null,
          });
        }

        case 'POST /v1/admin/auth/logout': {
          const s = await requireAdminSession(request, env);
          if (s.ok) await env.KV.delete(`${ADMIN_SESSION_PREFIX}${s.token}`);
          return json({ ok: true }); // idempotent — signing out is always fine
        }

        case 'POST /v1/admin/auth/change-password': {
          const s = await requireAdminSession(request, env);
          if (!s.ok) return err(s.error, s.status, s.message);
          const owner = await getOwner(env);
          if (!owner) {
            return err('no_admin', 404, 'No owner account exists.');
          }
          const body = await readJson(request);
          if (
            typeof body?.currentPassword !== 'string' ||
            typeof body?.newPassword !== 'string'
          ) {
            return err(
              'bad_input',
              400,
              'Current and new password are required.',
            );
          }
          const current = await hashPassword(
            body.currentPassword,
            owner.salt,
            owner.iter || ADMIN_PBKDF2_ITERATIONS,
          );
          if (!timingSafeEqualHex(current, owner.hash)) {
            return err('bad_credentials', 401, 'Current password is incorrect.');
          }
          if (!isValidPassword(body.newPassword)) {
            return err(
              'weak_password',
              400,
              'New password must be at least 10 characters.',
            );
          }
          const salt = randomToken(16);
          await env.KV.put(
            ADMIN_OWNER_KEY,
            JSON.stringify({
              ...owner,
              hash: await hashPassword(
                body.newPassword,
                salt,
                ADMIN_PBKDF2_ITERATIONS,
              ),
              salt,
              iter: ADMIN_PBKDF2_ITERATIONS,
              passwordChangedAt: Date.now(),
            }),
          );
          // Rotation: every existing session dies (lost phone, leaked
          // session), this device gets a fresh token in the response.
          for (const name of await listAllKeys(env, ADMIN_SESSION_PREFIX)) {
            await env.KV.delete(name);
          }
          const session = await createAdminSession(env, owner.email);
          return json({ ok: true, ...session });
        }

        case 'POST /v1/admin/auth/reset': {
          // Break-glass: the ADMIN_KEY secret removes a forgotten owner
          // account and all its sessions, restoring the first-run setup.
          const expected = env.ADMIN_KEY;
          const auth = request.headers.get('Authorization') || '';
          const token = auth.startsWith('Bearer ')
            ? auth.slice(7).trim()
            : '';
          if (
            typeof expected !== 'string' ||
            expected.length < 16 ||
            !token
          ) {
            return err('admin_required', 401, 'Admin key required.');
          }
          const [a, b] = await Promise.all([
            sha256Hex(token),
            sha256Hex(expected),
          ]);
          if (a !== b) {
            return err('admin_required', 401, 'Invalid admin key.');
          }
          await env.KV.delete(ADMIN_OWNER_KEY);
          for (const name of await listAllKeys(env, ADMIN_SESSION_PREFIX)) {
            await env.KV.delete(name);
          }
          return json({ ok: true });
        }

        case 'GET /v1/admin/overview': {
          const admin = await requireAdmin(request, env);
          if (!admin.ok) return err(admin.error, admin.status, admin.message);
          return json(await buildAdminOverview(env));
        }

        case 'PUT /v1/vault': {
          const session = await requireSession(request, env);
          if (!session.ok) {
            return err(session.error, session.status, session.message);
          }
          const body = await readJson(request);
          const blob = body?.blob;
          const revision = Number(body?.revision);
          if (!isBase64(blob) || !Number.isFinite(revision) || revision <= 0) {
            return err('bad_input', 400, 'blob must be base64 and revision a positive number.');
          }
          const key = `vault:${session.userId}`;
          const raw = await env.KV.get(key);
          let existing = null;
          if (raw) {
            try {
              existing = JSON.parse(raw);
            } catch (_) {
              existing = null;
            }
          }

          // Optimistic concurrency check
          if (
            existing &&
            body?.baseRevision !== undefined &&
            body?.baseRevision !== null
          ) {
            if (Number(existing.revision) > Number(body.baseRevision)) {
              return json(
                { error: 'conflict', revision: existing.revision, updatedAt: existing.updatedAt },
                409,
              );
            }
          }

          const updatedAt = Date.now();
          // v1.15.0 — analytics piggyback: merge bank-only events from the
          // upload into the stored list (newest first, hard cap, deduped).
          // The encrypted blob itself is never touched.
          const incoming = Array.isArray(body?.stats) ? body.stats : [];
          const stored = Array.isArray(existing?.stats) ? existing.stats : [];
          const seen = new Set(stored.map((e) => `${e.t}:${e.b}`));
          const merged = stored.slice();
          for (const rawEvent of incoming) {
            const ev = canonStatEvent(rawEvent);
            if (!ev) continue;
            const dedupe = `${ev.t}:${ev.b}`;
            if (seen.has(dedupe)) continue;
            seen.add(dedupe);
            merged.push(ev);
          }
          merged.sort((a, b) => b.t - a.t);
          const stats = merged.slice(0, MAX_STATS_EVENTS);

          await env.KV.put(
            key,
            JSON.stringify({ blob, revision, updatedAt, stats }),
            { expirationTtl: 365 * 24 * 3600 },
          );
          return json({ ok: true, revision, updatedAt });
        }

        case 'GET /v1/vault': {
          const session = await requireSession(request, env);
          if (!session.ok) {
            return err(session.error, session.status, session.message);
          }
          const raw = await env.KV.get(`vault:${session.userId}`);
          if (!raw) return err('empty', 404, 'No vault stored yet.');
          let vault;
          try {
            vault = JSON.parse(raw);
          } catch (_) {
            return err('server', 500, 'Corrupt vault.');
          }
          const since = url.searchParams.get('sinceRevision');
          if (since !== null && Number(since) === Number(vault.revision)) {
            return json({ notModified: true, revision: vault.revision });
          }
          return json(vault);
        }

        case 'DELETE /v1/vault': {
          const session = await requireSession(request, env);
          if (!session.ok) {
            return err(session.error, session.status, session.message);
          }
          await env.KV.delete(`vault:${session.userId}`);
          return json({ ok: true });
        }

        default:
          return err('not_found', 404, 'Unknown route.');
      }
    } catch (e) {
      return err('server', 500, 'Unexpected server error.');
    }
  },
};

// ── Admin Dashboard HTML (v1.15.0) ──────────────────────────────────────────
// Single self-contained page: no external assets, no frameworks. The owner
// enters the ADMIN_KEY once (kept in localStorage); every refresh pulls
// GET /v1/admin/overview and re-renders. Read-only by design.

function adminDashboardHtml() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Mahtem — Admin</title>
<style>
  :root {
    --bg: #0b1020; --panel: #121a30; --panel2: #0e1526; --line: #223052;
    --text: #e8eefc; --muted: #8fa0c2; --brand: #4f7cff; --brand2: #7aa2ff;
    --ok: #2fbf71; --bad: #ff5d5d; --amber: #ffb454;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: radial-gradient(1200px 600px at 80% -10%, #16224a 0%, var(--bg) 55%);
    color: var(--text); min-height: 100vh; padding: 28px 20px 60px;
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  }
  .wrap { max-width: 1080px; margin: 0 auto; }
  header { display: flex; align-items: center; gap: 14px; margin-bottom: 22px; flex-wrap: wrap; }
  .logo {
    width: 42px; height: 42px; border-radius: 12px; flex: none;
    background: linear-gradient(135deg, var(--brand), #9b5cff);
    display: flex; align-items: center; justify-content: center; font-weight: 800; font-size: 20px;
  }
  h1 { font-size: 20px; font-weight: 700; letter-spacing: .2px; }
  .sub { color: var(--muted); font-size: 13px; }
  .spacer { flex: 1; }
  .keybox { display: flex; gap: 8px; align-items: center; }
  input[type=password], input[type=text], input[type=email] {
    background: var(--panel2); border: 1px solid var(--line); color: var(--text);
    border-radius: 10px; padding: 9px 12px; font-size: 14px; width: 240px; outline: none;
  }
  input:focus { border-color: var(--brand); }
  #authbox input { width: 100%; }
  button {
    background: var(--brand); border: 0; color: #fff; font-weight: 600;
    border-radius: 10px; padding: 9px 16px; font-size: 14px; cursor: pointer;
  }
  button.ghost { background: transparent; border: 1px solid var(--line); color: var(--muted); }
  button.ghost:hover { color: var(--text); border-color: var(--brand); }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin-bottom: 18px; }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 14px 16px; }
  .card .k { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .6px; }
  .card .v { font-size: 26px; font-weight: 750; margin-top: 4px; }
  .card .d { color: var(--muted); font-size: 12px; margin-top: 2px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  @media (max-width: 860px) { .grid { grid-template-columns: 1fr; } }
  .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
  .panel h2 { font-size: 14px; font-weight: 700; margin-bottom: 12px; color: var(--brand2); letter-spacing: .3px; }
  .barrow { display: grid; grid-template-columns: 130px 1fr 84px; gap: 10px; align-items: center; margin: 7px 0; }
  .barrow .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text); font-size: 13px; }
  .barrow .track { background: var(--panel2); border-radius: 6px; height: 10px; overflow: hidden; }
  .barrow .fill { height: 100%; border-radius: 6px; background: linear-gradient(90deg, var(--brand), #9b5cff); }
  .barrow .num { text-align: right; color: var(--muted); font-size: 12.5px; font-variant-numeric: tabular-nums; }
  .chart { display: flex; align-items: flex-end; gap: 6px; height: 130px; padding-top: 6px; }
  .chart .col { flex: 1; display: flex; flex-direction: column; justify-content: flex-end; align-items: center; gap: 5px; height: 100%; }
  .chart .bar { width: 100%; max-width: 34px; border-radius: 5px 5px 2px 2px; background: linear-gradient(180deg, var(--brand2), var(--brand)); min-height: 2px; }
  .chart .lbl { font-size: 10px; color: var(--muted); transform: rotate(-45deg); white-space: nowrap; }
  .chart .val { font-size: 10.5px; color: var(--text); font-variant-numeric: tabular-nums; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; color: var(--muted); font-weight: 600; font-size: 11.5px; text-transform: uppercase; letter-spacing: .5px; padding: 7px 8px; border-bottom: 1px solid var(--line); }
  td { padding: 8px; border-bottom: 1px solid var(--panel2); font-variant-numeric: tabular-nums; }
  tr:hover td { background: var(--panel2); }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 7px; }
  .ok { background: var(--ok); } .bad { background: var(--bad); }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12px; color: var(--muted); }
  .feed { max-height: 320px; overflow-y: auto; }
  .feedrow { display: flex; align-items: center; gap: 10px; padding: 7px 4px; border-bottom: 1px solid var(--panel2); font-size: 13px; }
  .feedrow .t { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; flex: none; }
  .feedrow .u { margin-left: auto; }
  .msg { padding: 14px 16px; border-radius: 12px; margin: 10px 0; font-size: 14px; display: none; }
  .msg.err { background: rgba(255,93,93,.12); border: 1px solid rgba(255,93,93,.4); color: #ffb3b3; }
  .msg.info { background: rgba(79,124,255,.12); border: 1px solid rgba(79,124,255,.4); color: #c3d3ff; }
  footer { margin-top: 26px; color: var(--muted); font-size: 12px; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
  label.tog { display: inline-flex; gap: 7px; align-items: center; cursor: pointer; user-select: none; }
  .skel { color: var(--muted); padding: 30px 0; text-align: center; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">M</div>
    <div>
      <h1>Mahtem Admin</h1>
      <div class="sub">Cross-account scan analytics · read-only · zero-knowledge preserved</div>
    </div>
    <div class="spacer"></div>
    <div class="keybox" id="whoami" style="display:none">
      <span class="sub" id="who"></span>
      <button id="forget" class="ghost">Sign out</button>
    </div>
  </header>

  <div id="err" class="msg err"></div>
  <div id="info" class="msg info"></div>

  <div id="authbox" class="panel" style="max-width:430px;margin:30px auto 0;display:none">
    <h2 id="authTitle">Owner sign-in</h2>
    <div style="display:flex;flex-direction:column;gap:10px">
      <input id="email" type="email" placeholder="Email" autocomplete="username">
      <input id="pass" type="password" placeholder="Password" autocomplete="current-password">
      <input id="pass2" type="password" placeholder="Confirm password" autocomplete="new-password" style="display:none">
      <button id="authGo">Sign in</button>
    </div>
    <div class="sub" id="authNote" style="margin-top:10px"></div>
  </div>

  <div id="content" style="display:none">
    <div class="cards" id="cards"></div>

    <div class="grid">
      <div class="panel">
        <h2>Bank popularity</h2>
        <div id="banks"></div>
      </div>
      <div class="panel">
        <h2>Scans per day — last 14 days (UTC)</h2>
        <div class="chart" id="chart"></div>
      </div>
    </div>

    <div class="panel" style="margin-top:14px">
      <h2>Accounts</h2>
      <div style="overflow-x:auto">
        <table>
          <thead><tr>
            <th>Account</th><th>Created</th><th>Revision</th><th>Vault updated</th>
            <th>Scans</th><th>Last scan</th><th>Top bank</th>
          </tr></thead>
          <tbody id="accounts"></tbody>
        </table>
      </div>
    </div>

    <div class="panel" style="margin-top:14px">
      <h2>Recent scans — every account</h2>
      <div class="feed" id="feed"></div>
    </div>
  </div>

  <footer>
    <span id="gen"></span>
    <label class="tog"><input id="auto" type="checkbox" checked> auto-refresh 30s</label>
    <button id="refresh" class="ghost">Refresh now</button>
    <span>Bank-only metadata — receipt contents stay encrypted per account.</span>
  </footer>
</div>

<script>
(function () {
  'use strict';
  var TOK_STORE = 'mahtem_admin_tok';
  var EMAIL_STORE = 'mahtem_admin_email';
  var token = '';
  var timer = null;
  var needsSetup = false;

  var el = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fmt(n) { return (n == null ? 0 : n).toLocaleString('en-US'); }
  function dt(ms) {
    if (!ms) return '—';
    var d = new Date(ms);
    return d.toISOString().slice(0, 10) + ' ' + d.toISOString().slice(11, 16);
  }
  function ago(ms) {
    if (!ms) return 'never';
    var s = Math.max(0, (Date.now() - ms) / 1000);
    if (s < 60) return Math.floor(s) + 's ago';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    return Math.floor(s / 86400) + 'd ago';
  }
  function showErr(msg) { el('err').textContent = msg; el('err').style.display = 'block'; }
  function hideMsgs() { el('err').style.display = 'none'; el('info').style.display = 'none'; }

  function saveAuth(tok, em) {
    token = tok;
    try {
      localStorage.setItem(TOK_STORE, tok);
      localStorage.setItem(EMAIL_STORE, em || '');
    } catch (e) {}
  }
  function loadAuth() {
    try {
      return {
        token: localStorage.getItem(TOK_STORE) || '',
        email: localStorage.getItem(EMAIL_STORE) || '',
      };
    } catch (e) { return { token: '', email: '' }; }
  }
  function clearToken() {
    token = '';
    try { localStorage.removeItem(TOK_STORE); } catch (e) {}
  }
  function forgetAuth() {
    if (token) {
      fetch('/v1/admin/auth/logout', { method: 'POST', headers: authHeaders() })
        .catch(function () {});
    }
    clearToken();
    try { localStorage.removeItem(EMAIL_STORE); } catch (e) {}
    location.reload();
  }
  function authHeaders() {
    return { 'Authorization': 'Bearer ' + token, 'X-Mahtem-Client': 'mahtem-admin-dashboard' };
  }

  function fetchOverview() {
    hideMsgs();
    return fetch('/v1/admin/overview', { headers: authHeaders() }).then(function (r) {
      if (r.status === 401) {
        clearToken();
        throw new Error('Session expired — sign in again.');
      }
      if (r.status === 503) { throw new Error('Admin access is not configured on this deployment yet.'); }
      if (!r.ok) { throw new Error('Server error ' + r.status + '. Try again shortly.'); }
      return r.json();
    });
  }

  function postAuth(path, body) {
    return fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Mahtem-Client': 'mahtem-admin-dashboard' },
      body: JSON.stringify(body),
    }).then(function (r) {
      return r.json().then(function (j) { return { status: r.status, body: j }; });
    });
  }

  function afterAuth(res) {
    saveAuth(res.token, res.email);
    el('who').textContent = res.email || 'owner';
    el('whoami').style.display = 'flex';
    el('authbox').style.display = 'none';
    hideMsgs();
    refresh();
    schedule();
  }

  function showAuth(setup, prefillEmail) {
    needsSetup = setup;
    el('authbox').style.display = 'block';
    el('pass2').style.display = setup ? 'block' : 'none';
    el('authGo').textContent = setup ? 'Create owner account' : 'Sign in';
    el('authTitle').textContent = setup ? 'First run — create the owner account' : 'Owner sign-in';
    el('authNote').textContent = setup
      ? 'One owner account only (yours). The password is hashed with PBKDF2 on the server and never stored in plain text.'
      : 'Email + password sign-in. The session lasts 30 days on this device.';
    if (prefillEmail) el('email').value = prefillEmail;
  }

  function submitAuth() {
    var email = el('email').value.trim().toLowerCase();
    var pass = el('pass').value;
    if (!email || !pass) {
      showErr(needsSetup ? 'Enter an email and a password (at least 10 characters).' : 'Enter your email and password.');
      return;
    }
    if (needsSetup && pass !== el('pass2').value) {
      showErr('Passwords do not match.');
      return;
    }
    el('authGo').disabled = true;
    postAuth(needsSetup ? '/v1/admin/auth/setup' : '/v1/admin/auth/login', { email: email, password: pass })
      .then(function (res) {
        el('authGo').disabled = false;
        if (res.status === 200 && res.body && res.body.token) { afterAuth(res.body); return; }
        if (res.status === 404) {
          showAuth(true, email);
          showErr('No owner account yet — create one below.');
          return;
        }
        showErr((res.body && res.body.message) || 'Something went wrong. Try again.');
      })
      .catch(function () {
        el('authGo').disabled = false;
        showErr("Can't reach the Mahtem API. Check your connection.");
      });
  }

  function boot() {
    var stored = loadAuth();
    if (stored.token) {
      token = stored.token;
      if (stored.email) el('who').textContent = stored.email;
      el('whoami').style.display = 'flex';
      refresh();
      schedule();
      return;
    }
    fetch('/v1/admin/auth/status', { headers: { 'X-Mahtem-Client': 'mahtem-admin-dashboard' } })
      .then(function (r) { return r.json(); })
      .then(function (j) { showAuth(!j.hasAdmin, ''); })
      .catch(function () {
        showAuth(false, '');
        showErr("Can't reach the Mahtem API. Check your connection.");
      });
  }

  function render(d) {
    var t = d.totals || {};
    var cards = [
      ['Accounts', fmt(t.accounts), 'registered'],
      ['Cloud vaults', fmt(t.vaults), 'backing up now'],
      ['Total scans', fmt(t.scans), fmt(t.verified) + ' verified'],
      ['Scans today', fmt(t.scansToday), 'UTC day'],
      ['Scans 7 days', fmt(t.scans7d), 'rolling'],
      ['Active 7 days', fmt(t.scanningAccounts7d), 'accounts scanning'],
    ];
    el('cards').innerHTML = cards.map(function (c) {
      return '<div class="card"><div class="k">' + esc(c[0]) + '</div><div class="v">' +
        esc(c[1]) + '</div><div class="d">' + esc(c[2]) + '</div></div>';
    }).join('');

    var banks = d.banks || [];
    var maxB = banks.length ? banks[0].count : 1;
    el('banks').innerHTML = banks.length ? banks.map(function (b) {
      var pct = Math.max(2, Math.round(100 * b.count / maxB));
      var share = t.scans ? Math.round(100 * b.count / t.scans) : 0;
      return '<div class="barrow"><div class="name" title="' + esc(b.id) + '">' + esc(b.name || b.id) +
        '</div><div class="track"><div class="fill" style="width:' + pct + '%"></div></div>' +
        '<div class="num">' + fmt(b.count) + ' · ' + share + '%</div></div>';
    }).join('') : '<div class="skel">No scan analytics yet — data arrives with the next vault upload from the app (v1.15.0+).</div>';

    var days = (d.days || []).slice(-14);
    var maxD = 1;
    days.forEach(function (x) { if (x.count > maxD) maxD = x.count; });
    el('chart').innerHTML = days.map(function (x) {
      var h = Math.max(2, Math.round(100 * x.count / maxD));
      return '<div class="col" title="' + esc(x.day) + ': ' + x.count + ' scans">' +
        '<div class="val">' + (x.count || '') + '</div>' +
        '<div class="bar" style="height:' + h + '%"></div>' +
        '<div class="lbl">' + esc(x.day.slice(5)) + '</div></div>';
    }).join('');

    var accs = d.accounts || [];
    el('accounts').innerHTML = accs.length ? accs.map(function (a) {
      return '<tr><td class="mono">' + esc(a.id) + '…</td>' +
        '<td>' + esc(dt(a.createdAt).slice(0, 10)) + '</td>' +
        '<td>' + esc(fmt(a.revision)) + '</td>' +
        '<td>' + esc(ago(a.updatedAt)) + '</td>' +
        '<td><b>' + esc(fmt(a.scans)) + '</b></td>' +
        '<td>' + esc(ago(a.lastScanAt)) + '</td>' +
        '<td>' + esc(a.topBank || '—') + '</td></tr>';
    }).join('') : '<tr><td colspan="7" class="skel">No vaults stored yet.</td></tr>';

    var feed = d.recent || [];
    el('feed').innerHTML = feed.length ? feed.map(function (r) {
      return '<div class="feedrow"><span class="dot ' + (r.v ? 'ok' : 'bad') + '"></span>' +
        '<span class="t">' + esc(dt(r.t)) + '</span>' +
        '<span>' + esc(r.n || r.b) + '</span>' +
        '<span class="u mono">' + esc(r.u) + '…</span></div>';
    }).join('') : '<div class="skel">No scans reported yet.</div>';

    el('gen').textContent = 'Updated ' + new Date(d.generatedAt || Date.now()).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
    el('content').style.display = 'block';
  }

  function refresh() {
    return fetchOverview().then(render).catch(function (e) {
      el('content').style.display = 'none';
      showErr(e.message || String(e));
      if (!token) {
        el('whoami').style.display = 'none';
        boot();
      }
    });
  }

  function schedule() {
    if (timer) clearInterval(timer);
    timer = setInterval(function () {
      if (el('auto').checked && token) refresh();
    }, 30000);
  }

  el('authGo').addEventListener('click', submitAuth);
  el('pass').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { if (needsSetup) { el('pass2').focus(); } else { submitAuth(); } }
  });
  el('pass2').addEventListener('keydown', function (e) { if (e.key === 'Enter') submitAuth(); });
  el('email').addEventListener('keydown', function (e) { if (e.key === 'Enter') el('pass').focus(); });
  el('forget').addEventListener('click', forgetAuth);
  el('refresh').addEventListener('click', function () { if (token) refresh(); });

  boot();
})();
</script>
</body>
</html>`;
}
