-- Düello v2 (hibrit): can yok, şut saati, combo, kayıtlı rakip (ghost), rövanş, rating.
-- Yalnız eklemeli ve idempotent: deploy.sh her deploy'da tüm migration'ları yeniden uygular.
-- MySQL 8.4 "ADD COLUMN IF NOT EXISTS" desteklemez ve prosedür (SUPER/binlog) gerektirmemek
-- için her sütun information_schema kontrolü + PREPARE ile eklenir. Mevcut satırlar
-- version=1 / kind='live' olarak kalır; hiçbir sütun/tablo silinmez.

SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='version')=0, 'ALTER TABLE `duels` ADD COLUMN `version` TINYINT UNSIGNED NOT NULL DEFAULT 1', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='kind')=0, 'ALTER TABLE `duels` ADD COLUMN `kind` ENUM(''live'',''ghost'') NOT NULL DEFAULT ''live''', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='draw')=0, 'ALTER TABLE `duels` ADD COLUMN `draw` TINYINT(1) NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='finished_at_ms')=0, 'ALTER TABLE `duels` ADD COLUMN `finished_at_ms` BIGINT UNSIGNED NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='rematch_of')=0, 'ALTER TABLE `duels` ADD COLUMN `rematch_of` CHAR(32) NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_source')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_source` VARCHAR(10) NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_user_id')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_user_id` BIGINT UNSIGNED NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_duel_id')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_duel_id` CHAR(32) NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_payload')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_payload` MEDIUMTEXT NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_score')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_score` INT UNSIGNED NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_hits')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_hits` INT UNSIGNED NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND COLUMN_NAME='ghost_max_streak')=0, 'ALTER TABLE `duels` ADD COLUMN `ghost_max_streak` INT UNSIGNED NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='streak')=0, 'ALTER TABLE `duel_players` ADD COLUMN `streak` INT UNSIGNED NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='fever')=0, 'ALTER TABLE `duel_players` ADD COLUMN `fever` TINYINT(1) NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='fever_t')=0, 'ALTER TABLE `duel_players` ADD COLUMN `fever_t` INT NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='rematch')=0, 'ALTER TABLE `duel_players` ADD COLUMN `rematch` TINYINT(1) NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='disconnected')=0, 'ALTER TABLE `duel_players` ADD COLUMN `disconnected` TINYINT(1) NOT NULL DEFAULT 0', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='xp_gain')=0, 'ALTER TABLE `duel_players` ADD COLUMN `xp_gain` INT UNSIGNED NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='rating_before')=0, 'ALTER TABLE `duel_players` ADD COLUMN `rating_before` INT NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duel_players' AND COLUMN_NAME='rating_after')=0, 'ALTER TABLE `duel_players` ADD COLUMN `rating_after` INT NULL', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;

-- Rövanş en fazla bir kez oluşturulur; ghost havuzu sorgusu için indeks.
SET @sv = IF((SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND INDEX_NAME='uq_duels_rematch_of')=0, 'ALTER TABLE `duels` ADD UNIQUE KEY uq_duels_rematch_of (rematch_of)', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;
SET @sv = IF((SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='duels' AND INDEX_NAME='ix_duels_ghost_pool')=0, 'ALTER TABLE `duels` ADD INDEX ix_duels_ghost_pool (version, status, created_at)', 'DO 0'); PREPARE sv_stmt FROM @sv; EXECUTE sv_stmt; DEALLOCATE PREPARE sv_stmt;

CREATE TABLE IF NOT EXISTS duel_ratings (
 user_id BIGINT UNSIGNED PRIMARY KEY,
 rating DOUBLE NOT NULL DEFAULT 1500, rd DOUBLE NOT NULL DEFAULT 350, vol DOUBLE NOT NULL DEFAULT 0.06,
 games INT UNSIGNED NOT NULL DEFAULT 0, wins INT UNSIGNED NOT NULL DEFAULT 0,
 losses INT UNSIGNED NOT NULL DEFAULT 0, draws INT UNSIGNED NOT NULL DEFAULT 0,
 xp INT UNSIGNED NOT NULL DEFAULT 0,
 updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
