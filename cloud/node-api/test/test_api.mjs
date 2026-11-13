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

  // ── verified receipt ledger ───────────────────────────────────────────
  console.log('[receipts]');
  {
    const anon = await call('POST', '/v1/receipts', {
      body: { entryId: 'v1', bankId: 'cbe', reference: 'FT123', status: 'verified' },
    });
    ok(anon.status === 401, 'POST /v1/receipts without bearer → 401');

    const badBank = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: { entryId: 'v1', reference: 'FT123', status: 'verified' },
    });
    ok(badBank.status === 400 && badBank.json?.error === 'bad_input', 'missing bankId → 400 bad_input');

    const badStatus = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: { entryId: 'v1', bankId: 'cbe', reference: 'FT123', status: 'maybe' },
    });
    ok(badStatus.status === 400 && badStatus.json?.error === 'bad_input', 'bad status → 400 bad_input');

    const first = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: {
        entryId: 'v1', bankId: 'cbe', bankName: 'Commercial Bank of Ethiopia',
        reference: 'FT2508ABC', rawPayload: 'https://tx.cbeet.com/r/FT2508ABC',
        senderName: 'ABEBE', receiverName: 'GROCERY', amount: 1250.5,
        currency: 'ETB', receiptDate: '2026-10-31 09:14', status: 'verified',
        verifiedAt: 1700000000000,
      },
    });
    ok(first.status === 201 && first.json?.ok === true && first.json?.duplicate === false, 'record receipt → 201, not duplicate');

    const retry = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: {
        entryId: 'v1', bankId: 'cbe', bankName: 'Commercial Bank of Ethiopia',
        reference: 'FT2508ABC', status: 'verified', verifiedAt: 1700000000000,
        reason: 'rent',
      },
    });
    ok(retry.status === 200 && retry.json?.duplicate === true, 'same entryId retry → duplicate:true (idempotent)');

    const failed = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: {
        entryId: 'v2', bankId: 'telebirr', bankName: 'Telebirr',
        reference: 'WG2O9KZ1', status: 'failed', message: 'Receipt not found',
        verifiedAt: 1700000001000,
      },
    });
    ok(failed.status === 201 && failed.json?.ok === true, 'failed check also recorded → 201');

    const list = await call('GET', '/v1/receipts', { bearer: accessToken });
    ok(list.status === 200 && list.json?.count === 2, 'GET /v1/receipts → 2 rows');
    const rows = list.json?.receipts || [];
    ok(rows[0]?.entryId === 'v2' && rows[0]?.status === 'failed', 'newest first (v2 failed on top)');
    ok(rows[1]?.bankId === 'cbe' && rows[1]?.senderName === 'ABEBE' && rows[1]?.amount === 1250.5,
      'camelCase mapping + amount as number');
    ok(rows[1]?.rawPayload === 'https://tx.cbeet.com/r/FT2508ABC', 'raw payload stored');
    ok(rows[1]?.reason === 'rent', 'reason note moved onto the duplicate retry');

    const limited = await call('GET', '/v1/receipts?limit=1', { bearer: accessToken });
    ok(limited.status === 200 && limited.json?.count === 1, 'limit=1 → 1 row');

    const longRef = 'X'.repeat(400);
    const clipped = await call('POST', '/v1/receipts', {
      bearer: accessToken,
      body: { entryId: 'v3', bankId: 'boa', reference: longRef, status: 'verified' },
    });
    ok(clipped.status === 201, 'over-long reference accepted (clipped server-side)');
    const list2 = await call('GET', '/v1/receipts', { bearer: accessToken });
    const v3 = (list2.json?.receipts || []).find((r) => r.entryId === 'v3');
    ok(v3 && v3.reference.length === 255, 'reference clipped to 255 chars');

    const wipe = await call('DELETE', '/v1/receipts', { bearer: accessToken });
    ok(wipe.status === 200 && wipe.json?.ok === true, 'DELETE /v1/receipts → ok (privacy path)');
    const emptied = await call('GET', '/v1/receipts', { bearer: accessToken });
    ok(emptied.status === 200 && emptied.json?.count === 0, 'ledger empty after wipe');
  }

  // ── professional account records (v1.17.0) ────────────────────────────
  console.log('[account identity + audit]');
  let secondToken = '';
  {
    const idHash2 = H64();
    const authKey2 = H64();
    const created = await call('POST', '/v1/accounts', {
      body: { identifierHash: idHash2, authKey: authKey2, identifier: '+251911234567', displayName: 'Abebe Kebede' },
    });
    ok(created.status === 201, 'create account with identifier + name → 201');

    const firstLogin = await call('POST', '/v1/session', { body: { identifierHash: idHash2, authKey: authKey2 } });
    ok(firstLogin.status === 200, 'sign-in without identity fields → 200');
    secondToken = firstLogin.json?.accessToken || '';

    const again = await call('POST', '/v1/session', {
      body: { identifierHash: idHash2, authKey: authKey2, identifier: '+251911234567', displayName: 'Abebe Kebede' },
    });
    ok(again.status === 200, 'second sign-in → 200');

    const me = await call('GET', '/v1/account', { bearer: secondToken });
    ok(me.status === 200 && me.json?.identifier === '+251911234567', 'GET /v1/account returns readable identifier');
    ok(me.json?.identifierType === 'phone', 'identifier_type detected as phone');
    ok(me.json?.displayName === 'Abebe Kebede', 'display name stored');
    ok(me.json?.signInCount === 2, `sign_in_count = 2 (got ${me.json?.signInCount})`);
    ok(typeof me.json?.createdAt === 'number' && me.json.createdAt > 0, 'createdAt epoch present');

    // Legacy account (no identity at creation) backfills on first sign-in.
    const legacyHash = H64();
    const legacyKey = H64();
    await call('POST', '/v1/accounts', { body: { identifierHash: legacyHash, authKey: legacyKey } });
    const legacyLogin = await call('POST', '/v1/session', {
      body: { identifierHash: legacyHash, authKey: legacyKey, identifier: 'abebe@example.com' },
    });
    ok(legacyLogin.status === 200, 'legacy account sign-in → 200');
    const legacyMe = await call('GET', '/v1/account', { bearer: legacyLogin.json?.accessToken });
    ok(legacyMe.json?.identifier === 'abebe@example.com' && legacyMe.json?.identifierType === 'email',
      'identifier backfilled on sign-in (email type detected)');

    const patched = await call('PATCH', '/v1/account', { bearer: secondToken, body: { displayName: 'Abebe K.' } });
    ok(patched.status === 200 && patched.json?.ok === true, 'PATCH /v1/account → ok');
    const renamed = await call('GET', '/v1/account', { bearer: secondToken });
    ok(renamed.json?.displayName === 'Abebe K.', 'display name updated');

    const anonPatch = await call('PATCH', '/v1/account', { body: { displayName: 'X' } });
    ok(anonPatch.status === 401, 'PATCH /v1/account without bearer → 401');
  }

  // ── free-trial anti-abuse (v1.18.10) ──────────────────────────────────
  console.log('[trial budget sync]');
  {
    const dev = H64();
    const fresh = await call('POST', '/v1/trials/sync', { body: { deviceHash: dev } });
    ok(
      fresh.status === 200 && fresh.json?.used === 0 && fresh.json?.freeChecks === 5 && fresh.json?.trialsRemaining === 5,
      'fresh device → 5 trials remaining',
    );

    const used3 = await call('POST', '/v1/trials/sync', { body: { deviceHash: dev, used: 3 } });
    ok(used3.json?.used === 3 && used3.json?.trialsRemaining === 2, 'used=3 → 2 remaining');

    // Clear-storage simulation: the wiped app reports nothing (or 0) —
    // the server counter must not go down.
    const wiped = await call('POST', '/v1/trials/sync', { body: { deviceHash: dev } });
    ok(wiped.json?.used === 3 && wiped.json?.trialsRemaining === 2, 'cleared app cannot lower the counter');
    const liar = await call('POST', '/v1/trials/sync', { body: { deviceHash: dev, used: 0 } });
    ok(liar.json?.used === 3, 'explicit used=0 is clamped back up');
    const grow = await call('POST', '/v1/trials/sync', { body: { deviceHash: dev, used: 7 } });
    ok(grow.json?.used === 7 && grow.json?.trialsRemaining === 0, 'counter grows with the client, remaining floors at 0');

    const bad = await call('POST', '/v1/trials/sync', { body: { deviceHash: 'xyz' } });
    ok(bad.status === 400 && bad.json?.error === 'bad_input', 'bad deviceHash → 400');

    // Account-level cap: ledger rows count against the trial on ANY device,
    // so one account cannot double-dip from a second phone.
    const acctHash = H64();
    const acctKey = H64();
    await call('POST', '/v1/accounts', {
      body: { identifierHash: acctHash, authKey: acctKey, identifier: '+251922334455', displayName: 'Trial Tester' },
    });
    const acctLogin = await call('POST', '/v1/session', { body: { identifierHash: acctHash, authKey: acctKey } });
    const acctToken = acctLogin.json?.accessToken || '';
    await call('POST', '/v1/receipts', {
      bearer: acctToken,
      body: { entryId: 't1', bankId: 'cbe', reference: 'FT-TRIAL-1', status: 'verified' },
    });
    const otherDevice = await call('POST', '/v1/trials/sync', {
      bearer: acctToken,
      body: { deviceHash: H64() },
    });
    ok(otherDevice.json?.used >= 1, `account ledger caps the trial on a new device (used=${otherDevice.json?.used})`);

    const accountUsed4 = await call('POST', '/v1/trials/sync', {
      bearer: acctToken,
      body: { deviceHash: H64(), used: 4, accountScope: 'acct-hash-1' },
    });
    const accountWiped = await call('POST', '/v1/trials/sync', {
      bearer: acctToken,
      body: { deviceHash: H64(), accountScope: 'acct-hash-1' },
    });
    ok(accountUsed4.json?.used === 4 && accountWiped.json?.used === 4,
      'declared-scope account usage survives device changes and local counter resets');

    const proSync = await call('POST', '/v1/trials/sync', { body: { deviceHash: H64() } });
    ok(proSync.json?.pro?.active === false, 'no Pro → pro.active false (flag present)');

    // ── v1.19.3 scoping: a brand-new account on a used device keeps a
    // FRESH budget. v1.18.10–v1.19.2 merged the device's usage into the
    // signed-in account's ledger, so the phone's pre-sign-up checks
    // followed the user into the new account ("3 left" on day one).
    {
      const usedPhone = H64(); // spent 2 checks signed-out on this phone
      await call('POST', '/v1/trials/sync', { body: { deviceHash: usedPhone, used: 2 } });

      const freshHash = H64();
      const freshKey = H64();
      await call('POST', '/v1/accounts', {
        body: { identifierHash: freshHash, authKey: freshKey, identifier: '+251911223344', displayName: 'Fresh Account' },
      });
      const freshLogin = await call('POST', '/v1/session', { body: { identifierHash: freshHash, authKey: freshKey } });
      const freshToken = freshLogin.json?.accessToken || '';

      // Signed in on the used phone, legacy client (no accountScope):
      // the device's 2 checks must NOT enter the account ledger.
      const freshSync = await call('POST', '/v1/trials/sync', {
        bearer: freshToken,
        body: { deviceHash: usedPhone, used: 2 },
      });
      ok(
        freshSync.json?.used === 0 && freshSync.json?.trialsRemaining === 5 && freshSync.json?.scope === 'account',
        `fresh account on a used device keeps all 5 (used=${freshSync.json?.used})`,
      );

      // The device ledger absorbed the account's own usage after signing
      // in — signing out cannot resume a fresh device budget.
      const afterSignOut = await call('POST', '/v1/trials/sync', { body: { deviceHash: usedPhone } });
      ok(afterSignOut.json?.scope === 'device' && afterSignOut.json?.used >= 2,
        `signed-out budget on the same phone is still spent (used=${afterSignOut.json?.used})`);

      // A legacy client's report never lowers the fresh account budget
      // and never inflates it either (device numbers are ignored).
      const legacyLie = await call('POST', '/v1/trials/sync', {
        bearer: freshToken,
        body: { deviceHash: usedPhone, used: 4 },
      });
      ok(legacyLie.json?.used === 0, 'legacy client device-counter cannot poison the account budget');

      // v1.19.3+ client declaring its account scope raises its own budget.
      const scopedUse = await call('POST', '/v1/trials/sync', {
        bearer: freshToken,
        body: { deviceHash: usedPhone, used: 1, accountScope: 'fresh-hash-1' },
      });
      ok(scopedUse.json?.used === 1 && scopedUse.json?.trialsRemaining === 4,
        'declared-scope report raises the account budget');
      const scopedAgain = await call('POST', '/v1/trials/sync', {
        bearer: freshToken,
        body: { deviceHash: usedPhone, used: 0, accountScope: 'fresh-hash-1' },
      });
      ok(scopedAgain.json?.used === 1, 'declared-scope counter is monotonic');
    }
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
