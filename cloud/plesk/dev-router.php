<?php
/**
 * Local development router for the PHP built-in web server:
 *
 *   php -S 127.0.0.1:8088 dev-router.php
 *
 * (from the cloud/plesk directory). The production Apache .htaccess makes
 * this file unnecessary on Plesk.
 */

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if ($path === '/' || is_file(__DIR__ . $path)) {
    return false; // serve the static file (landing page, privacy, …)
}

if (strpos($path, '/api/') === 0 || strpos($path, '/v1/') === 0) {
    require __DIR__ . '/api/index.php';
    return true;
}

http_response_code(404);
header('Content-Type: text/plain');
echo "Not found\n";
return true;
