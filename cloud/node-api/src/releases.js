'use strict';

/**
 * Mahtem Cloud API — public release endpoints for the landing page.
 *
 * Mounted BEFORE the bot screen in src/app.js: these are plain marketing
 * endpoints with no user data, and download redirects are ordinary link
 * navigations that cannot send custom headers.
 *
 *   GET /v1/releases/latest        → slim GitHub-release JSON (server-cached)
 *   GET /v1/dl/:kind               → 302 to the current APK on GitHub's CDN
 *                                    (kind: arm64 | arm32 | universal)
 *
 * Why: api.github.com allows only 60 unauthenticated requests/hour per IP,
 * and Ethiopian carriers put thousands of visitors behind one shared IP.
 * This server fetches the release at most once per TTL, keeps the last good
 * payload in memory, and serves it stale (marked `stale: true`) whenever
 * GitHub is unreachable or rate-limited — the landing page and the download
 * links keep working through any GitHub-side outage.
 *
 * The JSON keeps GitHub's field names (tag_name, published_at, assets[]
 * with name/size/download_count/browser_download_url) so the landing page
 * treats this endpoint and the GitHub API identically.
 */

const express = require('express');

const REPO = 'L3von36/cheki-mobile';
const API_URL = `https://api.github.com/repos/${REPO}/releases/latest`;
const RELEASES_PAGE = `https://github.com/${REPO}/releases/latest`;

/** APK filename suffixes per download kind (CI renames assets this way). */
const KIND_SUFFIX = {
  arm64: '-arm64',
  arm32: '-arm32',
  universal: '-universal',
};

/** Freshness window before we re-fetch from GitHub. */
const TTL_MS = 10 * 60 * 1000;

/** In-memory cache: { release, at } + the in-flight fetch (dedupe). */
let cache = { release: null, at: 0 };
let inflight = null;

function slimRelease(raw) {
  const assets = Array.isArray(raw.assets) ? raw.assets : [];
  return {
    tag_name: String(raw.tag_name || ''),
    name: raw.name == null ? null : String(raw.name),
    published_at: raw.published_at == null ? null : String(raw.published_at),
    html_url: raw.html_url ? String(raw.html_url) : RELEASES_PAGE,
    assets: assets
      .filter((a) => a && typeof a.name === 'string' && a.name.endsWith('.apk'))
      .map((a) => ({
        name: a.name,
        size: Number(a.size) || 0,
        download_count: Number(a.download_count) || 0,
        browser_download_url: String(a.browser_download_url || ''),
      })),
  };
}

async function fetchLatest() {
  const upstream = await fetch(API_URL, {
    signal: AbortSignal.timeout(8_000),
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'mahtem-api/1.18 (+https://mahtem.com.et)',
    },
  });
  if (!upstream.ok) {
    throw new Error(`github responded ${upstream.status}`);
  }
  const release = slimRelease(await upstream.json());
  if (!release.tag_name) throw new Error('github payload missing tag_name');
  return release;
}

/** Cached latest release; serves any-age stale data when GitHub fails. */
async function getLatest() {
  const fresh = cache.release && Date.now() - cache.at < TTL_MS;
  if (fresh) return { release: cache.release, stale: false };

  if (!inflight) {
    inflight = fetchLatest()
      .then((release) => {
        cache = { release, at: Date.now() };
        return { release, stale: false };
      })
      .catch((e) => {
        console.error('[mahtem-api] releases:', e && e.message);
        if (cache.release) return { release: cache.release, stale: true };
        return null;
      })
      .finally(() => {
        inflight = null;
      });
  }
  return inflight;
}

function findAsset(release, suffix) {
  const assets = (release && release.assets) || [];
  return assets.find((a) => a.name.includes(suffix)) || null;
}

function router() {
  const r = express.Router();

  r.get('/v1/releases/latest', async (req, res, next) => {
    try {
      const got = await getLatest();
      if (!got) {
        return res.status(503).json({
          error: 'unavailable',
          message: 'Release info is not available yet — try again shortly.',
        });
      }
      // Cache headers so browsers/CDNs also absorb repeat traffic.
      res.setHeader('Cache-Control', 'public, max-age=300');
      res.json({
        ok: true,
        stale: got.stale,
        source: 'github',
        ...got.release,
      });
    } catch (e) {
      next(e);
    }
  });

  r.get('/v1/dl/:kind', async (req, res, next) => {
    try {
      const suffix = KIND_SUFFIX[req.params.kind];
      if (!suffix) {
        return res.status(404).json({
          error: 'bad_kind',
          message: 'kind must be arm64, arm32 or universal.',
        });
      }
      const got = await getLatest();
      const asset = got && findAsset(got.release, suffix);
      if (asset && asset.browser_download_url) {
        // Asset URLs are stable per release — safe to redirect even when
        // the answer came from an old cached snapshot.
        return res.redirect(302, asset.browser_download_url);
      }
      // Nothing cached yet (or GitHub removed the asset): send the visitor
      // to the releases page rather than dead-ending.
      return res.redirect(302, RELEASES_PAGE);
    } catch (e) {
      next(e);
    }
  });

  return r;
}

module.exports = { router, getLatest, slimRelease, KIND_SUFFIX };
