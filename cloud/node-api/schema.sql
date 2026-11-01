-- Mahtem Cloud API — MySQL schema (reference), v1.17.0.
--
-- The API creates and migrates all of this automatically on its first
-- request, so importing this file is OPTIONAL. It is here for phpMyAdmin
-- users who prefer to inspect (or create) the schema by hand
-- (Plesk → Databases → phpMyAdmin).
--
-- Conventions used throughout:
--   * *_at BIGINT  = epoch MILLISECONDS — what the API reads and writes.
--   * *_dt DATETIME = human-readable mirror of the same instant, kept in
--     UTC, so dates are readable without FROM_UNIXTIME gymnastics.
--   * Every account is keyed by `user_id` (UUID); `identifier_hash` remains
--     the login lookup key. Passwords are never stored — the client sends
--     only a PBKDF2-derived `authKey`, and this DB stores `auth_hash`.
--
-- FOR A QUICK OVERVIEW, QUERY THE VIEWS (recreated on every boot):
--   SELECT * FROM v_user_overview;      -- who is who, plan, activity
--   SELECT * FROM v_receipt_overview;   -- every receipt check, readable
-- The API also re-adds any missing columns via ALTER on startup, so a
-- hand-created schema only needs the CREATE TABLE statements below.

CREATE TABLE IF NOT EXISTS `config` (
    `k` VARCHAR(64) NOT NULL PRIMARY KEY,
    `v` TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── accounts: one row per cloud account ──────────────────────────────
CREATE TABLE IF NOT EXISTS `accounts` (
    `identifier_hash` CHAR(64) NOT NULL PRIMARY KEY, -- SHA-256(identifier), login key
    `user_id`         CHAR(36) NOT NULL,             -- stable UUID, referenced everywhere
    `auth_hash`       CHAR(64) NOT NULL,             -- SHA-256(user_id : authKey); no passwords
    `identifier`      VARCHAR(255) NULL,             -- readable phone/email (normalized on-device)
    `identifier_type` VARCHAR(16) NULL,              -- 'phone' | 'email'
    `display_name`    VARCHAR(64) NULL,              -- optional name shown to the owner
    `status`          VARCHAR(16) NOT NULL DEFAULT 'active', -- 'active' | 'disabled'
    `sign_in_count`   BIGINT NOT NULL DEFAULT 0,
    `created_at`      BIGINT NOT NULL,
    `created_dt`      DATETIME NULL,
    `last_seen_at`    BIGINT NULL,
    `last_seen_dt`    DATETIME NULL,
    UNIQUE KEY `ux_accounts_user` (`user_id`),
    KEY `ix_accounts_identifier` (`identifier`(191))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── sign-in audit trail (90-day retention, pruned opportunistically) ─
CREATE TABLE IF NOT EXISTS `sign_ins` (
    `id`      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `user_id` CHAR(36) NOT NULL,
    `at`      BIGINT NOT NULL,
    `at_dt`   DATETIME NULL,
    KEY `ix_sign_ins_user_time` (`user_id`, `at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `refresh_tokens` (
    `token`      CHAR(64) NOT NULL PRIMARY KEY,
    `user_id`    CHAR(64) NOT NULL,
    `exp`        BIGINT NOT NULL,
    `created_at` BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── history backup: AES-256-GCM ciphertext, unreadable to the server ─
CREATE TABLE IF NOT EXISTS `vaults` (
    `user_id`    CHAR(36) NOT NULL PRIMARY KEY,
    `blob`       MEDIUMTEXT NOT NULL,
    `revision`   BIGINT NOT NULL,
    `updated_at` BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Mahtem Pro payments (Telebirr receipts, hash-only) ───────────────
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

-- ── verified receipt ledger: one row per check a signed-in user runs ─
CREATE TABLE IF NOT EXISTS `verified_receipts` (
    `id`            BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `user_id`       CHAR(36) NOT NULL,
    `entry_id`      VARCHAR(64) NOT NULL,   -- client history entry id (dedup key)
    `bank_id`       VARCHAR(32) NOT NULL,
    `bank_name`     VARCHAR(64) NOT NULL,
    `reference`     VARCHAR(255) NOT NULL,  -- the receipt reference verified
    `raw_payload`   TEXT NULL,              -- the QR payload / link / number it was verified WITH
    `sender_name`   VARCHAR(128) NULL,
    `receiver_name` VARCHAR(128) NULL,
    `amount`        DECIMAL(18, 2) NULL,
    `currency`      VARCHAR(8) NULL,
    `receipt_date`  VARCHAR(64) NULL,
    `status`        VARCHAR(16) NOT NULL,   -- 'verified' | 'failed'
    `message`       VARCHAR(512) NULL,      -- failure detail for failed checks
    `reason`        VARCHAR(255) NULL,      -- user's own note ("rent", "order #12")
    `verified_at`   BIGINT NOT NULL,
    `verified_dt`   DATETIME NULL,
    `created_at`    BIGINT NOT NULL,
    `created_dt`    DATETIME NULL,
    UNIQUE KEY `ux_receipts_entry` (`user_id`, `entry_id`),
    KEY `ix_receipts_user_time` (`user_id`, `verified_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── admin views (recreated by the API on every boot) ──────────────────
CREATE OR REPLACE VIEW `v_user_overview` AS
SELECT a.`user_id`,
       a.`identifier`,
       a.`identifier_type` AS `type`,
       a.`display_name`    AS `name`,
       a.`status`,
       a.`sign_in_count`   AS `signins`,
       a.`created_dt`      AS `member_since`,
       a.`last_seen_dt`    AS `last_seen`,
       FROM_UNIXTIME(FLOOR(p.`expires_at` / 1000)) AS `pro_until`,
       (SELECT COUNT(*) FROM `verified_receipts` r
         WHERE r.`user_id` = a.`user_id`) AS `checks`
FROM `accounts` a
LEFT JOIN `pro_status` p ON p.`user_id` = a.`user_id`;

CREATE OR REPLACE VIEW `v_receipt_overview` AS
SELECT r.`verified_dt`   AS `when`,
       a.`identifier`,
       a.`display_name`  AS `name`,
       r.`bank_name`     AS `bank`,
       r.`reference`,
       r.`sender_name`   AS `sender`,
       r.`receiver_name` AS `receiver`,
       r.`amount`,
       r.`currency`,
       r.`status`,
       r.`reason`
FROM `verified_receipts` r
LEFT JOIN `accounts` a ON a.`user_id` = r.`user_id`;

INSERT IGNORE INTO `config` (`k`, `v`) VALUES ('schema', '2');
