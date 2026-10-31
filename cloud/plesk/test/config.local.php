<?php
// Local test config — SQLite driver for running test_api.mjs without MySQL.
// Never deployed: production keeps driver = 'mysql' in ../api/config.php.

return [
    'driver' => 'sqlite',
    'sqlite_path' => __DIR__ . '/mahtem-test.sqlite',
    'migrate_from_url' => '',
];
