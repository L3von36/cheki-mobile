#!/usr/bin/env node
/**
 * Mahtem Cloud API — smoke/behaviour test suite (HTTP level, zero deps).
 *
 * Works against ANY deployment of the API:
 *
 *   local (SQLite + PHP built-in server):
 *     php -S 127.0.0.1:8088 dev-router.php      # from cloud/plesk/
 *     MAHTEM_CONFIG_FILE=test/config.local.php  # passed to php via env
 *     node test_api.mjs http://127.0.0.1:8088
 *
 *   production:
 *     node test_api.mjs https://mahtem.com.et/api
 *
 * Mirrors the guarantees of cloud/test_worker.mjs plus the exact request /
 * response contract the Flutter client (lib/core/cloud/cloud_api.dart)
 * depends on. Exits non-zero on the first failure.
 */

const BASE = (process.argv[2] || 'http://127.0.0.1:8088').replace(/\/+$/, '');
const H = { 'X-Mahtem-Client': 'mahtem-android', 'Content-Type': 'application/json' };

let passed = 0;
const failures = [];

function ok(cond, label) {
  if (cond) { passed++; console.log(`  ✔ ${label}`); }
  else { failures.push(label); console.error(`  ✘ FAIL: ${label}`); }
}

async function call(method, path, { headers = {}, body, bearer } = {}) {
  const h = { ...H, ...headers };
  if (bearer) h['Authorization'] = `Bearer ${bearer}`;
  const resp = await fetch(`${BASE}${path}`, {
    method,
    headers: h,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await resp.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON */ }
  return { status: resp.status, json, text };
}

const hex = (n) => [...crypto.getRandomValues(new Uint8Array(n))].map(b => b.toString(16).padStart(2, '0')).join('');
const H64 = () => hex(32);

async function run() {
  console.log(`Testing Mahtem API at ${BASE}\n`);

  // ── bot screen & routing ──────────────────────────────────────────────
  console.log('[bot screen / routing]');
  {
    const noHeader = await fetch(`${BASE}/v1/health`);
    ok(noHeader.status === 400, 'missing X-Mahtem-Client → 400 client_required');
    const j = await noHeader.json().catch(() => null);
    ok(j?.error === 'client_required', 'error code = client_required');

    const nf = await call('GET', '/v1/nope');
    ok(nf.status === 404 && nf.json?.error === 'not_found', 'unknown route → 404 not_found');
  }

  // ── health ────────────────────────────────────────────────────────────
  console.log('[health]');
  {
    const r = await call('GET', '/v1/health');
    ok(r.status === 200 && r.json?.ok === true, 'GET /v1/health → 200 ok:true');
    ok(r.json?.service === 'mahtem-api', 'health.service = mahtem-api');
    ok(r.json?.db === true, 'health.db = true (database reachable)');
  }

  // ── accounts ──────────────────────────────────────────────────────────
  console.log('[accounts]');
  const identifierHash = H64();
  const authKey = H64();
  let userId = '';
  {
    const bad = await call('POST', '/v1/accounts', { body: { identifierHash: 'xyz', authKey } });
    ok(bad.status === 400 && bad.json?.error === 'bad_input', 'invalid hex → 400 bad_input');

    const created = await call('POST', '/v1/accounts', { body: { identifierHash, authKey } });
    ok(created.status === 201, 'create account → 201');
    userId = created.json?.userId || '';
    ok(/^[0-9a-f-]{36}$/.test(userId), `userId is a UUID (${userId})`);

    const dup = await call('POST', '/v1/accounts', { body: { identifierHash, authKey } });
    ok(dup.status === 409 && dup.json?.error === 'exists', 'duplicate account → 409 exists');

    const lookup = await call('POST', '/v1/accounts/lookup', { body: { identifierHash } });
    ok(lookup.status === 200 && lookup.json?.exists === true, 'lookup existing → exists:true');
    ok(typeof lookup.json?.createdAt === 'number', 'lookup returns createdAt');

    const lookup2 = await call('POST', '/v1/accounts/lookup', { body: { identifierHash: H64() } });
    ok(lookup2.status === 200 && lookup2.json?.exists === false, 'lookup unknown → exists:false');
  }

  // ── sessions (OAuth 2.1 / JWT) ────────────────────────────────────────
  console.log('[sessions]');
  let accessToken = '', refreshToken = '';
  {
    const wrong = await call('POST', '/v1/session', { body: { identifierHash, authKey: H64() } });
    ok(wrong.status === 401 && wrong.json?.error === 'bad_credentials', 'wrong password → 401 bad_credentials');

    const unknown = await call('POST', '/v1/session', { body: { identifierHash: H64(), authKey } });
    ok(unknown.status === 404 && unknown.json?.error === 'no_account', 'unknown identifier → 404 no_account');

    const login = await call('POST', '/v1/session', { body: { identifierHash, authKey } });
    ok(login.status === 200, 'sign in → 200');
    accessToken = login.json?.accessToken || '';
    refreshToken = login.json?.refreshToken || '';
    ok(accessToken.split('.').length === 3, 'accessToken is a 3-part JWT');
    ok(/^[0-9a-f]{64}$/.test(refreshToken), 'refreshToken is 64-hex');
    ok(login.json?.expiresIn === 900, 'expiresIn = 900 (15 min)');
    ok(login.json?.sessionToken === accessToken, 'sessionToken (legacy field) mirrors accessToken');
    ok(login.json?.userId === userId, 'userId matches created account');

    const check = await call('GET', '/v1/session', { bearer: accessToken });
    ok(check.status === 200 && check.json?.ok === true && check.json?.userId === userId,
      'GET /v1/session with Bearer → ok:true, same userId');

    const badToken = await call('GET', '/v1/session', { bearer: 'not.a.jwt' });
    ok(badToken.status === 401, 'GET /v1/session with junk JWT → 401');
    const tampered = await call('GET', '/v1/session', {
      bearer: accessToken.replace(/(.{2})$/, s => (s === 'aa' ? 'bb' : 'aa')),
    });
    ok(tampered.status === 401, 'tampered JWT signature → 401');

    const missing = await call('GET', '/v1/session');
    ok(missing.status === 401 && missing.json?.error === 'missing_token', 'no Bearer → 401 missing_token');
  }

  // ── refresh rotation ──────────────────────────────────────────────────
  console.log('[refresh rotation]');
  {
    const r1 = await call('POST', '/v1/session/refresh', { body: { refreshToken: refreshToken } });
    ok(r1.status === 200, 'refresh → 200 new tokens');
    ok(r1.json?.refreshToken && r1.json?.refreshToken !== refreshToken, 'refresh token rotated');

    const reuse = await call('POST', '/v1/session/refresh', { body: { refreshToken: refreshToken } });
    ok(reuse.status === 401 && reuse.json?.error === 'invalid_grant',
      'reusing consumed refresh token → 401 invalid_grant');

    const r2 = await call('POST', '/v1/session/refresh', { body: { refreshToken: r1.json?.refreshToken } });
    ok(r2.status === 200, 'second rotation with newest token → 200');
    accessToken = r2.json?.accessToken || accessToken;
    refreshToken = r2.json?.refreshToken || refreshToken;

    const noStr = await call('POST', '/v1/session/refresh', { body: { refreshToken: '' } });
    ok(noStr.status === 400 && noStr.json?.error === 'bad_input', 'empty refresh token → 400 bad_input');
    const shortRefresh = await call('POST', '/v1/session/refresh', { body: { refreshToken: 'nope' } });
    ok(shortRefresh.status === 401 && shortRefresh.json?.error === 'invalid_grant',
      'unknown short refresh token → 401 invalid_grant (Worker-identical)');
  }

  // ── vault ─────────────────────────────────────────────────────────────
  console.log('[vault]');
  const blobA = Buffer.from(`vault-blob-A-${hex(8)}`).toString('base64');
  const blobB = Buffer.from(`vault-blob-B-${hex(8)}`).toString('base64');
  {
    const empty = await call('GET', '/v1/vault', { bearer: accessToken });
    ok(empty.status === 404 && empty.json?.error === 'empty', 'empty vault → 404 empty');

    const bad = await call('PUT', '/v1/vault', { bearer: accessToken, body: { blob: 'short', revision: 1 } });
    ok(bad.status === 400 && bad.json?.error === 'bad_input', 'tiny blob → 400 bad_input');

    const badRev = await call('PUT', '/v1/vault', { bearer: accessToken, body: { blob: blobA, revision: 0 } });
    ok(badRev.status === 400, 'revision 0 → 400 bad_input');

    const put1 = await call('PUT', '/v1/vault', { bearer: accessToken, body: { blob: blobA, revision: 1 } });
    ok(put1.status === 200 && put1.json?.ok === true && put1.json?.revision === 1, 'PUT revision 1 → ok');

    const get1 = await call('GET', '/v1/vault', { bearer: accessToken });
    ok(get1.status === 200 && get1.json?.blob === blobA && get1.json?.revision === 1,
      'GET vault → blob A, revision 1');
    ok(typeof get1.json?.updatedAt === 'number', 'GET vault returns updatedAt (ms)');

    const nm = await call('GET', '/v1/vault?sinceRevision=1', { bearer: accessToken });
    ok(nm.status === 200 && nm.json?.notModified === true && nm.json?.revision === 1,
      'GET ?sinceRevision=same → notModified:true');

    const stale = await call('PUT', '/v1/vault', { bearer: accessToken, body: { blob: blobB, revision: 5, baseRevision: 0 } });
    ok(stale.status === 409 && stale.json?.error === 'conflict' && stale.json?.revision === 1,
      'stale baseRevision → 409 conflict with serverRevision 1');

    const put2 = await call('PUT', '/v1/vault', { bearer: accessToken, body: { blob: blobB, revision: 2, baseRevision: 1 } });
    ok(put2.status === 200 && put2.json?.revision === 2, 'PUT revision 2 with baseRevision 1 → ok');

    const get2 = await call('GET', '/v1/vault', { bearer: accessToken });
    ok(get2.json?.blob === blobB && get2.json?.revision === 2, 'GET vault → blob B, revision 2');
  }

  // ── Pro receipt ledger ────────────────────────────────────────────────
  console.log('[pro claims]');
  let receiptHash = '';
  {
    const bad = await call('POST', '/v1/pro/claim', {
      bearer: accessToken, body: { receiptHash: H64(), amountEtb: 299, planDays: 31 },
    });
    ok(bad.status === 400 && bad.json?.error === 'bad_input', 'claim 299 ETB → 400 bad_input');

    receiptHash = H64();
    const claim = await call('POST', '/v1/pro/claim', {
      bearer: accessToken, body: { receiptHash, amountEtb: 300, planDays: 31 },
    });
    ok(claim.status === 200 && claim.json?.alreadyClaimed === false, 'first claim → alreadyClaimed:false');
    const exp1 = claim.json?.expiresAt;
    ok(typeof exp1 === 'number' && Math.abs(exp1 - Date.now() - 31 * 86400000) < 60000,
      'expiresAt ≈ now + 31 days');

    const again = await call('POST', '/v1/pro/claim', {
      bearer: accessToken, body: { receiptHash, amountEtb: 300, planDays: 31 },
    });
    ok(again.status === 200 && again.json?.alreadyClaimed === true && again.json?.expiresAt === exp1,
      'same account re-claim → alreadyClaimed:true, same expiresAt');

    const status = await call('GET', '/v1/pro/status', { bearer: accessToken });
    ok(status.status === 200 && status.json?.entitled === true && status.json?.expiresAt === exp1,
      'pro status → entitled:true with matching expiry');
  }

  // ── second account: one receipt, one account ─────────────────────────
  console.log('[receipt binding across accounts]');
  {
    const h2 = H64(), k2 = H64();
    await call('POST', '/v1/accounts', { body: { identifierHash: h2, authKey: k2 } });
    const login2 = await call('POST', '/v1/session', { body: { identifierHash: h2, authKey: k2 } });
    const token2 = login2.json?.accessToken;

    const vault2 = await call('GET', '/v1/vault', { bearer: token2 });
    ok(vault2.status === 404 && vault2.json?.error === 'empty', 'second account has its own (empty) vault');

    const used = await call('POST', '/v1/pro/claim', {
      bearer: token2, body: { receiptHash: receiptHash, amountEtb: 300, planDays: 31 },
    });
    ok(used.status === 409 && used.json?.error === 'receipt_used',
      'second account claiming same receipt → 409 receipt_used');

    const status2 = await call('GET', '/v1/pro/status', { bearer: token2 });
    ok(status2.json?.entitled === false, 'second account not entitled');
  }

  // ── relay guard rails (no live bank call) ─────────────────────────────
  console.log('[relay guard rails]');
  {
    const badBank = await call('POST', '/v1/relay', { body: { bank: 'cbe', url: 'https://transactioninfo.ethiotelecom.et/receipt/x' } });
    ok(badBank.status === 400 && badBank.json?.error === 'bad_bank', 'non-allowlisted bank → 400 bad_bank');

    const badHost = await call('POST', '/v1/relay', { body: { bank: 'telebirr', url: 'https://evil.example.com/x' } });
    ok(badHost.status === 400 && badHost.json?.error === 'bad_host', 'non-allowlisted host → 400 bad_host');

    const badUrl = await call('POST', '/v1/relay', { body: { bank: 'telebirr', url: 'not-a-url' } });
    ok(badUrl.status === 400 && badUrl.json?.error === 'bad_url', 'malformed url → 400 bad_url');

    const httpUrl = await call('POST', '/v1/relay', { body: { bank: 'telebirr', url: 'http://transactioninfo.ethiotelecom.et/x' } });
    ok(httpUrl.status === 400 && httpUrl.json?.error === 'bad_url', 'http:// (not https) → 400 bad_url');
  }

  // ── cleanup endpoints ─────────────────────────────────────────────────
  console.log('[delete + revoke]');
  {
    const del = await call('DELETE', '/v1/vault', { bearer: accessToken });
    ok(del.status === 200 && del.json?.ok === true, 'DELETE vault → ok');
    const gone = await call('GET', '/v1/vault', { bearer: accessToken });
    ok(gone.status === 404 && gone.json?.error === 'empty', 'vault now empty');

    const revoke = await call('POST', '/v1/auth/revoke', { body: { refreshToken } });
    ok(revoke.status === 200 && revoke.json?.ok === true, 'revoke refresh token → ok');
    const afterRevoke = await call('POST', '/v1/session/refresh', { body: { refreshToken } });
    ok(afterRevoke.status === 401, 'refresh after revoke → 401');
  }

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) {
    console.error('\nFailures:');
    failures.forEach((f) => console.error('  - ' + f));
    process.exit(1);
  }
}

run().catch((e) => {
  console.error('Suite crashed:', e);
  process.exit(1);
});
