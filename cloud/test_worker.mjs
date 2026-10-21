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

  const BLOB = 'QUJDREVGR0hJSktMTU5PUA==';
  const s2 = await (
    await worker.fetch(
      req('/v1/session', { method: 'POST', body: { identifierHash: idHash, authKey } }),
      env,
    )
  ).json();
  // 8. Encrypted vault write/read round-trip
  const putRes = await worker.fetch(
    req('/v1/vault', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${s2.accessToken}` },
      body: { blob: BLOB, revision: Date.now() },
    }),
    env,
  );
  if (putRes.status !== 200) throw new Error('Vault PUT failed: ' + putRes.status);
  const getRes = await worker.fetch(
    req('/v1/vault', { headers: { Authorization: `Bearer ${s2.accessToken}` } }),
    env,
  );
  const vaultData = await getRes.json();
  if (getRes.status !== 200 || vaultData.blob !== BLOB) throw new Error('Vault GET failed');
  console.log('Vault PUT/GET round-trip: OK');
  // ── Geo-block relay (upstream fetch stubbed) ─────────────────────────────
  const realFetch = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url, init) => {
    fetched.push({ url: String(url), method: init?.method });
    return new Response('<html>receipt</html>', { status: 200 });
  };
  try {
    // Allowed bank + host is fetched and wrapped
    const relayUrl = 'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C';
    const okRes = await worker.fetch(req('/v1/relay', {
      method: 'POST',
      body: { bank: 'telebirr', url: relayUrl },
    }), env);
    const okData = await okRes.json();
    if (okRes.status !== 200 || okData.ok !== true || okData.status !== 200 ||
        okData.body !== '<html>receipt</html>') {
      throw new Error(`relay happy path failed: ${okRes.status} ${JSON.stringify(okData)}`);
    }
    if (fetched.length !== 1 || fetched[0].method !== 'GET' || fetched[0].url !== relayUrl) {
      throw new Error(`relay did not forward the exact GET: ${JSON.stringify(fetched)}`);
    }
    console.log('Relay happy path:', okRes.status, { forwarded: fetched[0].url });

    // Unknown bank rejected
    const badBank = await worker.fetch(req('/v1/relay', {
      method: 'POST',
      body: { bank: 'cbe', url: 'https://Mb.cbe.com.et/x' },
    }), env);
    if (badBank.status !== 400) throw new Error('relay accepted a non-allowlisted bank');
    console.log('Relay bad bank:', badBank.status, await badBank.json());

    // Host outside the allowlist rejected (not an open proxy)
    const badHost = await worker.fetch(req('/v1/relay', {
      method: 'POST',
      body: { bank: 'telebirr', url: 'https://evil.example.com/receipt/CHQ261Z4AB2C' },
    }), env);
    if (badHost.status !== 400) throw new Error('relay accepted a foreign host');
    console.log('Relay bad host:', badHost.status, await badHost.json());

    // Non-https scheme rejected
    const badScheme = await worker.fetch(req('/v1/relay', {
      method: 'POST',
      body: { bank: 'mpesa', url: 'http://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=X' },
    }), env);
    if (badScheme.status !== 400) throw new Error('relay accepted http://');
    console.log('Relay bad scheme:', badScheme.status, await badScheme.json());

    // Upstream failure maps to 502, never hangs
    globalThis.fetch = async () => { throw new Error('upstream down'); };
    const down = await worker.fetch(req('/v1/relay', {
      method: 'POST',
      body: { bank: 'mpesa', url: 'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=SJ72HK3YZ9' },
    }), env);
    if (down.status !== 502) throw new Error('upstream failure did not map to 502');
    console.log('Relay upstream down:', down.status, await down.json());
  } finally {
    globalThis.fetch = realFetch;
  }

  console.log('All worker tests passed successfully!');
}

run().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
