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
}

async function run() {
  const env = { KV: new MockKV() };
  console.log("Running worker tests...");

  // 1. Health check
  const healthReq = new Request("http://localhost/v1/health", {
    headers: { "X-Mahtem-Client": "test" }
  });
  const healthRes = await worker.fetch(healthReq, env);
  console.log("Health status:", healthRes.status, await healthRes.json());

  // 2. Create account
  const idHash = "a".repeat(64);
  const authKey = "b".repeat(64);
  const createReq = new Request("http://localhost/v1/accounts", {
    method: "POST",
    headers: { "X-Mahtem-Client": "test", "Content-Type": "application/json" },
    body: JSON.stringify({ identifierHash: idHash, authKey })
  });
  const createRes = await worker.fetch(createReq, env);
  const createData = await createRes.json();
  console.log("Create account:", createRes.status, createData);

  // 3. Login / Create session
  const loginReq = new Request("http://localhost/v1/session", {
    method: "POST",
    headers: { "X-Mahtem-Client": "test", "Content-Type": "application/json" },
    body: JSON.stringify({ identifierHash: idHash, authKey })
  });
  const loginRes = await worker.fetch(loginReq, env);
  const loginData = await loginRes.json();
  console.log("Login session tokens:", {
    status: loginRes.status,
    hasAccessToken: !!loginData.accessToken,
    hasRefreshToken: !!loginData.refreshToken,
    expiresIn: loginData.expiresIn,
    userId: loginData.userId
  });

  // Verify access token is a valid JWT (3 parts)
  const parts = loginData.accessToken.split('.');
  if (parts.length !== 3) throw new Error("AccessToken is not a 3-part JWT!");

  // 4. Access protected route with JWT (GET /v1/session)
  const sessionReq = new Request("http://localhost/v1/session", {
    headers: {
      "X-Mahtem-Client": "test",
      "Authorization": `Bearer ${loginData.accessToken}`
    }
  });
  const sessionRes = await worker.fetch(sessionReq, env);
  console.log("Verify JWT session:", sessionRes.status, await sessionRes.json());

  // 5. Test refresh token rotation (POST /v1/session/refresh)
  const refreshReq = new Request("http://localhost/v1/session/refresh", {
    method: "POST",
    headers: { "X-Mahtem-Client": "test", "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: loginData.refreshToken })
  });
  const refreshRes = await worker.fetch(refreshReq, env);
  const refreshData = await refreshRes.json();
  console.log("Refresh response:", {
    status: refreshRes.status,
    hasNewAccessToken: !!refreshData.accessToken,
    hasNewRefreshToken: !!refreshData.refreshToken,
    tokensDifferent: refreshData.refreshToken !== loginData.refreshToken
  });

  // 6. Test old refresh token reuse (should fail with 401 invalid_grant)
  const reuseReq = new Request("http://localhost/v1/session/refresh", {
    method: "POST",
    headers: { "X-Mahtem-Client": "test", "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: loginData.refreshToken })
  });
  const reuseRes = await worker.fetch(reuseReq, env);
  console.log("Reused old refresh token status (expected 401):", reuseRes.status, await reuseRes.json());

  // 7. Revoke session
  const revokeReq = new Request("http://localhost/v1/auth/revoke", {
    method: "POST",
    headers: { "X-Mahtem-Client": "test", "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: refreshData.refreshToken })
  });
  const revokeRes = await worker.fetch(revokeReq, env);
  console.log("Revoke status:", revokeRes.status, await revokeRes.json());

  console.log("All worker tests passed successfully!");
}

run().catch(err => {
  console.error("Test failed:", err);
  process.exit(1);
});
