<?php

/**
 * Mahtem Cloud API — configuration.
 *
 * SETUP ON PLESK (one time):
 *   1. Plesk → Databases → **Add Database** (type MySQL).
 *      Pick a database name, a database user and a strong password.
 *   2. Copy those three values into the `mysql` block below.
 *      (On Plesk they usually look like:  mahtemco_mahtem  /  mahtemco_api  …)
 *   3. Set `host` to the value Plesk shows for the database server
 *      (usually `localhost`).
 *
 * Nothing else needs editing. All tables are created automatically on the
 * first request.
 *
 * `migrate_from_url` lets existing users of the old Cloudflare Worker
 * (mahtem-api.mahtem.workers.dev) sign in once and have their account,
 * backup and Pro status imported automatically. After a few weeks set it
 * to '' to stop calling the old service.
 */

return [
    // 'mysql' in production. 'sqlite' exists only for local development tests.
    'driver' => 'mysql',

    'mysql' => [
        'host'   => 'localhost',
        'port'   => 3306,
        'dbname' => 'REPLACE_WITH_DB_NAME',
        'user'   => 'REPLACE_WITH_DB_USER',
        'pass'   => 'REPLACE_WITH_DB_PASSWORD',
    ],

    // Local development / testing only (never used when driver = mysql).
    'sqlite_path' => __DIR__ . '/data/mahtem.sqlite',

    // Old Cloudflare Worker — automatic one-time import of existing users.
    // Set to '' once every user has signed in again.
    'migrate_from_url' => 'https://mahtem-api.mahtem.workers.dev',
];
