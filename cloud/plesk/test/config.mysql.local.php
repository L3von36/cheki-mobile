<?php
// Local test config — real MySQL 8 server (sandbox only).
// Exercises the exact production code path (INSERT IGNORE, FOR UPDATE,
// ON DUPLICATE KEY UPDATE) that Plesk MySQL will run.

return [
    'driver' => 'mysql',
    'mysql' => [
        'host'   => '127.0.0.1',
        'port'   => 33061,
        'dbname' => 'mahtem_test',
        'user'   => 'mahtem',
        'pass'   => 'testpass123',
    ],
    'migrate_from_url' => '',
];
