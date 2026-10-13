CREATE TABLE users (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, public_id CHAR(26) NOT NULL UNIQUE,
 email VARCHAR(190) NULL UNIQUE, password_hash VARCHAR(255) NULL,
 username VARCHAR(20) NULL, username_key VARCHAR(20) NULL UNIQUE,
 display_name VARCHAR(80) NULL, avatar_url VARCHAR(500) NULL,
 status ENUM('active','suspended','deleted') NOT NULL DEFAULT 'active',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 last_seen_at DATETIME NULL, terms_version SMALLINT UNSIGNED NULL, terms_accepted_at DATETIME NULL,
 name_cleared_key VARCHAR(20) NULL,
 INDEX(created_at), INDEX(last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE identities (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL,
 provider ENUM('email','google','apple') NOT NULL, provider_subject VARCHAR(255) NOT NULL,
 email VARCHAR(190) NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY(provider,provider_subject), FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE refresh_tokens (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL,
 token_hash CHAR(64) NOT NULL UNIQUE, device_name VARCHAR(120) NULL,
 expires_at DATETIME NOT NULL, revoked_at DATETIME NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE, INDEX(expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE game_sessions (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, public_id CHAR(32) NOT NULL UNIQUE,
 user_id BIGINT UNSIGNED NOT NULL, nonce CHAR(32) NOT NULL, score INT UNSIGNED NOT NULL DEFAULT 0,
 shots SMALLINT UNSIGNED NOT NULL DEFAULT 0, hits SMALLINT UNSIGNED NOT NULL DEFAULT 0,
 misses SMALLINT UNSIGNED NOT NULL DEFAULT 0, fever_hits SMALLINT UNSIGNED NOT NULL DEFAULT 0,
 max_streak SMALLINT UNSIGNED NOT NULL DEFAULT 0, duration_ms INT UNSIGNED NOT NULL DEFAULT 0,
 stage VARCHAR(20) NOT NULL DEFAULT 'street', client_version VARCHAR(24) NULL, platform VARCHAR(20) NULL,
 suspicious TINYINT(1) NOT NULL DEFAULT 0, reject_reason VARCHAR(255) NULL,
 started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, finished_at DATETIME NULL,
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
 INDEX(score), INDEX(finished_at), INDEX(user_id,finished_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE daily_user_stats (
 stat_date DATE NOT NULL, user_id BIGINT UNSIGNED NOT NULL,
 sessions INT UNSIGNED NOT NULL DEFAULT 0, shots INT UNSIGNED NOT NULL DEFAULT 0,
 hits INT UNSIGNED NOT NULL DEFAULT 0, play_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
 best_score INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY(stat_date,user_id),
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE api_rate_limits (
 bucket CHAR(64) NOT NULL, window_start DATETIME NOT NULL, hits SMALLINT UNSIGNED NOT NULL DEFAULT 1,
 PRIMARY KEY(bucket,window_start), INDEX(window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Oyuncu güvenliği (migrations/20261013_moderation.sql ile aynı; yeni kurulumda migration atlar).
CREATE TABLE user_reports (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 reporter_id BIGINT UNSIGNED NOT NULL,
 target_id BIGINT UNSIGNED NOT NULL,
 reason ENUM('username','cheating','other') NOT NULL,
 context ENUM('duel','ghost','leaderboard') NOT NULL,
 duel_id CHAR(32) NULL,
 note VARCHAR(200) NULL,
 reported_name VARCHAR(20) NULL,
 status ENUM('open','dismissed','actioned') NOT NULL DEFAULT 'open',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 resolved_at DATETIME NULL,
 UNIQUE KEY uq_user_reports_pair (reporter_id, target_id),
 INDEX ix_user_reports_open (status, created_at),
 INDEX ix_user_reports_target (target_id, status, reason),
 FOREIGN KEY(reporter_id) REFERENCES users(id) ON DELETE CASCADE,
 FOREIGN KEY(target_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_blocks (
 blocker_id BIGINT UNSIGNED NOT NULL,
 blocked_id BIGINT UNSIGNED NOT NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(blocker_id, blocked_id),
 INDEX ix_user_blocks_blocked (blocked_id),
 FOREIGN KEY(blocker_id) REFERENCES users(id) ON DELETE CASCADE,
 FOREIGN KEY(blocked_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE name_bans (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 name_key VARCHAR(20) NOT NULL,
 name_norm VARCHAR(40) NOT NULL,
 user_id BIGINT UNSIGNED NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_name_bans_key (name_key),
 INDEX ix_name_bans_norm (name_norm),
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
