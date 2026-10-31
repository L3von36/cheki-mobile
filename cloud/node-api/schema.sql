-- Mahtem Cloud API — MySQL schema (reference).
--
-- The API creates these tables automatically on its first request, so
-- importing this file is OPTIONAL. It is here for phpMyAdmin users who
-- prefer to create the schema by hand (Plesk → Databases → phpMyAdmin).

CREATE TABLE IF NOT EXISTS `config` (
    `k` VARCHAR(64) NOT NULL PRIMARY KEY,
    `v` TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `accounts` (
    `identifier_hash` CHAR(64) NOT NULL PRIMARY KEY,
    `user_id`         CHAR(36) NOT NULL,
    `auth_hash`       CHAR(64) NOT NULL,
    `created_at`      BIGINT NOT NULL,
    UNIQUE KEY `ux_accounts_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `refresh_tokens` (
    `token`      CHAR(64) NOT NULL PRIMARY KEY,
    `user_id`    CHAR(64) NOT NULL,
    `exp`        BIGINT NOT NULL,
    `created_at` BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `vaults` (
    `user_id`    CHAR(36) NOT NULL PRIMARY KEY,
    `blob`       MEDIUMTEXT NOT NULL,
    `revision`   BIGINT NOT NULL,
    `updated_at` BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pro_receipts` (
    `receipt_hash` CHAR(64) NOT NULL PRIMARY KEY,
    `user_id`      CHAR(64) NOT NULL,
    `amount_etb`   INT NOT NULL,
    `plan_days`    INT NOT NULL,
    `paid_at_ms`   BIGINT NULL,
    `claimed_at`   BIGINT NOT NULL,
    `expires_at`   BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pro_status` (
    `user_id`    CHAR(36) NOT NULL PRIMARY KEY,
    `expires_at` BIGINT NOT NULL,
    `updated_at` BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `config` (`k`, `v`) VALUES ('schema', '1');
