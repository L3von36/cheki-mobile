# Deploy the Mahtem Node API on your Plesk hosting (mahtem.com.et)

This package turns your **Linux Bronze Plesk hosting** into two things:

1. **The Mahtem website** — landing page + privacy policy at `https://mahtem.com.et`
2. **The Mahtem Cloud API** — the same backend the app currently uses on
   Cloudflare (`mahtem-api.mahtem.workers.dev`), now running on **your own
   server in Ethiopia** (Node.js + MySQL) at `https://mahtem.com.et`

Existing users are migrated automatically: the first time someone signs in on
the new API, their account, encrypted backup and Pro status are imported from
the old Cloudflare service. Nothing is lost.

**What's in the package**

| File | What it is |
| --- | --- |
| `public/index.html` | Landing page (shows at mahtem.com.et) |
| `public/privacy.html` | Privacy policy page |
| `server.js` | Startup file (what Plesk launches) |
| `src/` | The Cloud API (Express + MySQL, ~4 small files) |
| `package.json` | Dependencies (Express + mysql2 — installed by Plesk) |
| `.env.example` | Template for **the only file you edit** (`.env`) |
| `schema.sql` | Optional: create tables by hand in phpMyAdmin (the app also auto-creates them) |
| `test/` | The full 57-check API test suite |

Requirements: **Node.js 18+** (your panel's Get Started screen shows the
Node.js option ✓) and the MySQL database that came with your plan.

---

## Step 1 — Create the MySQL database (2 minutes)

1. In Plesk, open **Databases** (left menu) → **Add Database**.
2. Fill in:
   - **Database name:** e.g. `mahtem`
   - **Related site:** `mahtem.com.et`
   - **Database username:** e.g. `mahtem`
   - **Password:** set a strong one (Plesk can generate it)
3. Click **OK**.

Plesk shows the final names — on your subscription they look like
`mahtemco_mahtem` (it adds your account prefix). Write down **database name,
username, password** — you need them in Step 3. The database server host is
usually `localhost`.

> You do NOT need to import `schema.sql` — all tables are created
> automatically on the first request. Importing it via phpMyAdmin is fine too.

## Step 2 — Upload the files

1. In Plesk open **Files** → go into the `httpdocs` folder.
2. **Delete the placeholder site files** currently in `httpdocs`.
3. Upload the **contents** of this package (or upload the zip and use
   **Extract**) so the final layout is exactly:

```
httpdocs/
├── package.json
├── server.js          ← startup file
├── .env               ← created in Step 3 (enable "show hidden files")
├── .env.example
├── schema.sql
├── public/
│   ├── index.html
│   └── privacy.html
├── src/
│   ├── app.js
│   ├── config.js
│   ├── db.js
│   ├── jwt.js
│   └── migrate.js
└── test/
```

> `node_modules/` is created by Plesk in Step 4 — never upload it.

## Step 3 — Create `.env` with your database values

1. In the File Manager, rename/copy `.env.example` to `.env`
   (enable **show hidden files** to see it).
2. Open `.env` and replace the three `REPLACE_WITH_…` values:

```
DB_NAME=mahtemco_mahtem
DB_USER=mahtemco_mahtem
DB_PASSWORD=•••your password•••
```

Leave `MIGRATE_FROM_URL` as it is — that's what imports your existing users
from Cloudflare. (Set it to empty after a few weeks, see below.)

## Step 4 — Register the app in Plesk's Node.js panel

1. Plesk → **Websites & Domains** → **Node.js**
   (or Get Started → **Node.js** like on your screenshot).
2. Set:
   - **Node.js version:** the newest available (must be 18 or higher)
   - **Application Root:** `httpdocs` (the folder with `package.json`)
   - **Application Startup File:** `server.js`
3. Click **Enable Node.js** / **OK**.
4. Click **Install NPM packages** (Plesk runs `npm install` for you —
   Express + mysql2, about 80 small packages).
5. Click **Restart App**.

## Step 5 — Install the HTTPS certificate (required)

The Android app only talks to `https://` addresses, so this step is mandatory:

1. Plesk → **Hosting & DNS** → **SSL/TLS Certificates**.
2. Click **Install a free basic certificate (Let's Encrypt)**.
3. Select `mahtem.com.et` (and `www.mahtem.com.et`), tick
   **"Redirect to HTTPS"** if asked, and install.

Takes about a minute and renews itself.

## Step 6 — Test it

Open in your phone/desktop browser:

- `https://mahtem.com.et` → you should see the Mahtem landing page.
- `https://mahtem.com.et/v1/health` → you should see JSON like:

```json
{"ok":true,"service":"mahtem-api","auth":"OAuth 2.0 / JWT (HS256) + Zero-Knowledge","version":"1.15.0-node","db":true,"time":"…"}
```

`"db":true` means the database connection works. If you see `"db":false`,
the credentials in `.env` are wrong (see Troubleshooting).

(Full check from a computer with Node installed:
`node test/test_api.mjs https://mahtem.com.et` — all 57 checks must pass.)

## Step 7 — Tell me it's live

Once `/v1/health` shows `"db":true`, the app itself gets switched over to
`https://mahtem.com.et` in its next release (a one-line change in
`lib/core/cloud/cloud_api.dart`, then a normal version bump + tag). Don't
change the app's address yourself — it ships with the next tagged build.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `health` shows `"db":false` | Database name/user/password in `.env` don't match Plesk. Re-check exactly (Plesk prefixes names with your account). Also check `DB_HOST` (usually `localhost`). |
| `NPM install` fails | Try again; if it persists, check the Node version is 18+ and the Application Root is the folder containing `package.json`. |
| The app logs "Cannot find module 'express'" | NPM packages not installed — press **Install NPM packages**, then **Restart App**. |
| Domain shows the Node app's 502 / nothing | Application Startup File must be `server.js` and it must stay in Application Root. Restart App after any edit. |
| `api/…` paths give 404 | Not needed in this deployment: the API lives at the domain **root** (`/v1/…`), no `/api` prefix. |
| Edits to `.env` don't take effect | Press **Restart App** in the Node.js panel. |

## Later (housekeeping)

- After a few weeks in production, edit `.env` and set
  `MIGRATE_FROM_URL=` (empty) so the server stops consulting the old
  Cloudflare service. Press **Restart App**.
- **Back up** your database now and then: Plesk → Databases → **Export** —
  it contains every account, backup and Pro record.
- The JWT signing secret is auto-created in the `config` table. Don't drop
  that table alone; if you ever restore an old backup, sessions simply
  re-login.
