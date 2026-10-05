import worker from './worker.js';

class MockKV {
  constructor() {
    this.store = new Map();
  }
  async get(key) {
    return this.store.has(key) ? this.store.get(key) : null;
  }
  async put(key, val, options) {
    this.store.set(key, typeof val === 'string' ? val : JSON.stringify(val));
  }
  async delete(key) {
    this.store.delete(key);
  }
  async list({ prefix = '', cursor } = {}) {
    const keys = [...this.store.keys()]
      .filter((k) => k.startsWith(prefix))
      .sort()
      .map((name) => ({ name }));
    return { keys, list_complete: true };
  }
}

const H = { 'X-Mahtem-Client': 'test', 'Content-Type': 'application/json' };
const req = (path, { method = 'GET', headers = {}, body } = {}) =>
  new Request(`http://localhost${path}`, {
    method,
    headers: { ...H, ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

async function run() {
  const env = { KV: new MockKV() };
  console.log('Running worker tests...');

  // 1. Health check
  const healthRes = await worker.fetch(req('/v1/health'), env);
  console.log('Health status:', healthRes.status, await healthRes.json());

  // 2. Create account
  const idHash = 'a'.repeat(64);
  const authKey = 'b'.repeat(64);
  const createRes = await worker.fetch(
    req('/v1/accounts', { method: 'POST', body: { identifierHash: idHash, authKey } }),
    env,
  );
  const createData = await createRes.json();
  console.log('Create account:', createRes.status, createData);

  // 3. Login / Create session
  const loginRes = await worker.fetch(
    req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }),
    env,
  );
  const loginData = await loginRes.json();
  console.log('Login session tokens:', {
    status: loginRes.status,
    hasAccessToken: !!loginData.accessToken,
    hasRefreshToken: !!loginData.refreshToken,
    expiresIn: loginData.expiresIn,
    userId: loginData.userId,
  });

  // Verify access token is a valid JWT (3 parts)
  const parts = loginData.accessToken.split('.');
  if (parts.length !== 3) throw new Error('AccessToken is not a 3-part JWT!');

  // 4. Access protected route with JWT (GET /v1/session)
  const sessionRes = await worker.fetch(
    req('/v1/session', {
      headers: { Authorization: `Bearer ${loginData.accessToken}` },
    }),
    env,
  );
  console.log('Verify JWT session:', sessionRes.status, await sessionRes.json());

  // 5. Test refresh token rotation (POST /v1/session/refresh)
  const refreshRes = await worker.fetch(
    req('/v1/session/refresh', {
      method: 'POST',
      body: { refreshToken: loginData.refreshToken },
    }),
    env,
  );
  const refreshData = await refreshRes.json();
  console.log('Refresh response:', {
    status: refreshRes.status,
    hasNewAccessToken: !!refreshData.accessToken,
    hasNewRefreshToken: !!refreshData.refreshToken,
    tokensDifferent: refreshData.refreshToken !== loginData.refreshToken,
  });

  // 6. Test old refresh token reuse (should fail with 401 invalid_grant)
  const reuseRes = await worker.fetch(
    req('/v1/session/refresh', {
      method: 'POST',
      body: { refreshToken: loginData.refreshToken },
    }),
    env,
  );
  console.log('Reused old refresh token status (expected 401):', reuseRes.status, await reuseRes.json());

  // 7. Revoke session
  const revokeRes = await worker.fetch(
    req('/v1/auth/revoke', {
      method: 'POST',
      body: { refreshToken: refreshData.refreshToken },
    }),
    env,
  );
  console.log('Revoke status:', revokeRes.status, await revokeRes.json());

  // ── v1.15.0: vault analytics piggyback + admin dashboard ────────────────
  const BLOB = 'QUJDREVGR0hJSktMTU5PUA=='; // >16 chars base64

  // Fresh session for vault writes
  const s2 = await (
    await worker.fetch(
      req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }),
      env,
    )
  ).json();

  // 8. Vault PUT with stats events
  const cbeT = Date.now() - 3600e3;
  const tbT = Date.now() - 60e3;
  const putRes = await worker.fetch(
    req('/v1/vault', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${s2.accessToken}` },
      body: {
        blob: BLOB,
        revision: Date.now(),
        stats: [
          { b: 'cbe', n: 'CBE', t: cbeT, v: 1 },
          { b: 'telebirr', n: 'Telebirr', t: tbT, v: 0 },
          { b: 'junk!', t: -5 }, // malformed — dropped
        ],
      },
    }),
    env,
  );
  console.log('Vault PUT with stats:', putRes.status, await putRes.json());

  // 9. Second PUT merges + dedupes (repeat one event, add one)
  await worker.fetch(
    req('/v1/vault', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${s2.accessToken}` },
      body: {
        blob: BLOB,
        revision: Date.now() + 1,
        stats: [{ b: 'cbe', n: 'CBE', t: cbeT, v: 1 }],
      },
    }),
    env,
  );
  const storedVault = JSON.parse(env.KV.store.get([...env.KV.store.keys()].find((k) => k.startsWith('vault:'))));
  if (storedVault.stats.length !== 2) {
    throw new Error(`Expected 2 deduped stats events, got ${storedVault.stats.length}`);
  }
  console.log('Stats stored (deduped):', storedVault.stats.length, 'events — OK');

  // 10. Admin overview requires the key
  const noKeyRes = await worker.fetch(req('/v1/admin/overview', {
    headers: { Authorization: 'Bearer whatever' },
  }), env);
  console.log('Admin without configured key (expected 503):', noKeyRes.status, await noKeyRes.json());

  env.ADMIN_KEY = 'test-admin-key-0123456789abcdef';
  const wrongKeyRes = await worker.fetch(req('/v1/admin/overview', {
    headers: { Authorization: 'Bearer wrong-key-1234567890' },
  }), env);
  if (wrongKeyRes.status !== 401) throw new Error('Admin gate accepted a wrong key!');
  console.log('Admin wrong key (expected 401): OK');

  // 11. Admin overview aggregates
  const okRes = await worker.fetch(req('/v1/admin/overview', {
    headers: { Authorization: `Bearer ${env.ADMIN_KEY}` },
  }), env);
  const overview = await okRes.json();
  console.log('Admin overview:', okRes.status, {
    accounts: overview.totals.accounts,
    vaults: overview.totals.vaults,
    scans: overview.totals.scans,
    banks: overview.banks.map((b) => `${b.id}:${b.count}`).join(','),
    days: overview.days.length,
    recent: overview.recent.length,
  });
  if (overview.totals.accounts < 1 || overview.totals.scans !== 2 || overview.days.length !== 30) {
    throw new Error('Admin overview aggregation is wrong!');
  }
  if (overview.totals.scans30d !== 2 || overview.banks[0].verified === undefined) {
    throw new Error('Admin overview v1.17.0 fields missing (scans30d / bank.verified)!');
  }

  // 11b. Per-account detail (v1.17.0)
  const acctPrefix = [...env.KV.store.keys()].find((k) => k.startsWith('vault:')).slice(6, 14);
  const noAuthDetail = await worker.fetch(req(`/v1/admin/account/${acctPrefix}`), env);
  if (noAuthDetail.status !== 401) throw new Error('Account detail must require auth!');
  const detailRes = await worker.fetch(req(`/v1/admin/account/${acctPrefix}`, {
    headers: { Authorization: `Bearer ${env.ADMIN_KEY}` },
  }), env);
  const detail = await detailRes.json();
  console.log('Admin account detail:', detailRes.status, {
    id: detail.id, scans: detail.scans, verified: detail.verified,
    banks: (detail.banks || []).map((b) => `${b.id}:${b.count}/${b.verified}`).join(','),
    events: (detail.events || []).length, days: (detail.days || []).length,
  });
  if (detailRes.status !== 200 || detail.scans !== 2 || detail.verified !== 1) {
    throw new Error('Account detail aggregation is wrong!');
  }
  if ((detail.days || []).length !== 30 || (detail.events || []).length !== 2) {
    throw new Error('Account detail series/events wrong!');
  }
  const missingDetail = await worker.fetch(req('/v1/admin/account/00000000', {
    headers: { Authorization: `Bearer ${env.ADMIN_KEY}` },
  }), env);
  if (missingDetail.status !== 404) throw new Error('Unknown prefix must 404!');
  // Forced prefix collision → 409 ambiguous
  env.KV.store.set('vault:deadbeef-1111', JSON.stringify({ blob: BLOB, revision: 1, updatedAt: Date.now(), stats: [] }));
  env.KV.store.set('vault:deadbeef-2222', JSON.stringify({ blob: BLOB, revision: 2, updatedAt: Date.now(), stats: [] }));
  const ambRes = await worker.fetch(req('/v1/admin/account/deadbeef', {
    headers: { Authorization: `Bearer ${env.ADMIN_KEY}` },
  }), env);
  const amb = await ambRes.json();
  env.KV.store.delete('vault:deadbeef-1111');
  env.KV.store.delete('vault:deadbeef-2222');
  if (ambRes.status !== 409 || amb.error !== 'ambiguous' || (amb.ids || []).length !== 2) {
    throw new Error('Ambiguous prefix must 409 with ids!');
  }
  console.log('Account detail auth/404/ambiguous guards: OK');

  // 12. /admin dashboard page serves HTML with NO client header (browser)
  const pageRes = await worker.fetch(new Request('http://localhost/admin'), env);
  const pageText = await pageRes.text();
  if (pageRes.status !== 200 || !pageText.includes('Mahtem Admin')) {
    throw new Error('Admin dashboard page failed to serve!');
  }
  console.log('Admin dashboard page:', pageRes.status, pageRes.headers.get('content-type'), `(${pageText.length} bytes)`);

  // 13. Other routes still require the client header
  const bareRes = await worker.fetch(new Request('http://localhost/v1/health'), env);
  console.log('Missing header on /v1 (expected 400):', bareRes.status);

  // ── v1.16.0: admin owner account (email + password) ──────────────────────
  const st0 = await (
    await worker.fetch(req('/v1/admin/auth/status'), env)
  ).json();
  if (st0.hasAdmin !== false) throw new Error('hasAdmin should start false');

  const weak = await worker.fetch(
    req('/v1/admin/auth/setup', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'short' } }),
    env,
  );
  if (weak.status !== 400) throw new Error('weak password accepted!');

  const badEmail = await worker.fetch(
    req('/v1/admin/auth/setup', { method: 'POST', body: { email: 'not-an-email', password: 'long-enough-pass' } }),
    env,
  );
  if (badEmail.status !== 400) throw new Error('bad email accepted!');

  const setup = await (
    await worker.fetch(
      req('/v1/admin/auth/setup', {
        method: 'POST',
        body: { email: '  Owner@Mahtem.APP ', password: 'correct-horse-battery' },
      }),
      env,
    )
  ).json();
  if (!setup.token) throw new Error('setup failed: ' + JSON.stringify(setup));

  const dup = await worker.fetch(
    req('/v1/admin/auth/setup', { method: 'POST', body: { email: 'other@mahtem.app', password: 'another-long-password' } }),
    env,
  );
  if (dup.status !== 409) throw new Error('second setup should 409, got ' + dup.status);

  const me = await (
    await worker.fetch(req('/v1/admin/auth/me', { headers: { Authorization: `Bearer ${setup.token}` } }), env)
  ).json();
  if (me.email !== 'owner@mahtem.app') throw new Error('me should normalize the email, got ' + me.email);

  const ovSess = await worker.fetch(
    req('/v1/admin/overview', { headers: { Authorization: `Bearer ${setup.token}` } }),
    env,
  );
  if (ovSess.status !== 200) throw new Error('overview with owner session failed: ' + ovSess.status);

  const noAuth = await worker.fetch(req('/v1/admin/auth/me'), env);
  if (noAuth.status !== 401) throw new Error('me without token should 401');

  const badLogin = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'wrong-password-123' } }),
    env,
  );
  if (badLogin.status !== 401) throw new Error('bad login should 401');

  const wrongEmailLogin = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'someone@else.com', password: 'correct-horse-battery' } }),
    env,
  );
  if (wrongEmailLogin.status !== 401) throw new Error('wrong-email login should 401');

  const goodLogin = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'Owner@mahtem.app', password: 'correct-horse-battery' } }),
    env,
  );
  if (goodLogin.status !== 200) throw new Error('good login failed: ' + JSON.stringify(await goodLogin.json()));

  // change-password: wrong current → 401; correct → rotated session
  const chWrong = await worker.fetch(
    req('/v1/admin/auth/change-password', {
      method: 'POST',
      headers: { Authorization: `Bearer ${setup.token}` },
      body: { currentPassword: 'nope-not-it-password', newPassword: 'brand-new-password-1' },
    }),
    env,
  );
  if (chWrong.status !== 401) throw new Error('change-password wrong current should 401');

  const ch = await (
    await worker.fetch(
      req('/v1/admin/auth/change-password', {
        method: 'POST',
        headers: { Authorization: `Bearer ${setup.token}` },
        body: { currentPassword: 'correct-horse-battery', newPassword: 'brand-new-password-1' },
      }),
      env,
    )
  ).json();
  if (!ch.token) throw new Error('change-password failed: ' + JSON.stringify(ch));

  const oldSess = await worker.fetch(
    req('/v1/admin/overview', { headers: { Authorization: `Bearer ${setup.token}` } }),
    env,
  );
  if (oldSess.status !== 401) throw new Error('rotation should kill the old session');

  const reLogin = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'brand-new-password-1' } }),
    env,
  );
  if (reLogin.status !== 200) throw new Error('login with new password failed');

  const oldPw = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'correct-horse-battery' } }),
    env,
  );
  if (oldPw.status !== 401) throw new Error('old password should be rejected');

  // logout is idempotent and kills the session
  const out = await worker.fetch(
    req('/v1/admin/auth/logout', { method: 'POST', headers: { Authorization: `Bearer ${ch.token}` } }),
    env,
  );
  if (out.status !== 200) throw new Error('logout failed');
  const dead = await worker.fetch(
    req('/v1/admin/overview', { headers: { Authorization: `Bearer ${ch.token}` } }),
    env,
  );
  if (dead.status !== 401) throw new Error('session should be dead after logout');

  // rate limit: 8 failures in the window → 429 even for the right password
  for (let i = 0; i < 8; i++) {
    await worker.fetch(
      req('/v1/admin/auth/login', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'wrong-password-123' } }),
      env,
    );
  }
  const rl = await worker.fetch(
    req('/v1/admin/auth/login', { method: 'POST', body: { email: 'owner@mahtem.app', password: 'brand-new-password-1' } }),
    env,
  );
  if (rl.status !== 429) throw new Error('rate limit should 429, got ' + rl.status);

  // legacy ADMIN_KEY still unlocks the overview (break-glass / old clients)
  const legacy = await worker.fetch(
    req('/v1/admin/overview', { headers: { Authorization: `Bearer ${env.ADMIN_KEY}` } }),
    env,
  );
  if (legacy.status !== 200) throw new Error('legacy ADMIN_KEY path broke');

  // break-glass reset removes the owner + sessions → first-run setup again
  const reset = await worker.fetch(
    req('/v1/admin/auth/reset', { method: 'POST', headers: { Authorization: `Bearer ${env.ADMIN_KEY}` } }),
    env,
  );
  if (reset.status !== 200) throw new Error('reset failed');
  const resetNoKey = await worker.fetch(req('/v1/admin/auth/reset', { method: 'POST' }), env);
  if (resetNoKey.status !== 401) throw new Error('reset without key should 401');
  const st1 = await (await worker.fetch(req('/v1/admin/auth/status'), env)).json();
  if (st1.hasAdmin !== false) throw new Error('reset should clear hasAdmin');

  console.log('Admin auth scenarios (setup/login/me/change-password/logout/rate-limit/reset): OK');

  // ── v1.18: management layer (CRUD) ──────────────────────────────────────
  console.log('Management layer tests...');

  // Fresh owner (previous section was reset to first-run)
  const setup2 = await (
    await worker.fetch(
      req('/v1/admin/auth/setup', { method: 'POST', body: { email: 'owner2@mahtem.app', password: 'owner-password-1' } }),
      env,
    )
  ).json();
  if (!setup2.token) throw new Error('owner setup failed: ' + JSON.stringify(setup2));
  const ownerAuth = { Authorization: `Bearer ${setup2.token}` };

  const me2 = await (await worker.fetch(req('/v1/admin/auth/me', { headers: ownerAuth }), env)).json();
  if (me2.role !== 'owner') throw new Error('me should report role owner, got ' + JSON.stringify(me2));

  // Settings: defaults, owner-only mutation, enforcement
  const s0 = await (await worker.fetch(req('/v1/admin/settings', { headers: ownerAuth }), env)).json();
  if (s0.signupsEnabled !== true || s0.maintenanceMode !== false) throw new Error('settings defaults wrong: ' + JSON.stringify(s0));

  await worker.fetch(req('/v1/admin/settings', { method: 'PUT', headers: ownerAuth, body: { signupsEnabled: false } }), env);
  const signupBlocked = await worker.fetch(
    req('/v1/accounts', { method: 'POST', body: { identifierHash: 'c'.repeat(64), authKey: 'd'.repeat(64) } }),
    env,
  );
  if (signupBlocked.status !== 403) throw new Error('signups_disabled should 403, got ' + signupBlocked.status);

  await worker.fetch(req('/v1/admin/settings', { method: 'PUT', headers: ownerAuth, body: { signupsEnabled: true, maintenanceMode: true } }), env);
  const userLogin = await (
    await worker.fetch(req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }), env)
  ).json();
  const maint = await worker.fetch(
    req('/v1/vault', { method: 'PUT', headers: { Authorization: `Bearer ${userLogin.accessToken}` }, body: { blob: 'QUJDREVGR0hJSktMTU5PUA==', revision: 9 } }),
    env,
  );
  if (maint.status !== 503) throw new Error('maintenance should 503 vault writes, got ' + maint.status);
  await worker.fetch(req('/v1/admin/settings', { method: 'PUT', headers: ownerAuth, body: { maintenanceMode: false } }), env);

  // Admin users CRUD + role enforcement
  const badCreate = await worker.fetch(req('/v1/admin/users', { method: 'POST', headers: ownerAuth, body: { email: 'not-an-email', password: 'password-12345' } }), env);
  if (badCreate.status !== 400) throw new Error('invalid email should 400');
  const dupOwner = await worker.fetch(req('/v1/admin/users', { method: 'POST', headers: ownerAuth, body: { email: 'OWNER2@mahtem.app', password: 'password-12345' } }), env);
  if (dupOwner.status !== 409) throw new Error('owner email duplicate should 409');
  const created = await worker.fetch(req('/v1/admin/users', { method: 'POST', headers: ownerAuth, body: { email: 'helper@mahtem.app', password: 'helper-password-1' } }), env);
  if (created.status !== 201) throw new Error('admin create failed: ' + JSON.stringify(await created.json()));
  const helper = await created.json();

  const helperLogin = await (
    await worker.fetch(req('/v1/admin/auth/login', { method: 'POST', body: { email: 'helper@mahtem.app', password: 'helper-password-1' } }), env)
  ).json();
  if (!helperLogin.token || helperLogin.role !== 'admin') throw new Error('helper login failed or wrong role: ' + JSON.stringify(helperLogin));
  const helperAuth = { Authorization: `Bearer ${helperLogin.token}` };

  const helperUsers = await worker.fetch(req('/v1/admin/users', { headers: helperAuth }), env);
  if (helperUsers.status !== 200) throw new Error('admin GET users should 200');
  const helperCreate = await worker.fetch(req('/v1/admin/users', { method: 'POST', headers: helperAuth, body: { email: 'x@y.com', password: 'password-12345' } }), env);
  if (helperCreate.status !== 403) throw new Error('admin POST users should 403');
  const helperSettingsPut = await worker.fetch(req('/v1/admin/settings', { method: 'PUT', headers: helperAuth, body: { signupsEnabled: false } }), env);
  if (helperSettingsPut.status !== 403) throw new Error('admin PUT settings should 403');

  const rp = await worker.fetch(req(`/v1/admin/users/${helper.id}/reset-password`, { method: 'POST', headers: ownerAuth, body: { newPassword: 'helper-password-2' } }), env);
  if (rp.status !== 200) throw new Error('reset-password failed: ' + JSON.stringify(await rp.json()));
  const helperDead = await worker.fetch(req('/v1/admin/overview', { headers: helperAuth }), env);
  if (helperDead.status !== 401) throw new Error('reset should kill helper sessions');
  const helperRe = await (
    await worker.fetch(req('/v1/admin/auth/login', { method: 'POST', body: { email: 'helper@mahtem.app', password: 'helper-password-2' } }), env)
  ).json();
  if (!helperRe.token) throw new Error('helper relogin with new password failed');
  const helperAuth2 = { Authorization: `Bearer ${helperRe.token}` };

  // Announcements CRUD + public feed
  const ann = await worker.fetch(req('/v1/admin/announcements', { method: 'POST', headers: ownerAuth, body: { message: 'Scheduled maintenance tonight', level: 'warn' } }), env);
  if (ann.status !== 201) throw new Error('announcement create failed: ' + JSON.stringify(await ann.json()));
  const annRec = await ann.json();
  const helperAnn = await worker.fetch(req('/v1/admin/announcements', { method: 'POST', headers: helperAuth2, body: { message: 'Helper can post too' } }), env);
  if (helperAnn.status !== 201) throw new Error('admin announcement create should 201');
  const pub = await (await worker.fetch(req('/v1/announcements'), env)).json();
  if (!Array.isArray(pub.announcements) || pub.announcements.length !== 2) throw new Error('public announcements wrong: ' + JSON.stringify(pub));
  const annDel = await worker.fetch(req(`/v1/admin/announcements/${annRec.id}`, { method: 'DELETE', headers: ownerAuth }), env);
  if (annDel.status !== 200) throw new Error('announcement delete failed');
  const annDel2 = await worker.fetch(req(`/v1/admin/announcements/${annRec.id}`, { method: 'DELETE', headers: ownerAuth }), env);
  if (annDel2.status !== 404) throw new Error('double delete should 404');

  // Account suspend / unsuspend (admin role allowed)
  const vaultKey = [...env.KV.store.keys()].find((k) => k.startsWith('vault:'));
  const uid = vaultKey.slice(6);
  const acct = uid.slice(0, 8);
  const susp = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'PATCH', headers: ownerAuth, body: { suspended: true } }), env);
  if (susp.status !== 200) throw new Error('suspend failed: ' + JSON.stringify(await susp.json()));
  const suspWrite = await worker.fetch(
    req('/v1/vault', { method: 'PUT', headers: { Authorization: `Bearer ${userLogin.accessToken}` }, body: { blob: 'QUJDREVGR0hJSktMTU5PUA==', revision: 10 } }),
    env,
  );
  if (suspWrite.status !== 403) throw new Error('suspended vault write should 403, got ' + suspWrite.status);
  const suspLogin = await worker.fetch(req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }), env);
  if (suspLogin.status !== 403) throw new Error('suspended login should 403');
  const unsusp = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'PATCH', headers: helperAuth2, body: { suspended: false } }), env);
  if (unsusp.status !== 200) throw new Error('unsuspend (admin role) failed');
  const unsuspWrite = await worker.fetch(
    req('/v1/vault', { method: 'PUT', headers: { Authorization: `Bearer ${userLogin.accessToken}` }, body: { blob: 'QUJDREVGR0hJSktMTU5PUA==', revision: 10 } }),
    env,
  );
  if (unsuspWrite.status !== 200) throw new Error('unsuspended vault write should 200, got ' + unsuspWrite.status);

  // Legacy ADMIN_KEY: read-only analytics, no management
  const legacyOverview = await worker.fetch(req('/v1/admin/overview', { headers: { Authorization: `Bearer ${env.ADMIN_KEY}` } }), env);
  if (legacyOverview.status !== 200) throw new Error('legacy overview should stay 200');
  const legacySettings = await worker.fetch(req('/v1/admin/settings', { headers: { Authorization: `Bearer ${env.ADMIN_KEY}` } }), env);
  if (legacySettings.status !== 403) throw new Error('legacy settings GET should 403');
  const legacyPatch = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'PATCH', headers: { Authorization: `Bearer ${env.ADMIN_KEY}` }, body: { suspended: true } }), env);
  if (legacyPatch.status !== 403) throw new Error('legacy PATCH should 403');
  const legacyUsers = await worker.fetch(req('/v1/admin/users', { headers: { Authorization: `Bearer ${env.ADMIN_KEY}` } }), env);
  if (legacyUsers.status !== 403) throw new Error('legacy users GET should 403');

  // Account delete: typed confirm, full wipe, tombstone
  const noConfirm = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'DELETE', headers: ownerAuth, body: { confirm: 'zzzz' } }), env);
  if (noConfirm.status !== 400) throw new Error('delete without confirm should 400');
  const del = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'DELETE', headers: ownerAuth, body: { confirm: acct } }), env);
  if (del.status !== 200) throw new Error('delete failed: ' + JSON.stringify(await del.json()));
  const delData = await del.json();
  if (!delData.userRemoved) throw new Error('delete should remove the user record: ' + JSON.stringify(delData));
  const afterDel = await (await worker.fetch(req('/v1/admin/overview', { headers: ownerAuth }), env)).json();
  if (afterDel.totals.vaults !== 0) throw new Error('vault should be gone after delete');
  const zombieWrite = await worker.fetch(
    req('/v1/vault', { method: 'PUT', headers: { Authorization: `Bearer ${userLogin.accessToken}` }, body: { blob: 'QUJDREVGR0hJSktMTU5PUA==', revision: 11 } }),
    env,
  );
  if (zombieWrite.status !== 403) throw new Error('tombstone should block zombie vault write, got ' + zombieWrite.status);
  const deadLogin = await worker.fetch(req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }), env);
  if (deadLogin.status !== 404) throw new Error('deleted account login should 404, got ' + deadLogin.status);
  const patchDeleted = await worker.fetch(req(`/v1/admin/account/${acct}`, { method: 'PATCH', headers: ownerAuth, body: { suspended: false } }), env);
  if (patchDeleted.status !== 404) throw new Error('patching a deleted account should 404 (vault gone), got ' + patchDeleted.status);

  // Audit trail captured the whole story
  const audit = await (await worker.fetch(req('/v1/admin/audit', { headers: ownerAuth }), env)).json();
  const actions = (audit.entries || []).map((e) => e.action);
  for (const expected of [
    'settings_updated',
    'admin_created',
    'admin_reset_password',
    'announcement_created',
    'announcement_deleted',
    'account_suspended',
    'account_unsuspended',
    'account_deleted',
    'break_glass_reset',
  ]) {
    if (!actions.includes(expected)) throw new Error(`audit missing ${expected}; have: ${actions.join(',')}`);
  }

  // Removing an admin kills their sessions and future logins
  const rm = await worker.fetch(req(`/v1/admin/users/${helper.id}`, { method: 'DELETE', headers: ownerAuth }), env);
  if (rm.status !== 200) throw new Error('admin remove failed');
  const helperGone = await worker.fetch(req('/v1/admin/overview', { headers: { Authorization: `Bearer ${helperRe.token}` } }), env);
  if (helperGone.status !== 401) throw new Error('removed admin session should 401');
  const helperLoginGone = await worker.fetch(req('/v1/admin/auth/login', { method: 'POST', body: { email: 'helper@mahtem.app', password: 'helper-password-2' } }), env);
  if (helperLoginGone.status !== 401) throw new Error('removed admin login should 401');

  console.log('Management layer (settings/users/announcements/suspend/delete/audit/legacy): OK');

  console.log('All worker tests passed successfully!');
}

run().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
