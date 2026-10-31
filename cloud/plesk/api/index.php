<?php
declare(strict_types=1);

/**
 * Mahtem Cloud API (v1.15.0-plesk) — Zero-Knowledge OAuth 2.1 / JWT backend.
 *
 * PHP 8.0+ / MySQL port of `cloud/worker.js` (Cloudflare Worker) designed for
 * shared Plesk hosting (Linux + PHP + MySQL). Single front controller, zero
 * external Composer dependencies: only PDO and curl are required.
 *
 * PRIVACY CONTRACT (Zero-Knowledge, identical to the Worker):
 *   * Client derives `authKey = PBKDF2(password, "mahtem-cloud-auth-v1")` on-device.
 *     The raw password never reaches this server.
 *   * Stored `identifierHash = SHA-256(identifier)` — never raw email/phone.
 *   * Vault (history backup) is AES-256-GCM encrypted on-device. This server
 *     cannot decrypt it and never sees the vault key.
 *
 * TOKEN ARCHITECTURE (identical to the Worker):
 *   * Short-lived access token: JWT HS256, 15 minutes, stateless verification.
 *   * Rotating single-use refresh token: 30 days, reuse-detecting (atomic
 *     delete-then-issue, stronger than the KV original).
 *   * JWT secret auto-provisioned into the `config` table on first use.
 *
 * MIGRATION: accounts, vaults and Pro entitlements created on the original
 * Cloudflare Worker (mahtem-api.mahtem.workers.dev) are imported automatically
 * on the user's first sign-in, because both systems share the exact same
 * hashing scheme (see `migrate_import_from_worker()`).
 *
 * Route map (identical request/response shapes to the Worker):
 *   GET    /v1/health           — liveness probe
 *   POST   /v1/accounts         — create account          {identifierHash, authKey}
 *   POST   /v1/accounts/lookup  — does an account exist?  {identifierHash}
 *   POST   /v1/session          — sign in                 {identifierHash, authKey}
 *   POST   /v1/session/refresh  — rotate refresh token    {refreshToken}
 *   GET    /v1/session          — validate Bearer JWT
 *   DELETE /v1/session          — revoke refresh token    {refreshToken?}
 *   POST   /v1/auth/revoke      — alias of DELETE /v1/session
 *   PUT    /v1/vault            — encrypted backup        {blob, revision, baseRevision?}
 *   GET    /v1/vault            — fetch backup            ?sinceRevision=N
 *   DELETE /v1/vault            — remove backup
 *   POST   /v1/pro/claim        — monthly receipt claim   {receiptHash, amountEtb, planDays}
 *   GET    /v1/pro/status       — Pro expiry
 *   POST   /v1/relay            — geo-block relay         {bank, url} (allowlisted)
 *
 * Every request must carry the `X-Mahtem-Client` header (cheap bot screen).
 */

const MAHTEM_API_VERSION   = '1.15.0-plesk';
const ACCESS_TOKEN_TTL     = 900;                 // 15 minutes
const REFRESH_TOKEN_TTL    = 30 * 24 * 3600;      // 30 days (seconds)
const PLAN_DAYS            = 31;
const PLAN_AMOUNT_ETB      = 300;
const MAX_BLOB_CHARS       = 4000000;             // base64 vault ciphertext cap
const MAX_BODY_BYTES       = 12 * 1024 * 1024;    // hard JSON body cap

date_default_timezone_set('UTC');
error_reporting(E_ALL);
ini_set('display_errors', '0'); // never leak diagnostics to clients

// MAHTEM_CONFIG_FILE lets local tests point at an alternate config
// (e.g. the SQLite driver) without touching the deployed config.php.
$configFile = getenv('MAHTEM_CONFIG_FILE');
$MAHTEM_CONFIG = require ($configFile && is_file($configFile)) ? $configFile : __DIR__ . '/config.php';

/* ────────────────────────────────────────────────────────────────────────────
 * Response helpers (mirror the Worker's `json` / `err`)
 * ──────────────────────────────────────────────────────────────────────── */

function send_cors_headers(): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET,POST,PUT,DELETE,OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type,Authorization,X-Mahtem-Client');
    header('X-Content-Type-Options: nosniff');
}

function json_out($data, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    send_cors_headers();
    echo json_encode(
        $data,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
    );
    exit;
}

function err_out(string $code, int $status, string $message): void
{
    json_out(['error' => $code, 'message' => $message], $status);
}

function options_204(): void
{
    http_response_code(204);
    send_cors_headers();
    exit;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Crypto / validation helpers
 * ──────────────────────────────────────────────────────────────────────── */

function is_hex64($s): bool
{
    return is_string($s) && (bool)preg_match('/^[0-9a-f]{64}$/', $s);
}

/** The Worker's isBase64(): a length check — the client always emits real base64. */
function is_base64ish($s): bool
{
    return is_string($s) && strlen($s) > 16 && strlen($s) <= MAX_BLOB_CHARS;
}

function uuid4(): string
{
    $b = random_bytes(16);
    $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
    $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($b), 4));
}

function now_ms(): int
{
    return (int)round(microtime(true) * 1000);
}

function b64url_encode(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

/** Strict base64url decode; null on any malformed input. */
function b64url_decode_strict(string $s): ?string
{
    $b = strtr($s, '-_', '+/');
    $pad = strlen($b) % 4;
    if ($pad === 1) return null; // impossible base64 length
    if ($pad !== 0) $b .= str_repeat('=', 4 - $pad);
    $raw = base64_decode($b, true);
    return $raw === false ? null : $raw;
}

/* ── JWT engine (HS256) ── */

function jwt_sign(string $userId, string $secret): array
{
    $header = b64url_encode((string)json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $now = time();
    $exp = $now + ACCESS_TOKEN_TTL;
    $payload = b64url_encode((string)json_encode([
        'sub'  => $userId,
        'iss'  => 'mahtem-api',
        'type' => 'access',
        'iat'  => $now,
        'exp'  => $exp,
        'jti'  => uuid4(),
    ]));
    $sig = b64url_encode(hash_hmac('sha256', $header . '.' . $payload, $secret, true));
    return [
        'jwt'       => $header . '.' . $payload . '.' . $sig,
        'expiresIn' => ACCESS_TOKEN_TTL,
        'expiresAt' => $exp * 1000,
    ];
}

function jwt_verify(string $token, string $secret): array
{
    $parts = explode('.', $token);
    if (count($parts) !== 3) return ['ok' => false, 'error' => 'invalid'];
    [$h, $p, $s] = $parts;

    $expected = hash_hmac('sha256', $h . '.' . $p, $secret, true);
    $sig = b64url_decode_strict($s);
    if ($sig === null || !hash_equals($expected, $sig)) {
        return ['ok' => false, 'error' => 'invalid_signature'];
    }
    $payload = json_decode((string)b64url_decode_strict($p), true);
    if (!is_array($payload)) return ['ok' => false, 'error' => 'malformed'];

    $now = time();
    if (isset($payload['exp']) && is_numeric($payload['exp']) && (int)$payload['exp'] < $now) {
        return ['ok' => false, 'error' => 'expired', 'payload' => $payload];
    }
    return ['ok' => true, 'payload' => $payload];
}

/** Server-side pepper for authKey — identical formula to the Worker. */
function hash_auth_key(string $authKey, string $userId): string
{
    return hash('sha256', $userId . ':' . $authKey);
}

/* ────────────────────────────────────────────────────────────────────────────
 * Request helpers
 * ──────────────────────────────────────────────────────────────────────── */

function read_json_body(): ?array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '' || strlen($raw) > MAX_BODY_BYTES) return null;
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : null;
}

function client_header_present(): bool
{
    if (!empty($_SERVER['HTTP_X_MAHTEM_CLIENT'])) return true;
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            if (strcasecmp((string)$name, 'X-Mahtem-Client') === 0 && (string)$value !== '') {
                return true;
            }
        }
    }
    return false;
}

function bearer_token(): string
{
    foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $key) {
        $v = $_SERVER[$key] ?? '';
        if (is_string($v) && stripos($v, 'bearer ') === 0) {
            return trim(substr($v, 7));
        }
    }
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            if (strcasecmp((string)$name, 'Authorization') === 0
                && stripos((string)$value, 'bearer ') === 0) {
                return trim(substr((string)$value, 7));
            }
        }
    }
    return '';
}

/**
 * Resolves the API route path regardless of where this app is mounted
 * (…/httpdocs/api → /v1/…). Falls back to slicing from the first /v1/.
 */
function request_path(): string
{
    $uri = $_SERVER['REQUEST_URI'] ?? '/';
    $path = parse_url($uri, PHP_URL_PATH);
    if (!is_string($path) || $path === '') $path = '/';

    $docroot = realpath($_SERVER['DOCUMENT_ROOT'] ?? '') ?: '';
    $dir = str_replace('\\', '/', __DIR__);
    if ($docroot !== '' && strpos($dir, $docroot) === 0) {
        $base = rtrim(substr($dir, strlen($docroot)), '/');
        if ($base !== '' && strpos($path, $base) === 0) {
            $path = substr($path, strlen($base));
        }
    }
    if (strpos($path, '/v1/') !== 0) {
        $pos = strpos($path, '/v1/');
        if ($pos !== false) $path = substr($path, $pos);
    }
    return $path === '' ? '/' : $path;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Database (MySQL on Plesk; SQLite driver kept for local development tests)
 * ──────────────────────────────────────────────────────────────────────── */

function db_connect(array $config): PDO
{
    $driver = $config['driver'] ?? 'mysql';
    $opts = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ];

    if ($driver === 'sqlite') {
        $path = $config['sqlite_path'] ?? (__DIR__ . '/data/mahtem.sqlite');
        $dir = dirname($path);
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        $pdo = new PDO('sqlite:' . $path, null, null, $opts);
        $pdo->exec('PRAGMA journal_mode=WAL');
        $pdo->exec('PRAGMA busy_timeout=5000');
        return $pdo;
    }

    $m = $config['mysql'];
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
        $m['host'],
        (int)($m['port'] ?? 3306),
        $m['dbname']
    );
    $pdo = new PDO($dsn, (string)$m['user'], (string)$m['pass'], $opts);
    try {
        $pdo->exec("SET sql_mode='STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION'");
    } catch (Throwable $e) {
        /* non-fatal */
    }
    return $pdo;
}

function ensure_schema(PDO $pdo, string $driver): void
{
    $ready = false;
    try {
        $st = $pdo->query("SELECT v FROM `config` WHERE k = 'schema'");
        $ready = $st !== false && $st->fetch(PDO::FETCH_ASSOC) !== false;
    } catch (Throwable $e) {
        $ready = false;
    }
    if ($ready) return;

    $mysql = ($driver === 'mysql');
    $tables = [
        "`config` (
            `k` VARCHAR(64) NOT NULL PRIMARY KEY,
            `v` TEXT NOT NULL
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
        "`accounts` (
            `identifier_hash` CHAR(64) NOT NULL PRIMARY KEY,
            `user_id`         CHAR(36) NOT NULL,
            `auth_hash`       CHAR(64) NOT NULL,
            `created_at`      BIGINT NOT NULL,
            " . ($mysql ? 'UNIQUE KEY `ux_accounts_user` (`user_id`)'
                        : 'UNIQUE (`user_id`)') . "
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
        "`refresh_tokens` (
            `token`      CHAR(64) NOT NULL PRIMARY KEY,
            `user_id`    CHAR(64) NOT NULL,
            `exp`        BIGINT NOT NULL,
            `created_at` BIGINT NOT NULL
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
        "`vaults` (
            `user_id`    CHAR(36) NOT NULL PRIMARY KEY,
            `blob`       " . ($mysql ? 'MEDIUMTEXT' : 'TEXT') . " NOT NULL,
            `revision`   BIGINT NOT NULL,
            `updated_at` BIGINT NOT NULL
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
        "`pro_receipts` (
            `receipt_hash` CHAR(64) NOT NULL PRIMARY KEY,
            `user_id`      CHAR(64) NOT NULL,
            `amount_etb`   INTEGER NOT NULL,
            `plan_days`    INTEGER NOT NULL,
            `paid_at_ms`   BIGINT NULL,
            `claimed_at`   BIGINT NOT NULL,
            `expires_at`   BIGINT NOT NULL
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
        "`pro_status` (
            `user_id`    CHAR(36) NOT NULL PRIMARY KEY,
            `expires_at` BIGINT NOT NULL,
            `updated_at` BIGINT NOT NULL
        )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''),
    ];
    foreach ($tables as $ddl) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS ' . $ddl);
    }
    try {
        $pdo->exec("INSERT " . ($mysql ? 'IGNORE INTO' : 'OR IGNORE INTO')
            . " `config` (`k`, `v`) VALUES ('schema', '1')");
    } catch (Throwable $e) {
        /* concurrent first request already inserted it */
    }
}

function insert_ignore_sql(string $driver): string
{
    return $driver === 'mysql' ? 'INSERT IGNORE INTO' : 'INSERT OR IGNORE INTO';
}

/** Connect + ensure schema once per request (cached in a static). */
function db_ready(array $config): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;
    $pdo = db_connect($config);
    ensure_schema($pdo, (string)($config['driver'] ?? 'mysql'));
    return $pdo;
}

/** JWT signing secret: env override → config table → auto-provision. */
function get_jwt_secret(PDO $pdo, string $driver): string
{
    $env = getenv('MAHTEM_JWT_SECRET');
    if (is_string($env) && strlen($env) >= 32) return $env;

    $st = $pdo->query("SELECT v FROM `config` WHERE k = 'jwt_secret'");
    $row = $st ? $st->fetch(PDO::FETCH_ASSOC) : false;
    if (is_array($row) && isset($row['v']) && is_string($row['v']) && strlen($row['v']) >= 32) {
        return $row['v'];
    }
    $secret = bin2hex(random_bytes(32));
    $pdo->prepare(insert_ignore_sql($driver) . " `config` (`k`, `v`) VALUES ('jwt_secret', ?)")
        ->execute([$secret]);
    return $secret;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Sessions
 * ──────────────────────────────────────────────────────────────────────── */

function issue_session_tokens(PDO $pdo, string $driver, string $userId): array
{
    $jwt = jwt_sign($userId, get_jwt_secret($pdo, $driver));
    $refresh = bin2hex(random_bytes(32));
    $exp = time() + REFRESH_TOKEN_TTL;
    $pdo->prepare("INSERT INTO `refresh_tokens` (`token`, `user_id`, `exp`, `created_at`) VALUES (?, ?, ?, ?)")
        ->execute([$refresh, $userId, $exp, now_ms()]);
    // Opportunistic cleanup of expired refresh tokens (~5% of logins).
    if (random_int(1, 20) === 1) {
        $pdo->exec('DELETE FROM `refresh_tokens` WHERE `exp` < ' . time());
    }
    return [
        'accessToken'  => $jwt['jwt'],
        'refreshToken' => $refresh,
        'tokenType'    => 'Bearer',
        'expiresIn'    => $jwt['expiresIn'],
        'expiresAt'    => $jwt['expiresAt'],
        'sessionToken' => $jwt['jwt'], // backwards-compatible field
        'userId'       => $userId,
    ];
}

/**
 * Bearer-token session check. JWTs are verified statelessly; the legacy
 * `sess:` KV tokens of the old Worker are intentionally not carried over —
 * those clients simply re-authenticate once with their stored credentials.
 */
function require_session(PDO $pdo, string $driver): array
{
    $token = bearer_token();
    if ($token === '') {
        return ['ok' => false, 'status' => 401, 'error' => 'missing_token',
                'message' => 'Session token required.'];
    }

    if (substr_count($token, '.') === 2) {
        $v = jwt_verify($token, get_jwt_secret($pdo, $driver));
        if ($v['ok'] && isset($v['payload']['sub']) && is_string($v['payload']['sub'])) {
            return [
                'ok'     => true,
                'token'  => $token,
                'userId' => $v['payload']['sub'],
                'exp'    => isset($v['payload']['exp']) ? (int)$v['payload']['exp'] : null,
            ];
        }
        if (($v['error'] ?? '') === 'expired') {
            return ['ok' => false, 'status' => 401, 'error' => 'token_expired',
                    'message' => 'Access token has expired. Use /v1/session/refresh to renew.'];
        }
        return ['ok' => false, 'status' => 401, 'error' => 'invalid_token',
                'message' => 'Access token is invalid or signature check failed.'];
    }

    return ['ok' => false, 'status' => 401, 'error' => 'unauthorized',
            'message' => 'Session missing or expired.'];
}

/* ────────────────────────────────────────────────────────────────────────────
 * Migration from the original Cloudflare Worker
 * ──────────────────────────────────────────────────────────────────────── */

function http_json(string $method, string $url, ?array $body, ?string $bearer, int $timeout): ?array
{
    if (!function_exists('curl_init')) return null;
    $ch = curl_init($url);
    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT        => $timeout,
        CURLOPT_HTTPHEADER     => ['X-Mahtem-Client: mahtem-android'],
    ];
    if ($bearer !== null && $bearer !== '') {
        $opts[CURLOPT_HTTPHEADER][] = 'Authorization: Bearer ' . $bearer;
    }
    if ($method === 'POST') {
        $opts[CURLOPT_POST] = true;
        $opts[CURLOPT_POSTFIELDS] = (string)json_encode($body ?? []);
        $opts[CURLOPT_HTTPHEADER][] = 'Content-Type: application/json';
    }
    curl_setopt_array($ch, $opts);
    $text = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $err = curl_errno($ch);
    curl_close($ch);
    if ($err !== 0 || !is_string($text)) return null;
    return ['status' => $status, 'body' => $text];
}

/**
 * One-time import of a user's data from the original Cloudflare Worker.
 * Runs only after the OLD worker proved the same credentials, so this can
 * never be used to pull someone else's data. Never throws.
 */
function migrate_import_from_worker(
    PDO $pdo,
    string $driver,
    string $baseUrl,
    string $identifierHash,
    string $authKey
): ?string {
    try {
        $base = rtrim($baseUrl, '/');
        $resp = http_json('POST', $base . '/v1/session',
            ['identifierHash' => $identifierHash, 'authKey' => $authKey], null, 15);
        if ($resp === null || $resp['status'] !== 200) return null;
        $data = json_decode($resp['body'], true);
        if (!is_array($data)) return null;
        $userId = $data['userId'] ?? null;
        if (!is_string($userId) || $userId === '' || strlen($userId) > 64) return null;

        $now = now_ms();
        $authHash = hash_auth_key($authKey, $userId);
        $pdo->prepare(insert_ignore_sql($driver)
            . " `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `created_at`) VALUES (?, ?, ?, ?)")
            ->execute([$identifierHash, $userId, $authHash, $now]);

        // Vault backup (ciphertext only).
        $accessToken = is_string($data['accessToken'] ?? null) ? $data['accessToken'] : null;
        $vresp = http_json('GET', $base . '/v1/vault', null, $accessToken, 15);
        if ($vresp !== null && $vresp['status'] === 200) {
            $v = json_decode($vresp['body'], true);
            if (is_array($v) && is_base64ish($v['blob'] ?? null)
                && isset($v['revision']) && is_numeric($v['revision']) && (int)$v['revision'] > 0) {
                $updatedAt = is_numeric($v['updatedAt'] ?? null) ? (int)$v['updatedAt'] : $now;
                $pdo->prepare(insert_ignore_sql($driver)
                    . " `vaults` (`user_id`, `blob`, `revision`, `updated_at`) VALUES (?, ?, ?, ?)")
                    ->execute([$userId, (string)$v['blob'], (int)$v['revision'], $updatedAt]);
            }
        }

        // Pro entitlement.
        $presp = http_json('GET', $base . '/v1/pro/status', null, $accessToken, 15);
        if ($presp !== null && $presp['status'] === 200) {
            $p = json_decode($presp['body'], true);
            if (is_array($p) && isset($p['expiresAt']) && is_numeric($p['expiresAt'])
                && (int)$p['expiresAt'] > 0) {
                $pdo->prepare(insert_ignore_sql($driver)
                    . " `pro_status` (`user_id`, `expires_at`, `updated_at`) VALUES (?, ?, ?)")
                    ->execute([$userId, (int)$p['expiresAt'], $now]);
            }
        }

        // Keep an in-flight refresh token working across the switch.
        if (isset($data['refreshToken']) && is_string($data['refreshToken'])
            && preg_match('/^[0-9a-f]{32,128}$/', $data['refreshToken'])) {
            $pdo->prepare(insert_ignore_sql($driver)
                . " `refresh_tokens` (`token`, `user_id`, `exp`, `created_at`) VALUES (?, ?, ?, ?)")
                ->execute([$data['refreshToken'], $userId, time() + REFRESH_TOKEN_TTL, $now]);
        }
        return $userId;
    } catch (Throwable $e) {
        return null; // migration must never break sign-in
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Routing
 * ──────────────────────────────────────────────────────────────────────── */

$driver = (string)($MAHTEM_CONFIG['driver'] ?? 'mysql');
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path   = request_path();

if ($method === 'OPTIONS') {
    options_204();
}

// Cheap bot screen — the app always sends this header.
if (!client_header_present()) {
    err_out('client_required', 400, 'Missing X-Mahtem-Client header.');
}

try {
    switch ($method . ' ' . $path) {

        case 'GET /v1/health': {
            $dbOk = true;
            try {
                db_ready($MAHTEM_CONFIG)->query('SELECT 1');
            } catch (Throwable $e) {
                $dbOk = false;
            }
            json_out([
                'ok'      => true,
                'service' => 'mahtem-api',
                'auth'    => 'OAuth 2.0 / JWT (HS256) + Zero-Knowledge',
                'version' => MAHTEM_API_VERSION,
                'db'      => $dbOk,
                'time'    => gmdate('Y-m-d\TH:i:s\Z'),
            ]);
        }

        /* ── account creation ─────────────────────────────────────────── */

        case 'POST /v1/accounts': {
            $body = read_json_body();
            $identifierHash = $body['identifierHash'] ?? null;
            $authKey = $body['authKey'] ?? null;
            if (!is_hex64($identifierHash) || !is_hex64($authKey)) {
                err_out('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.');
            }
            $pdo = db_ready($MAHTEM_CONFIG);

            $st = $pdo->prepare("SELECT `user_id` FROM `accounts` WHERE `identifier_hash` = ?");
            $st->execute([$identifierHash]);
            if ($st->fetch(PDO::FETCH_ASSOC)) {
                err_out('exists', 409, 'An account with this identifier already exists.');
            }

            $id = uuid4();
            $authHash = hash_auth_key((string)$authKey, $id);
            try {
                $pdo->prepare("INSERT INTO `accounts` (`identifier_hash`, `user_id`, `auth_hash`, `created_at`) VALUES (?, ?, ?, ?)")
                    ->execute([$identifierHash, $id, $authHash, now_ms()]);
            } catch (PDOException $e) {
                if (($e->errorInfo[0] ?? '') === '23000') {
                    err_out('exists', 409, 'An account with this identifier already exists.');
                }
                throw $e;
            }
            json_out(['userId' => $id], 201);
        }

        case 'POST /v1/accounts/lookup': {
            $body = read_json_body();
            $identifierHash = $body['identifierHash'] ?? null;
            if (!is_hex64($identifierHash)) {
                err_out('bad_input', 400, 'identifierHash must be a 64-hex digest.');
            }
            $pdo = db_ready($MAHTEM_CONFIG);
            $st = $pdo->prepare("SELECT `created_at` FROM `accounts` WHERE `identifier_hash` = ?");
            $st->execute([$identifierHash]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) json_out(['exists' => false]);
            json_out(['exists' => true, 'createdAt' => (int)$row['created_at']]);
        }

        /* ── login / session creation ─────────────────────────────────── */

        case 'POST /v1/session':
        case 'POST /v1/auth/token': {
            $body = read_json_body();
            $identifierHash = $body['identifierHash'] ?? null;
            $authKey = $body['authKey'] ?? null;
            if (!is_hex64($identifierHash) || !is_hex64($authKey)) {
                err_out('bad_input', 400, 'identifierHash and authKey must be 64-hex digests.');
            }
            $pdo = db_ready($MAHTEM_CONFIG);

            $st = $pdo->prepare("SELECT `user_id`, `auth_hash` FROM `accounts` WHERE `identifier_hash` = ?");
            $st->execute([$identifierHash]);
            $record = $st->fetch(PDO::FETCH_ASSOC);

            // First sign-in after the hosting switch: import from the old Worker.
            if (!$record) {
                $migrateUrl = trim((string)($MAHTEM_CONFIG['migrate_from_url'] ?? ''));
                if ($migrateUrl !== '') {
                    migrate_import_from_worker($pdo, $driver, $migrateUrl, (string)$identifierHash, (string)$authKey);
                    $st->execute([$identifierHash]);
                    $record = $st->fetch(PDO::FETCH_ASSOC);
                }
            }
            if (!$record) {
                err_out('no_account', 404, 'No account for this identifier.');
            }

            $authHash = hash_auth_key((string)$authKey, (string)$record['user_id']);
            if (!hash_equals((string)$record['auth_hash'], $authHash)) {
                err_out('bad_credentials', 401, 'Wrong identifier or password.');
            }

            json_out(issue_session_tokens($pdo, $driver, (string)$record['user_id']));
        }

        /* ── refresh token rotation ───────────────────────────────────── */

        case 'POST /v1/session/refresh':
        case 'POST /v1/auth/refresh': {
            $body = read_json_body();
            $refreshToken = $body['refreshToken'] ?? null;
            if (!is_string($refreshToken) || $refreshToken === '') {
                err_out('bad_input', 400, 'refreshToken string is required.');
            }
            $pdo = db_ready($MAHTEM_CONFIG);

            $st = $pdo->prepare("SELECT `user_id`, `exp` FROM `refresh_tokens` WHERE `token` = ?");
            $st->execute([$refreshToken]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                err_out('invalid_grant', 401, 'Refresh token is invalid, expired, or already used.');
            }
            if (((int)$row['exp']) < time()) {
                $pdo->prepare("DELETE FROM `refresh_tokens` WHERE `token` = ?")->execute([$refreshToken]);
                err_out('invalid_grant', 401, 'Refresh token has expired.');
            }

            // Atomic single-use rotation: only the first caller wins.
            $del = $pdo->prepare("DELETE FROM `refresh_tokens` WHERE `token` = ?");
            $del->execute([$refreshToken]);
            if ($del->rowCount() === 0) {
                err_out('invalid_grant', 401, 'Refresh token is invalid, expired, or already used.');
            }

            json_out(issue_session_tokens($pdo, $driver, (string)$row['user_id']));
        }

        /* ── session revocation ───────────────────────────────────────── */

        case 'DELETE /v1/session':
        case 'POST /v1/auth/revoke': {
            $body = read_json_body();
            $refreshToken = is_array($body) ? ($body['refreshToken'] ?? null) : null;
            if (is_string($refreshToken) && $refreshToken !== '') {
                $pdo = db_ready($MAHTEM_CONFIG);
                $pdo->prepare("DELETE FROM `refresh_tokens` WHERE `token` = ?")->execute([$refreshToken]);
            }
            json_out(['ok' => true]);
        }

        /* ── check current session ────────────────────────────────────── */

        case 'GET /v1/session':
        case 'GET /v1/auth/me': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            json_out(['userId' => $session['userId'], 'exp' => $session['exp'], 'ok' => true]);
        }

        /* ── encrypted vault backup ───────────────────────────────────── */

        case 'PUT /v1/vault': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            $body = read_json_body();
            $blob = $body['blob'] ?? null;
            $revision = $body['revision'] ?? null;
            $revisionIsInt = is_int($revision)
                || (is_float($revision) && floor($revision) === $revision);
            if (!is_base64ish($blob) || !$revisionIsInt || (int)$revision <= 0) {
                err_out('bad_input', 400, 'blob must be base64 and revision a positive number.');
            }
            $revision = (int)$revision;
            $baseRevision = array_key_exists('baseRevision', $body) ? $body['baseRevision'] : null;
            $userId = (string)$session['userId'];

            $pdo->beginTransaction();
            try {
                $sel = $pdo->prepare("SELECT `revision`, `updated_at` FROM `vaults` WHERE `user_id` = ?"
                    . ($driver === 'mysql' ? ' FOR UPDATE' : ''));
                $sel->execute([$userId]);
                $existing = $sel->fetch(PDO::FETCH_ASSOC);

                // Optimistic concurrency check (identical semantics to the Worker).
                if ($existing && $baseRevision !== null && is_numeric((string)$baseRevision)) {
                    if ((int)$existing['revision'] > (int)$baseRevision) {
                        $pdo->rollBack();
                        json_out([
                            'error'     => 'conflict',
                            'revision'  => (int)$existing['revision'],
                            'updatedAt' => (int)$existing['updated_at'],
                        ], 409);
                    }
                }

                $updatedAt = now_ms();
                if ($existing) {
                    $pdo->prepare("UPDATE `vaults` SET `blob` = ?, `revision` = ?, `updated_at` = ? WHERE `user_id` = ?")
                        ->execute([(string)$blob, $revision, $updatedAt, $userId]);
                } else {
                    $pdo->prepare("INSERT INTO `vaults` (`user_id`, `blob`, `revision`, `updated_at`) VALUES (?, ?, ?, ?)")
                        ->execute([$userId, (string)$blob, $revision, $updatedAt]);
                }
                $pdo->commit();
                json_out(['ok' => true, 'revision' => $revision, 'updatedAt' => $updatedAt]);
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                throw $e;
            }
        }

        case 'GET /v1/vault': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            $st = $pdo->prepare("SELECT `blob`, `revision`, `updated_at` FROM `vaults` WHERE `user_id` = ?");
            $st->execute([(string)$session['userId']]);
            $vault = $st->fetch(PDO::FETCH_ASSOC);
            if (!$vault) err_out('empty', 404, 'No vault stored yet.');

            $since = $_GET['sinceRevision'] ?? null;
            if ($since !== null && is_numeric((string)$since)
                && (float)$since === (float)$vault['revision']) {
                json_out(['notModified' => true, 'revision' => (int)$vault['revision']]);
            }
            json_out([
                'blob'      => (string)$vault['blob'],
                'revision'  => (int)$vault['revision'],
                'updatedAt' => (int)$vault['updated_at'],
            ]);
        }

        case 'DELETE /v1/vault': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            $pdo->prepare("DELETE FROM `vaults` WHERE `user_id` = ?")->execute([(string)$session['userId']]);
            json_out(['ok' => true]);
        }

        /* ── monthly Pro receipt ledger ─────────────────────────────────
         * The app verifies the Telebirr receipt first, then submits only its
         * SHA-256 fingerprint through the user's normal session. The primary
         * key on receipt_hash makes the "one receipt, one account" rule atomic.
         */
        case 'POST /v1/pro/claim': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            $body = read_json_body();
            $receiptHash = $body['receiptHash'] ?? null;
            $amountEtb = is_numeric($body['amountEtb'] ?? null) ? (float)$body['amountEtb'] : 0.0;
            $planDays = is_numeric($body['planDays'] ?? null) ? (float)$body['planDays'] : 0.0;
            $paidAtMs = is_numeric($body['paidAtMs'] ?? null) ? (int)$body['paidAtMs'] : null;
            $userId = (string)$session['userId'];

            if (!is_hex64($receiptHash) || $amountEtb !== 300.0 || $planDays !== 31.0) {
                err_out('bad_input', 400, 'A monthly claim requires a receipt hash, 300 ETB, and 31 days.');
            }

            $now = now_ms();
            $st = $pdo->prepare("SELECT `expires_at` FROM `pro_status` WHERE `user_id` = ?");
            $st->execute([$userId]);
            $cur = $st->fetch(PDO::FETCH_ASSOC);
            $currentExpiry = $cur ? (int)$cur['expires_at'] : 0;
            $expiresAt = max($now, $currentExpiry) + PLAN_DAYS * 24 * 3600 * 1000;

            try {
                $pdo->prepare(
                    "INSERT INTO `pro_receipts`
                     (`receipt_hash`, `user_id`, `amount_etb`, `plan_days`, `paid_at_ms`, `claimed_at`, `expires_at`)
                     VALUES (?, ?, ?, ?, ?, ?, ?)"
                )->execute([
                    (string)$receiptHash, $userId, (int)$amountEtb, (int)$planDays,
                    $paidAtMs, $now, $expiresAt,
                ]);
            } catch (PDOException $e) {
                if (($e->errorInfo[0] ?? '') === '23000') {
                    $st = $pdo->prepare("SELECT `user_id`, `expires_at` FROM `pro_receipts` WHERE `receipt_hash` = ?");
                    $st->execute([(string)$receiptHash]);
                    $existing = $st->fetch(PDO::FETCH_ASSOC);
                    if ($existing && (string)$existing['user_id'] !== $userId) {
                        err_out('receipt_used', 409, 'This payment has already been used by another account.');
                    }
                    $expiresAtExisting = $existing ? (int)$existing['expires_at'] : 0;
                    json_out([
                        'ok'             => true,
                        'alreadyClaimed' => true,
                        'expiresAt'      => $expiresAtExisting > 0 ? $expiresAtExisting : $now,
                    ]);
                }
                throw $e;
            }

            if ($driver === 'mysql') {
                $pdo->prepare(
                    "INSERT INTO `pro_status` (`user_id`, `expires_at`, `updated_at`) VALUES (?, ?, ?)
                     ON DUPLICATE KEY UPDATE `expires_at` = VALUES(`expires_at`), `updated_at` = VALUES(`updated_at`)"
                )->execute([$userId, $expiresAt, $now]);
            } else {
                $pdo->prepare(
                    "INSERT INTO `pro_status` (`user_id`, `expires_at`, `updated_at`) VALUES (?, ?, ?)
                     ON CONFLICT(`user_id`) DO UPDATE SET `expires_at` = excluded.`expires_at`, `updated_at` = excluded.`updated_at`"
                )->execute([$userId, $expiresAt, $now]);
            }

            json_out(['ok' => true, 'alreadyClaimed' => false, 'expiresAt' => $expiresAt]);
        }

        case 'GET /v1/pro/status': {
            $pdo = db_ready($MAHTEM_CONFIG);
            $session = require_session($pdo, $driver);
            if (!$session['ok']) {
                err_out($session['error'], $session['status'], $session['message']);
            }
            $st = $pdo->prepare("SELECT `expires_at` FROM `pro_status` WHERE `user_id` = ?");
            $st->execute([(string)$session['userId']]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) json_out(['entitled' => false, 'expiresAt' => null]);
            $expiresAt = (int)$row['expires_at'];
            json_out(['entitled' => $expiresAt > now_ms(), 'expiresAt' => $expiresAt]);
        }

        /* ── geo-block relay ────────────────────────────────────────────
         * Telebirr and M-Pesa receipt endpoints refuse some client IPs.
         * This server fetches the receipt page on the user's behalf — strictly
         * allowlisted hosts, GET only, never an open proxy. Running on
         * Ethiopian (EthioTelecom) infrastructure makes this reach both hosts
         * directly.
         */
        case 'POST /v1/relay': {
            $body = read_json_body();
            $bank = is_array($body) ? ($body['bank'] ?? null) : null;
            $target = is_array($body) ? ($body['url'] ?? null) : null;

            $allowedHosts = [
                'telebirr' => ['transactioninfo.ethiotelecom.et'],
                'mpesa'    => ['m-pesabusiness.safaricom.et'],
            ];
            if (!is_string($bank) || !array_key_exists($bank, $allowedHosts)) {
                err_out('bad_bank', 400, 'bank must be telebirr or mpesa.');
            }
            if (!is_string($target) || $target === '') {
                err_out('bad_url', 400, 'url must be an absolute URL.');
            }
            $u = parse_url($target);
            if ($u === false || !isset($u['scheme'], $u['host']) || $u['scheme'] !== 'https') {
                err_out('bad_url', 400, 'url must be an absolute URL.');
            }
            if (!in_array(strtolower((string)$u['host']), $allowedHosts[$bank], true)) {
                err_out('bad_host', 400, 'url host is not relay-allowed.');
            }

            if (!function_exists('curl_init')) {
                err_out('relay_failed', 502, 'Could not reach the bank.');
            }
            @set_time_limit(20);
            $ch = curl_init($target);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_MAXREDIRS      => 5,
                CURLOPT_CONNECTTIMEOUT => 5,
                CURLOPT_TIMEOUT        => 12,
                CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                CURLOPT_HTTPHEADER     => ['Accept: text/html,application/json,*/*'],
            ]);
            $text = curl_exec($ch);
            if ($text === false) {
                curl_close($ch);
                err_out('relay_failed', 502, 'Could not reach the bank.');
            }
            $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            curl_close($ch);
            if (!is_string($text)) $text = '';
            if (strlen($text) > 1000000) $text = substr($text, 0, 1000000);
            json_out(['ok' => true, 'status' => $status, 'body' => $text]);
        }

        default:
            err_out('not_found', 404, 'Unknown route.');
    }
} catch (Throwable $e) {
    @error_log('[mahtem-api] ' . $e->getMessage() . ' @ ' . $method . ' ' . $path);
    err_out('server', 500, 'Unexpected server error.');
}
