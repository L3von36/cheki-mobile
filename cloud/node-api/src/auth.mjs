/**
 * Mahtem Cloud API — BetterAuth identity layer (v1.19.0-node).
 *
 * Replaces the homegrown zero-knowledge session handshake for SIGN-IN with
 * Better Auth (https://better-auth.com) while everything the app already
 * does — vault, Pro receipts, verified-receipt ledger, free-trial budget —
 * keeps working unchanged (see auth-bridge.cjs: BetterAuth sessions are
 * resolved onto the existing `accounts.user_id`).
 *
 * Storage: a dedicated SQLite database (node:sqlite, Node >= 22.5 — no
 * native build step on Plesk). Identity tables live apart from the Plesk
 * MySQL data so a Better Auth version bump can never corrupt app data; the
 * bridge row in MySQL carries `better_auth_user_id`.
 *
 * Plugins:
 *   * bearer               — native/mobile clients authenticate with
 *                            `Authorization: Bearer <token>` (token arrives
 *                            in the sign-in response body AND the
 *                            `set-auth-token` header).
 *   * device-authorization — GitHub sign-in on the Flutter app: the app
 *                            requests a device code, the user approves in
 *                            the browser (public/auth/device.html), the app
 *                            polls /device/token for its bearer token.
 *
 * All options are environment-driven; see .env.example.
 */
import { betterAuth } from 'better-auth';
import { bearer, deviceAuthorization } from 'better-auth/plugins';
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import config from './config.js';
import db from './db.js';

let authInstance = null;
let authPromise = null;

/** Applies the shipped BetterAuth DDL (src/auth-schema.sql) idempotently:
 * tables/indexes are created only when missing, ALTERs are best-effort
 * (they duplicate on the happy path), exactly like ensureSchema() in
 * db.js. Runs on every boot before the BetterAuth instance is built. */
async function applyAuthSchema(database) {
  const ddlPath = path.join(path.dirname(new URL(import.meta.url).pathname), 'auth-schema.sql');
  let raw;
  try {
    raw = fs.readFileSync(ddlPath, 'utf8');
  } catch (_) {
    console.error('[mahtem-api] auth-schema.sql missing — run scripts/gen_auth_schema.mjs');
    return;
  }
  const statements = raw
    .split('\n')
    .filter((line) => !/^\s*--/.test(line)) // drop comment lines first —
    .join('\n') // a ';' inside a comment must not split statements
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean);
  for (const sql of statements) {
    try {
      if (/^CREATE TABLE/i.test(sql)) {
        const table = sql.match(/["'`]([^"'`]+)["'`]/)?.[1];
        if (table) {
          const row = database
            .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name = ?")
            .get(table);
          if (row) continue; // exists — skip (CREATE TABLE has no IF NOT EXISTS here)
        }
      }
      database.exec(sql);
    } catch (_) {
      // CREATE INDEX re-run / ALTER "duplicate column" — already applied.
    }
  }
}

/** The email Better Auth sees for a phone-identifier account. Better Auth
 * requires an email; phones map onto a reserved synthetic domain that the
 * bridge maps straight back (identifierFromBaEmail). */
export function baEmailForIdentifier(identifier) {
  const id = String(identifier || '').trim().toLowerCase();
  if (id.includes('@')) return id;
  return `${id}@phone.mahtem.et`;
}

/** Inverse of baEmailForIdentifier — used when bridging a Better Auth user
 * onto the readable `accounts` identity. */
export function identifierFromBaEmail(email) {
  const value = String(email || '').trim().toLowerCase();
  const at = value.lastIndexOf('@');
  if (at <= 0) return { value: value || 'unknown', type: 'email' };
  const local = value.slice(0, at);
  if (value.endsWith('@phone.mahtem.et') && /^[0-9]+$/.test(local)) {
    return { value: local, type: 'phone' };
  }
  return { value, type: 'email' };
}

async function ensureSecret() {
  const envSecret = process.env.BETTER_AUTH_SECRET || '';
  if (envSecret.length >= 32) return envSecret;
  const rows = await db.query("SELECT v FROM `config` WHERE k = 'better_auth_secret'");
  if (rows.length && String(rows[0].v || '').length >= 32) return String(rows[0].v);
  const secret = crypto.randomBytes(48).toString('base64url');
  await db.run(
    `${db.INSERT_IGNORE} \`config\` (\`k\`, \`v\`) VALUES ('better_auth_secret', ?)`,
    [secret],
  );
  const after = await db.query("SELECT v FROM `config` WHERE k = 'better_auth_secret'");
  return String(after[0].v);
}

function publicBaseUrl() {
  return (
    process.env.BETTER_AUTH_URL ||
    config.publicBaseUrl ||
    'https://mahtem.com.et'
  ).replace(/\/+$/, '');
}

function trustedOrigins() {
  const base = publicBaseUrl();
  const list = new Set([base, config.publicBaseUrl || base]);
  for (const extra of (process.env.BETTER_AUTH_TRUSTED_ORIGINS || '').split(',')) {
    const trimmed = extra.trim();
    if (trimmed) list.add(trimmed);
  }
  return [...list];
}

/** Assembles the betterAuth options object. Shared by the live instance
 * (buildAuth) and scripts/gen_auth_schema.mjs (schema DDL generation), so
 * the shipped auth-schema.sql always matches the configured plugins. */
export function authOptions(database, secret) {
  const githubId = process.env.GITHUB_CLIENT_ID || '';
  const githubSecret = process.env.GITHUB_CLIENT_SECRET || '';

  return {
    database,
    secret,
    baseURL: publicBaseUrl(),
    basePath: '/api/auth',
    trustedOrigins: trustedOrigins(),
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 6, // the app's own floor — keep the two in sync
    },
    session: {
      expiresIn: 60 * 60 * 24 * 30, // 30 days, like the legacy refresh token
      updateAge: 60 * 60 * 24,
    },
    ...(githubId && githubSecret
      ? {
          socialProviders: {
            github: {
              clientId: githubId,
              clientSecret: githubSecret,
            },
          },
        }
      : {}),
    plugins: [
      bearer(),
      // The device-verification URL must point at the human page served
      // from public/, not at the JSON /device endpoint.
      deviceAuthorization({ verificationUri: '/auth/device.html' }),
    ],
  };
}

async function buildAuth() {
  const secret = await ensureSecret();
  const sqlitePath = config.betterAuthSqlitePath;
  fs.mkdirSync(path.dirname(sqlitePath), { recursive: true });
  const database = new DatabaseSync(sqlitePath);
  database.exec('PRAGMA journal_mode=WAL;');
  database.exec('PRAGMA busy_timeout=5000;');

  const options = authOptions(database, secret);

  // Create/upgrade BetterAuth's own tables BEFORE the instance boots —
  // it validates the schema on the first request and refuses to serve
  // if tables are missing. The DDL ships as auth-schema.sql (generated
  // by scripts/gen_auth_schema.mjs from the SAME options object — rerun
  // it after changing plugins/options). Idempotent; keeps Plesk
  // deployments zero-touch (no `npx auth migrate` step).
  await applyAuthSchema(database);

  return betterAuth(options);
}

/** Lazily constructs (and memoizes) the Better Auth instance. */
export function getAuth() {
  if (authInstance) return Promise.resolve(authInstance);
  if (!authPromise) {
    authPromise = buildAuth().then((auth) => {
      authInstance = auth;
      return auth;
    });
  }
  return authPromise;
}
