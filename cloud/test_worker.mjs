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
  if (overview.totals.accounts < 1 || overview.totals.scans !== 2 || overview.days.length !== 14) {
    throw new Error('Admin overview aggregation is wrong!');
  }

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

  console.log('All worker tests passed successfully!');
}

run().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
