'use strict';

/**
 * Mahtem Cloud API — startup file (Passenger / Plesk "Application Startup
 * File"). Passenger injects the port through process.env.PORT; locally we
 * default to 8080.
 *
 *   node server.js            → http://localhost:8080
 *   DB_DRIVER=sqlite node server.js   (local testing without MySQL)
 */

const app = require('./src/app');
const db = require('./src/db');

const PORT = Number(process.env.PORT) || 8080;

// Warm the database connection + schema as early as possible so the first
// real request never pays the cold-start cost.
db.ensureReady().catch((e) => {
  console.error('[mahtem-api] database not ready:', e && e.message);
});

const server = app.listen(PORT, () => {
  console.log(`[mahtem-api] v1.15.0-node listening on :${PORT} (driver: ${db.driver})`);
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 5000).unref();
  });
}

module.exports = server;
