-- Oyuncu güvenliği (build 13, App Store Guideline 1.2): şikâyet, engelleme, yönetici ad yasağı
-- ve kullanım koşulu onayı. Yalnız eklemeli ve idempotent: deploy.sh her deploy'da tüm
-- migration'ları yeniden uygular; mevcut tablo/satır silinmez. Yalnız users tablosuna bağlıdır
-- (diğer migration'larla sıra bağımlılığı yok). users'a eklenen üç sütun NULL'a izin verir
-- (MySQL 8.4'te anlık ALTER, tablo yeniden yazılmaz); mevcut kullanıcılar NULL kalır.
-- Kullanıcı adıyla karşılaştırılan sütunlar users ile aynı harmanlamayı (utf8mb4_unicode_ci) kullanır.

CREATE TABLE IF NOT EXISTS user_reports (
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

CREATE TABLE IF NOT EXISTS user_blocks (
 blocker_id BIGINT UNSIGNED NOT NULL,
 blocked_id BIGINT UNSIGNED NOT NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(blocker_id, blocked_id),
 INDEX ix_user_blocks_blocked (blocked_id),
 FOREIGN KEY(blocker_id) REFERENCES users(id) ON DELETE CASCADE,
 FOREIGN KEY(blocked_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS name_bans (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 name_key VARCHAR(20) NOT NULL,
 name_norm VARCHAR(40) NOT NULL,
 user_id BIGINT UNSIGNED NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_name_bans_key (name_key),
 INDEX ix_name_bans_norm (name_norm),
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='terms_version')=0, 'ALTER TABLE `users` ADD COLUMN `terms_version` SMALLINT UNSIGNED NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='terms_accepted_at')=0, 'ALTER TABLE `users` ADD COLUMN `terms_accepted_at` DATETIME NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
-- Yöneticinin inceleyip reddettiği (onayladığı) mevcut ad: yeni şikâyetler bu adı yeniden gizleyemez.
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='name_cleared_key')=0, 'ALTER TABLE `users` ADD COLUMN `name_cleared_key` VARCHAR(20) NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
