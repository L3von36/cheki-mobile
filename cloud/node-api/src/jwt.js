'use strict';

/**
 * JWT engine (HS256) — byte-compatible with cloud/worker.js:
 *
 *   header  = base64url({"alg":"HS256","typ":"JWT"})
 *   payload = base64url({sub, iss:'mahtem-api', type:'access', iat, exp, jti})
 *   sig     = base64url(HMAC-SHA256(secret, header + '.' + payload))
 *
 * 15-minute access tokens, verified statelessly (zero database reads).
 */

const crypto = require('node:crypto');

const ACCESS_TOKEN_TTL_SECONDS = 15 * 60; // 15 minutes

function b64url(value) {
  return Buffer.from(value).toString('base64url');
}

function signAccessToken(userId, secret) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ACCESS_TOKEN_TTL_SECONDS;
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64url(
    JSON.stringify({
      sub: userId,
      iss: 'mahtem-api',
      type: 'access',
      iat: now,
      exp,
      jti: crypto.randomUUID(),
    }),
  );
  const signature = crypto
    .createHmac('sha256', secret)
    .update(`${header}.${payload}`)
    .digest('base64url');
  return {
    jwt: `${header}.${payload}.${signature}`,
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    expiresAt: exp * 1000,
  };
}

/**
 * Strict verification: base64url charset is validated before decoding so a
 * tampered signature can never sneak through lenient base64 padding rules.
 */
function verifyAccessToken(token, secret) {
  if (typeof token !== 'string') return { ok: false, error: 'invalid' };
  const parts = token.split('.');
  if (parts.length !== 3) return { ok: false, error: 'invalid' };
  const [h64, p64, s64] = parts;

  try {
    if (!/^[A-Za-z0-9_-]+$/.test(s64) || !/^[A-Za-z0-9_-]*$/.test(p64)) {
      return { ok: false, error: 'malformed' };
    }
    const expected = crypto
      .createHmac('sha256', secret)
      .update(`${h64}.${p64}`)
      .digest();
    const signature = Buffer.from(s64, 'base64url');
    if (
      signature.length !== expected.length ||
      !crypto.timingSafeEqual(signature, expected)
    ) {
      return { ok: false, error: 'invalid_signature' };
    }

    const payload = JSON.parse(Buffer.from(p64, 'base64url').toString('utf8'));
    if (!payload || typeof payload !== 'object') {
      return { ok: false, error: 'malformed' };
    }
    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.exp === 'number' && payload.exp < now) {
      return { ok: false, error: 'expired', payload };
    }
    return { ok: true, payload };
  } catch (_) {
    return { ok: false, error: 'malformed' };
  }
}

module.exports = { ACCESS_TOKEN_TTL_SECONDS, signAccessToken, verifyAccessToken };
