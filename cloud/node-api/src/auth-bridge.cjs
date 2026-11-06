'use strict';

/**
 * Mahtem Cloud API — CommonJS bridge into the BetterAuth layer (auth.mjs).
 *
 * The rest of the API is plain CJS Express; Better Auth ships as ESM only,
 * so this module owns the dynamic import and exposes the three things
 * app.js needs:
 *
 *   handle(req, res, next)      mount point for /api/auth/* (lazy init)
 *   sessionUserId(req)          resolve a BetterAuth bearer session onto
 *                               the legacy `accounts.user_id` (linking or
 *                               provisioning the row on first sight)
 *   getAuth()                   the BetterAuth instance for server-side
 *                               auth.api.* calls (legacy migration, probes)
 *
 * Identity mapping: a phone-number account signs in to Better Auth as
 * `<intl>@phone.mahtem.et` (Better Auth requires an email); emails map
 * 1:1. The `accounts` row keeps the READABLE identifier exactly as before,
 * so the owner's phpMyAdmin views don't change.
 */

const crypto = require('node:crypto');
const db = require('./db');
const config = require('./config');

let authPromise = null;
let nodeHandler = null;

function getAuth() {
  if (!authPromise) {
    authPromise = import('./auth.mjs').then((m) => m.getAuth());
  }
  return authPromise;
}

/** Express mount point: lazily boots BetterAuth, then delegates to its
 * node handler. The body parser must run AFTER this (Better Auth consumes
 * the raw stream), which app.js guarantees by mounting it first. */
async function handle(req, res, next) {
  try {
    const auth = await getAuth();
    if (!nodeHandler) {
      const { toNodeHandler } = await import('better-auth/node');
      nodeHandler = toNodeHandler(auth);
    }
    await Promise.resolve(nodeHandler(req, res, next)).catch((e) => {
      console.error('[mahtem-api] better-auth request failed:', e && (e.stack || e.message || e));
      if (!res.headersSent) {
        res.status(500).json({ error: 'server', message: 'Auth request failed.' });
      }
    });
  } catch (e) {
    console.error('[mahtem-api] better-auth mount failed:', e && (e.stack || e.message || e));
    if (!res.headersSent) {
      res.status(500).json({ error: 'server', message: 'Auth service unavailable.' });
    }
  }
}

/** Better Auth user row → the legacy identifier it represents. */
function identifierFromBaEmail(email) {
  const value = String(email || '').trim().toLowerCase();
  const at = value.lastIndexOf('@');
  if (at <= 0) return { value: value || 'unknown', type: 'email' };
  const local = value.slice(0, at);
  if (value.endsWith('@phone.mahtem.et') && /^[0-9]+$/.test(local)) {
    return { value: local, type: 'phone' };
  }
  return { value, type: 'email' };
}

const K_LEGACY_HASH = crypto.createHash('sha256').update('better-auth-managed').digest('hex');

/**
 * Resolves the BetterAuth session carried by [req] (Authorization bearer
 * or cookie) to a legacy accounts row, linking/provisioning as needed.
 * Returns { userId, exp, email, name } or null.
 */
async function sessionUserId(req) {
  const auth = await getAuth();
  const { fromNodeHeaders } = await import('better-auth/node');

  let session = await auth.api.getSession({ headers: fromNodeHeaders(req.headers) });
  if ((!session || !session.user) && req.headers.authorization) {
    // The bearer plugin translates Authorization headers inside its own
    // route stack; programmatic getSession may only see cookies. Feed it
    // the token as the session cookie as well — same secret, same value.
    const token = String(req.headers.authorization)
      .replace(/^Bearer\s+/i, '')
      .trim();
    if (token && token.split('.').length !== 3) {
      const headers = new Headers(fromNodeHeaders(req.headers));
      headers.set('cookie', `better-auth.session_token=${token}`);
      session = await auth.api.getSession({ headers });
    }
  }
  if (!session || !session.user) return null;

  const user = session.user;
  await db.ensureReady();

  // 1. Already linked.
  let rows = await db.query(
    'SELECT `user_id` FROM `accounts` WHERE `better_auth_user_id` = ?',
    [user.id],
  );

  // 2. First sight of this BetterAuth user: link by readable identifier.
  if (!rows.length) {
    const ident = identifierFromBaEmail(user.email);
    rows = await db.query(
      'SELECT `user_id` FROM `accounts` WHERE `identifier` = ? AND `identifier_type` = ?',
      [ident.value, ident.type],
    );
    if (rows.length) {
      await db.run(
        'UPDATE `accounts` SET `better_auth_user_id` = ? WHERE `user_id` = ?',
        [user.id, String(rows[0].user_id)],
      );
    }
  }

  // 3. Brand-new identity (fresh sign-up through BetterAuth): provision.
  if (!rows.length) {
    const ident = identifierFromBaEmail(user.email);
    const userId = crypto.randomUUID();
    const now = Date.now();
    const nowDt = new Date(now).toISOString().slice(0, 19).replace('T', ' ');
    const identifierHash = crypto
      .createHash('sha256')
      .update(`ba:${user.id}`)
      .digest('hex');
    await db.run(
      'INSERT INTO `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `identifier`, `identifier_type`, `display_name`, `status`, `sign_in_count`, `created_at`, `created_dt`, `better_auth_user_id`) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
      [
        identifierHash,
        userId,
        K_LEGACY_HASH,
        ident.value,
        ident.type,
        String(user.name || '').trim().slice(0, 64) || null,
        'active',
        now,
        nowDt,
        user.id,
      ],
    );
    rows = [{ user_id: userId }];
  }

  let exp = null;
  const expiresAt = session.session && session.session.expiresAt;
  if (expiresAt) {
    const ms = Date.parse(expiresAt);
    if (Number.isFinite(ms)) exp = Math.floor(ms / 1000);
  }
  return {
    userId: String(rows[0].user_id),
    exp,
    email: user.email || null,
    name: user.name || null,
    betterAuthUserId: user.id,
  };
}

/** True when the BetterAuth layer has a GitHub provider configured. */
async function githubEnabled() {
  const auth = await getAuth();
  const github = auth.options && auth.options.socialProviders && auth.options.socialProviders.github;
  return Boolean(github && github.clientId && github.clientSecret);
}

module.exports = { getAuth, handle, sessionUserId, githubEnabled, identifierFromBaEmail, config };
