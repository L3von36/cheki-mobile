# Mahtem Cloud API (Cloudflare Worker)

Zero-knowledge account + history-backup backend for Mahtem v1.13.0+.

- **Live URL:** https://mahtem-api.mahtem.workers.dev
- **Runtime:** Cloudflare Workers + KV namespace `mahtem-api`
- **Source:** [`worker.js`](./worker.js) — single module, no build step

## Privacy contract

The client derives everything on-device; the Worker stores only digests
and ciphertext:

| Data sent to the server      | What it is                                              |
| ---------------------------- | ------------------------------------------------------- |
| `identifierHash`             | SHA-256 of the normalized account identifier            |
| `authKey`                    | PBKDF2-SHA256(password, "mahtem-cloud-auth-v1") — 120k  |
| `blob`                       | AES-256-GCM ciphertext of the history vault             |

The vault key (`PBKDF2(password, "mahtem-cloud-vault-v1:<identifier>")`)
NEVER leaves the phone. The raw password NEVER leaves the phone. Even a
full compromise of the Worker + KV store leaks no identifiers, no
passwords and no readable history.

## API

| Route                     | Method | Auth     | Notes                                        |
| ------------------------- | ------ | -------- | -------------------------------------------- |
| `/v1/health`              | GET    | —        | Liveness probe                               |
| `/v1/accounts`            | POST   | —        | `{identifierHash, authKey}` → 201 / 409      |
| `/v1/accounts/lookup`     | POST   | —        | `{identifierHash}` → `{exists}`              |
| `/v1/session`             | POST   | —        | `{identifierHash, authKey}` → session token  |
| `/v1/session`             | GET    | Bearer   | Validate                                     |
| `/v1/session`             | DELETE | Bearer   | Revoke                                       |
| `/v1/vault`               | PUT    | Bearer   | `{blob, revision[, baseRevision]}`; 409 conflict when `baseRevision` is stale |
| `/v1/vault`               | GET    | Bearer   | `{blob, revision, updatedAt}` / 404 empty    |
| `/v1/vault`               | DELETE | Bearer   | Remove the cloud copy                        |

Every request must carry `X-Mahtem-Client` (cheap bot screen). Sessions
expire after 90 days (KV TTL auto-cleanup). KV free-tier quotas
(1,000 writes/day, 100k reads/day) act as the de-facto rate limiter.

## Deploy

Deploys are automatic: every push to `main` that touches `cloud/**` runs
[`.github/workflows/deploy-cloud.yml`](../.github/workflows/deploy-cloud.yml),
which uploads the module (with the KV binding re-asserted) and smoke-tests
`/v1/health`. It authenticates with the `CLOUDFLARE_API_TOKEN` repo secret
(a least-privilege token holding Workers Scripts edit only) and can be run
manually via **Run workflow** (workflow_dispatch) on the Actions tab.

Manual redeploy from a machine (same mechanism the workflow uses):

```bash
# metadata.json: {"main_module":"worker.js","compatibility_date":"2026-09-01",
#   "bindings":[{"type":"kv_namespace","name":"KV","namespace_id":"<KV_ID>"}]}
curl -X PUT -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/mahtem-api" \
  -F "metadata=@metadata.json;type=application/json" \
  -F "worker.js=@worker.js;type=application/javascript+module"
```

Rotate the deploy token from time to time (Cloudflare dashboard → My
Profile → API Tokens), then update the `CLOUDFLARE_API_TOKEN` repo secret
with the new value — no other change needed.
