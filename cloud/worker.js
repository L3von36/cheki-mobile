/**
 * Mahtem Cloud API (v1.13.0) — zero-knowledge account + backup backend.
 *
 * Runs on Cloudflare Workers with a KV namespace binding (KV).
 * Deployed at https://mahtem-api.mahtem.workers.dev
 *
 * PRIVACY CONTRACT (what makes this "Mahtem-consistent"):
 *   * The client derives `authKey = PBKDF2(password, "mahtem-auth-v1")`
 *     on-device and sends ONLY that. The raw password never reaches us.
 *   * We store `identifierHash = SHA-256(identifier)` — never the raw
 *     email/phone, so a breach of this KV store leaks no user list.
 *   * The vault (verification history backup) arrives as an AES-GCM
 *     ciphertext whose key is derived on-device with a DIFFERENT salt
 *     ("mahtem-vault-v1") from the raw password. We cannot decrypt it —
 *     even knowing authKey (one-way PBKDF2 output, not the password).
 *
 * KV keys:
 *   user:{identifierHash} -> {id, authHash, createdAt}
 *   sess:{token}          -> {userId, exp}  (KV TTL = auto expiry)
 *   vault:{userId}        -> {blob, revision, updatedAt}
 *
 * Free-tier note: KV quotas (1k writes/day, 100k reads/day) act as the
 * de-facto rate limiter; per-IP throttling is pointless here and skipped.
 */

const CLIENT_HEADER = 'x-mahtem-client';
const SESSION_TTL_SECONDS = 90 * 24 * 3600; // 90 days
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

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** The client's authKey is already a 256-bit PBKDF2 output (not a human
 * password), so one fast server-side SHA-256 with a per-user pepper is
 * proportionate — no 100k-iteration KDF inside the 10ms free-plan CPU. */
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

async function requireSession(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return null;
  const raw = await env.KV.get(`sess:${token}`);
  if (!raw) return null;
  let session;
  try {
    session = JSON.parse(raw);
  } catch (_) {
    return null;
  }
  if (!session.userId || (session.exp || 0) * 1000 < Date.now()) return null;
  return { token, userId: session.userId };
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS_HEADERS });

    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;

    // Cheap bot screen — the app always sends this header.
    if (request.headers.get(CLIENT_HEADER) === null) {
      return err('client_required', 400, 'Missing X-Mahtem-Client header.');
    }

    try {
      switch (route) {
        case 'GET /v1/health':
          return json({ ok: true, service: 'mahtem-api', time: new Date().toISOString() });

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
          try { record = JSON.parse(raw); } catch (_) { return json({ exists: false }); }
          return json({ exists: true, createdAt: record.createdAt ?? null });
        }

        // ── sessions ────────────────────────────────────────────────────
        case 'POST /v1/session': {
          const body = await readJson(request);
          const identifierHash = body?.identifierHash;
          const authKey = body?.authKey;
          if (!isHex64(identifierHash) || !isHex64(authKey)) {
            return err('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.');
          }
          const raw = await env.KV.get(`user:${identifierHash}`);
          if (!raw) return err('no_account', 404, 'No account for this identifier.');
          let record;
          try { record = JSON.parse(raw); } catch (_) { return err('server', 500, 'Corrupt record.'); }

          const authHash = await hashAuthKey(authKey, record.id);
          if (authHash !== record.authHash) {
            return err('bad_credentials', 401, 'Wrong identifier or password.');
          }

          const token = randomToken();
          const exp = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
          await env.KV.put(`sess:${token}`, JSON.stringify({ userId: record.id, exp }), {
            expirationTtl: SESSION_TTL_SECONDS,
          });
          return json({ sessionToken: token, userId: record.id, expiresAt: exp * 1000 });
        }

        case 'GET /v1/session': {
          const session = await requireSession(request, env);
          if (!session) return err('unauthorized', 401, 'Session missing or expired.');
          return json({ userId: session.userId, ok: true });
        }

        case 'DELETE /v1/session': {
          const session = await requireSession(request, env);
          if (session) await env.KV.delete(`sess:${session.token}`);
          return json({ ok: true });
        }

        // ── vault (encrypted history backup) ────────────────────────────
        case 'PUT /v1/vault': {
          const session = await requireSession(request, env);
          if (!session) return err('unauthorized', 401, 'Session missing or expired.');
          const body = await readJson(request);
          const blob = body?.blob;
          const revision = Number(body?.revision);
          if (!isBase64(blob) || !Number.isFinite(revision) || revision <= 0) {
            return err('bad_input', 400, 'blob must be base64 and revision a positive number.');
          }
          const key = `vault:${session.userId}`;
          const raw = await env.KV.get(key);
          // Optimistic concurrency: when the client sends baseRevision it
          // declares "I built this upload on top of that revision" — a
          // newer stored revision yields 409 so the client can re-download,
          // merge and retry. WITHOUT baseRevision the write is a blind
          // overwrite (first upload, or the client chose to clobber).
          if (raw && body?.baseRevision !== undefined && body?.baseRevision !== null) {
            let existing;
            try { existing = JSON.parse(raw); } catch (_) { existing = null; }
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
            { expirationTtl: 365 * 24 * 3600 }, // keep backing up or it fades after a year
          );
          return json({ ok: true, revision, updatedAt });
        }

        case 'GET /v1/vault': {
          const session = await requireSession(request, env);
          if (!session) return err('unauthorized', 401, 'Session missing or expired.');
          const raw = await env.KV.get(`vault:${session.userId}`);
          if (!raw) return err('empty', 404, 'No vault stored yet.');
          let vault;
          try { vault = JSON.parse(raw); } catch (_) { return err('server', 500, 'Corrupt vault.'); }
          return json(vault);
        }

        case 'DELETE /v1/vault': {
          const session = await requireSession(request, env);
          if (!session) return err('unauthorized', 401, 'Session missing or expired.');
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
