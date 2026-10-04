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
 */

const CLIENT_HEADER = 'x-mahtem-client';
const ACCESS_TOKEN_TTL_SECONDS = 15 * 60; // 15 minutes
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600; // 30 days
const LEGACY_SESSION_TTL_SECONDS = 90 * 24 * 3600; // 90 days

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

    // Cheap bot screen — the app always sends this header.
    if (request.headers.get(CLIENT_HEADER) === null) {
      return err('client_required', 400, 'Missing X-Mahtem-Client header.');
    }

    try {
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

        // ── vault (encrypted history backup) ────────────────────────────
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

          // Optimistic concurrency check
          if (raw && body?.baseRevision !== undefined && body?.baseRevision !== null) {
            let existing;
            try {
              existing = JSON.parse(raw);
            } catch (_) {
              existing = null;
            }
            if (existing && Number(existing.revision) > Number(body.baseRevision)) {
              return json(
                { error: 'conflict', revision: existing.revision, updatedAt: existing.updatedAt },
                409,
              );
            }
          }

          const updatedAt = Date.now();
          await env.KV.put(
            key,
            JSON.stringify({ blob, revision, updatedAt }),
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
