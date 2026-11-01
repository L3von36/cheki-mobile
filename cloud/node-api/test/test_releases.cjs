// Unit test: src/releases.js caching + stale-if-error behaviour with a
// stubbed global fetch (no network needed). Run: node test/test_releases.cjs
'use strict';

const assert = require('node:assert');
const path = require('node:path');

process.chdir(path.join(__dirname, '..'));
// Fresh module state.
delete require.cache[require.resolve('../src/releases.js')];
const releases = require('../src/releases.js');

const GOOD = {
  tag_name: 'v1.18.12',
  name: 'Mahtem 1.18.12',
  published_at: '2026-10-31T09:00:00Z',
  html_url: 'https://github.com/L3von36/cheki-mobile/releases/tag/v1.18.12',
  assets: [
    { name: 'mahtem-v1.18.12-arm64.apk', size: 22_500_000, download_count: 1200, browser_download_url: 'https://github.com/L3von36/cheki-mobile/releases/download/v1.18.12/mahtem-v1.18.12-arm64.apk' },
    { name: 'mahtem-v1.18.12-arm32.apk', size: 21_000_000, download_count: 340, browser_download_url: 'https://github.com/L3von36/cheki-mobile/releases/download/v1.18.12/mahtem-v1.18.12-arm32.apk' },
    { name: 'mahtem-v1.18.12-universal.apk', size: 33_100_000, download_count: 210, browser_download_url: 'https://github.com/L3von36/cheki-mobile/releases/download/v1.18.12/mahtem-v1.18.12-universal.apk' },
    { name: 'checksums.txt', size: 300, download_count: 5, browser_download_url: 'https://example.com/checksums.txt' },
  ],
};

let mode = 'ok';
global.fetch = async () => {
  if (mode === 'ok') return { ok: true, status: 200, json: async () => GOOD };
  if (mode === 'http403') return { ok: false, status: 403, json: async () => ({}) };
  throw new Error('network down');
};

(async () => {
  // 1) success path → slim shape, non-APK asset filtered
  let got = await releases.getLatest();
  assert.strictEqual(got.stale, false);
  assert.strictEqual(got.release.tag_name, 'v1.18.12');
  assert.strictEqual(got.release.assets.length, 3, 'non-APK assets must be filtered');
  assert.ok(got.release.assets[0].browser_download_url.endsWith('-arm64.apk'));

  // 2) second call inside TTL → served from cache (fetch must not be hit)
  mode = 'explode';
  got = await releases.getLatest();
  assert.strictEqual(got.stale, false, 'TTL cache must not refetch');

  // 3) expire TTL + network down → stale serve, no throw
  const rel = releases; // keep reference
  // reach into internals via a fresh fetch failure after TTL: simulate by
  // resetting the module's internal cache timestamp through a new require.
  const fresh = require('../src/releases.js'); // same instance (cache shared)
  // Age the cache beyond TTL by monkey-patching Date.now briefly.
  const realNow = Date.now;
  Date.now = () => realNow() + 11 * 60 * 1000;
  mode = 'http403';
  got = await fresh.getLatest();
  Date.now = realNow;
  assert.strictEqual(got.stale, true, 'expired cache + GitHub 403 must serve stale');
  assert.strictEqual(got.release.tag_name, 'v1.18.12');

  // 4) kind mapping
  assert.strictEqual(fresh.KIND_SUFFIX.arm64, '-arm64');
  assert.strictEqual(fresh.KIND_SUFFIX.universal, '-universal');

  // 5) slimRelease never crashes on a minimal payload
  const mini = fresh.slimRelease({ tag_name: 'v0', assets: null });
  assert.deepStrictEqual(mini.assets, []);

  console.log('test_releases: all 5 assertions passed');
})().catch((e) => {
  console.error('test_releases FAILED:', e && e.message);
  process.exit(1);
});
