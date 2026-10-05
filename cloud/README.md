# Mahtem Cloud API (Cloudflare Worker)

Zero-knowledge account + history-backup backend with **OAuth 2.1 / JWT Architecture** for Mahtem.

- **Live URL:** https://mahtem-api.mahtem.workers.dev
- **Runtime:** Cloudflare Workers + KV namespace `mahtem-api`
- **Source:** [`worker.js`](./worker.js) — single module, pure Web Crypto API, zero external dependencies

## Privacy contract (Zero-Knowledge)

The client derives everything on-device; the Worker stores only digests and ciphertext:

| Data sent to the server      | What it is                                              |
| ---------------------------- | ------------------------------------------------------- |
| `identifierHash`             | SHA-256 of the normalized account identifier            |
| `authKey`                    | PBKDF2-SHA256(password, "mahtem-cloud-auth-v1") — 120k  |
| `blob`                       | AES-256-GCM ciphertext of the history vault             |

The vault key (`PBKDF2(password, "mahtem-cloud-vault-v1:<identifier>")`)
NEVER leaves the phone. The raw password NEVER leaves the phone. Even a
full compromise of the Worker + KV store leaks no identifiers, no
passwords and no readable history.

## Token Architecture (OAuth 2.1 / JWT)

1. **Short-Lived Access Token (JWT, HS256)**:
   - **Lifespan**: 15 minutes (`exp: 900s`).
   - **Signed**: HMAC-SHA256 via standard Web Crypto (`crypto.subtle`).
   - **Stateless Verification**: Protected endpoints (`/v1/vault`, `/v1/session`) verify the cryptographic signature and expiration in-memory with **0 KV reads**, saving worker quota and reducing latency.
   - **Secret**: Stored securely in `env.JWT_SECRET` or auto-provisioned in `config:jwt_secret`.

2. **Rotating Refresh Token (`ref:...`)**:
   - **Lifespan**: 30 days in KV with auto-cleanup TTL.
   - **Token Rotation**: Every refresh generates a new refresh token and deletes the old one.
   - **Replay & Theft Protection**: Reusing an already-consumed refresh token immediately fails with `401 invalid_grant`.

## API Endpoints

| Route                     | Method | Auth     | Description / Notes                                        |
| ------------------------- | ------ | -------- | ---------------------------------------------------------- |
| `/v1/health`              | GET    | —        | Liveness probe & auth capability info                      |
| `/v1/accounts`            | POST   | —        | `{identifierHash, authKey}` → 201 / 409                    |
| `/v1/accounts/lookup`     | POST   | —        | `{identifierHash}` → `{exists, createdAt}`                 |
| `/v1/session`             | POST   | —        | `{identifierHash, authKey}` → `{accessToken, refreshToken, expiresIn, sessionToken, userId}` |
| `/v1/session/refresh`     | POST   | —        | `{refreshToken}` → Rotates token, returns new JWT + refresh token |
| `/v1/session`             | GET    | Bearer   | Stateless JWT validation → `{userId, exp, ok}`             |
| `/v1/session`             | DELETE | Bearer   | Revoke session / refresh token                             |
| `/v1/auth/revoke`         | POST   | —/Bearer | `{refreshToken}` → Revokes refresh token                   |
| `/v1/vault`               | PUT    | Bearer   | `{blob, revision[, baseRevision]}`; 409 conflict check     |
| `/v1/vault`               | GET    | Bearer   | `{blob, revision, updatedAt}` / 404 empty                  |
| `/v1/vault`               | DELETE | Bearer | Remove the cloud copy                              |
| `/v1/relay`               | POST   | —      | `{bank, url}` → fetches a geo-blocked Telebirr/M-Pesa receipt page (`bank` allowlisted; GET-only, never an open proxy) |

Every request must carry `X-Mahtem-Client` header.

## Automated Tests

Run the test suite locally with Node 20+:

```bash
node cloud/test_worker.mjs
```

## Deploy

Deploys are automatic: every push to `main` that touches `cloud/**` runs
[`.github/workflows/deploy-cloud.yml`](../.github/workflows/deploy-cloud.yml),
which uploads the module (with the KV binding re-asserted) and smoke-tests
`/v1/health`.
