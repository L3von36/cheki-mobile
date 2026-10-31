# Deploy Mahtem on your Plesk hosting (mahtem.com.et)

This package turns your **Linux Bronze Plesk hosting** into two things:

1. **The Mahtem website** — landing page + privacy policy at `https://mahtem.com.et`
2. **The Mahtem Cloud API** — the same backend the app currently uses on
   Cloudflare (`mahtem-api.mahtem.workers.dev`), now running on **your own
   server in Ethiopia** (PHP + MySQL), at `https://mahtem.com.et/api`

Existing users are migrated automatically: the first time someone signs in on
the new API, their account, encrypted backup and Pro status are imported from
the old Cloudflare service. Nothing is lost.

**What's in the package**

| File | What it is |
| --- | --- |
| `index.html` | Landing page (shows at mahtem.com.et) |
| `privacy.html` | Privacy policy page |
| `.htaccess` | Web-root rules: force HTTPS, security headers |
| `api/index.php` | The Cloud API (single file, no dependencies) |
| `api/config.php` | **The only file you edit** (3 lines) |
| `api/.htaccess` | API routing rules |

Requirements: PHP **8.0+** with PDO + curl (your panel shows PHP 8.3.36 ✓).

---

## Step 1 — Create the MySQL database (2 minutes)

1. In Plesk, open **Databases** (left menu) → **Add Database**.
2. Fill in:
   - **Database name:** e.g. `mahtem`
   - **Related site:** `mahtem.com.et`
   - **Database username:** e.g. `mahtem`
   - **Password:** set a strong one (Plesk can generate it)
3. Click **OK**.

Plesk will show the final names — on your subscription they look like
`mahtemco_mahtem` and `mahtemco_mahtem` (it adds your account prefix).
Write down **database name, username, password** — you need them in Step 2.

> Note the **database server host** shown in Plesk (usually `localhost`).

## Step 2 — Fill in `api/config.php`

Open `api/config.php` in any text editor and replace the three placeholder
values with the ones from Step 1:

```php
'dbname' => 'REPLACE_WITH_DB_NAME',   →  'mahtemco_mahtem',
'user'   => 'REPLACE_WITH_DB_USER',   →  'mahtemco_mahtem',
'pass'   => 'REPLACE_WITH_DB_PASSWORD', →  '•••your password•••',
```

That is the only edit. Leave `driver` as `'mysql'` and leave the
`migrate_from_url` line as it is.

## Step 3 — Upload the files

1. In Plesk open **Files** → go into the `httpdocs` folder.
2. **Delete the placeholder site files** currently in `httpdocs`
   (the demo page files — `index.html`, css/images from the template, etc.).
3. Upload **the whole package** (or upload the zip and use **Extract**):
   the two `.html` files, the two `.htaccess` files, and the `api` folder.
4. Final layout must be exactly:

```
httpdocs/
├── .htaccess          ← note: files starting with a dot may be hidden;
├── index.html            enable "show hidden files" in the File Manager
├── privacy.html
└── api/
    ├── .htaccess
    ├── config.php     ← the one you edited
    └── index.php
```

## Step 4 — Install the HTTPS certificate (required)

The Android app only talks to `https://` addresses, so this step is mandatory:

1. Plesk → **Hosting & DNS** → **SSL/TLS Certificates**.
2. Click **Install a free basic certificate (Let's Encrypt)**.
3. Select the domain `mahtem.com.et` (and `www.mahtem.com.et`), tick
   **"Redirect to HTTPS"** if asked, and install.

Takes about a minute and renews itself.

## Step 5 — Test it

Open in your phone/desktop browser:

- `https://mahtem.com.et` → you should see the Mahtem landing page.
- `https://mahtem.com.et/api/v1/health` → you should see JSON like:

```json
{"ok":true,"service":"mahtem-api","auth":"OAuth 2.0 / JWT (HS256) + Zero-Knowledge","version":"1.15.0-plesk","db":true,"time":"…"}
```

`"db":true` means the database connection works. If you see `"db":false`,
the credentials in `api/config.php` are wrong (see Troubleshooting).

(Developers can also run the full 57-check test suite from a computer:
`node cloud/plesk/test_api.mjs https://mahtem.com.et/api` — it's in the repo.)

## Step 6 — Tell me it's live

Once `/api/v1/health` shows `"db":true`, the app itself gets switched over to
`https://mahtem.com.et/api` in its next release (a one-line change in
`lib/core/cloud/cloud_api.dart`, then a normal version bump + tag). Don't
change the app's address yourself — it ships with the next tagged build.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `health` shows `"db":false` | Database name/user/password in `api/config.php` don't match Plesk. Re-check exactly (Plesk prefixes names with your account). |
| `api/v1/health` returns Plesk's 404 page | `.htaccess` override is disabled for the domain. In Plesk: Apache & nginx Settings → ensure "Allow run PHP in …"/`.htaccess` processing is on; or ask the host to enable `AllowOverride All`. |
| Login fails from the app, everything else works | The `Authorization` header is being stripped. Keep the `RewriteCond … HTTP_AUTHORIZATION` lines in `api/.htaccess` (they're included). |
| Upload of vault backups fails (413 or empty) | PHP limit too low: Plesk → PHP Settings → raise `post_max_size` and `upload_max_filesize` to **16M**. |
| "headers already sent" or raw PHP shown | PHP version below 8.0 — switch the domain to PHP 8.3 in Plesk → PHP Settings. |

## Later (housekeeping)

- After a few weeks in production, edit `api/config.php` and set
  `'migrate_from_url' => ''` so the server stops consulting the old
  Cloudflare service.
- **Back up** your database now and then: Plesk → Databases → **Export** —
  it contains every account, backup and Pro record.
- The JWT signing secret is auto-created in the `config` table. Don't drop
  that table alone; if you ever restore an old backup, sessions simply
  re-login.
