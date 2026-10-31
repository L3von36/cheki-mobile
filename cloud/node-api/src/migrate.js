'use strict';

/**
 * One-time import of a user's data from the original Cloudflare Worker
 * (mahtem-api.mahtem.workers.dev).
 *
 * Runs only after the OLD worker proved the same credentials (we sign in on
 * the user's behalf with the very credentials the client just presented), so
 * this can never be used to pull someone else's data. Never throws —
 * migration must never break sign-in.
 *
 * Both systems share the exact same hashing scheme
 * (authHash = SHA-256("<userId>:<authKey>")), so accounts imported here
 * authenticate locally with zero re-registration.
 */

const crypto = require('node:crypto');
const db = require('./db');

const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const MAX_BLOB_CHARS = 4_000_000;

const isHex64 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
const isBase64ish = (s) => typeof s === 'string' && s.length > 16 && s.length <= MAX_BLOB_CHARS;

function hashAuthKey(authKey, userId) {
  return crypto.createHash('sha256').update(`${userId}:${authKey}`).digest('hex');
}

async function fetchJson(url, { method = 'GET', body, bearer, timeoutMs = 15_000 } = {}) {
  const headers = { 'X-Mahtem-Client': 'mahtem-android' };
  if (bearer) headers.Authorization = `Bearer ${bearer}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const resp = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
    redirect: 'follow',
  });
  const text = await resp.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }
  return { status: resp.status, json };
}

async function migrateImportFromWorker(baseUrl, identifierHash, authKey) {
  try {
    const base = baseUrl.replace(/\/+$/, '');

    // 1. Prove the credentials against the old service.
    const resp = await fetchJson(`${base}/v1/session`, {
      method: 'POST',
      body: { identifierHash, authKey },
    });
    if (resp.status !== 200 || !resp.json) return null;
    const data = resp.json;
    const userId = typeof data.userId === 'string' ? data.userId : '';
    if (!userId || userId.length > 64) return null;

    const now = Date.now();
    const authHash = hashAuthKey(authKey, userId);

    // 2. Account (same user id as on the old service → history stays continuous).
    await db.run(
      `${db.INSERT_IGNORE} \`accounts\` (\`identifier_hash\`, \`user_id\`, \`auth_hash\`, \`created_at\`) VALUES (?, ?, ?, ?)`,
      [identifierHash, userId, authHash, now],
    );

    // 3. Encrypted vault backup (ciphertext only — we cannot read it).
    const accessToken = typeof data.accessToken === 'string' ? data.accessToken : '';
    if (accessToken) {
      const vresp = await fetchJson(`${base}/v1/vault`, { bearer: accessToken });
      const v = vresp.status === 200 ? vresp.json : null;
      if (v && isBase64ish(v.blob) && Number.isFinite(Number(v.revision)) && Number(v.revision) > 0) {
        const updatedAt = Number.isFinite(Number(v.updatedAt)) ? Number(v.updatedAt) : now;
        await db.run(
          `${db.INSERT_IGNORE} \`vaults\` (\`user_id\`, \`blob\`, \`revision\`, \`updated_at\`) VALUES (?, ?, ?, ?)`,
          [userId, String(v.blob), Number(v.revision), updatedAt],
        );
      }

      // 4. Pro entitlement.
      const presp = await fetchJson(`${base}/v1/pro/status`, { bearer: accessToken });
      const p = presp.status === 200 ? presp.json : null;
      if (p && Number.isFinite(Number(p.expiresAt)) && Number(p.expiresAt) > 0) {
        await db.run(
          `${db.INSERT_IGNORE} \`pro_status\` (\`user_id\`, \`expires_at\`, \`updated_at\`) VALUES (?, ?, ?)`,
          [userId, Number(p.expiresAt), now],
        );
      }
    }

    // 5. Keep an in-flight refresh token working across the switch.
    if (typeof data.refreshToken === 'string' && /^[0-9a-f]{32,128}$/.test(data.refreshToken)) {
      await db.run(
        `${db.INSERT_IGNORE} \`refresh_tokens\` (\`token\`, \`user_id\`, \`exp\`, \`created_at\`) VALUES (?, ?, ?, ?)`,
        [data.refreshToken, userId, Math.floor(Date.now() / 1000) + REFRESH_TOKEN_TTL_SECONDS, now],
      );
    }

    return userId;
  } catch (_) {
    return null; // migration must never break sign-in
  }
}

module.exports = { migrateImportFromWorker };
