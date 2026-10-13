-- Oyuncu ilerlemesi (bulut kaydı): yeniden yüklemede giriş yapınca kaldığı yerden devam.
-- Yalnız eklemeli ve idempotent: deploy.sh her deploy'da tüm migration'ları yeniden uygular;
-- mevcut tablolara dokunmaz. payload birleştirilebilir JSON'dur (backend/src/progress.php):
-- best/maxStreak en büyük, cihaz başı sayaçlar en büyük (toplam = cihazların toplamı),
-- ayarlar son yazan, tutorialDone VEYA. epoch "Sil ve baştan başla" ile artar; eski epoch'la
-- gelen yazım reddedilir ve cihaz yerel ilerlemesini siler (diğer cihazlara yayılım).

CREATE TABLE IF NOT EXISTS player_progress (
 user_id BIGINT UNSIGNED PRIMARY KEY,
 epoch INT UNSIGNED NOT NULL DEFAULT 0,
 revision INT UNSIGNED NOT NULL DEFAULT 0,
 payload JSON NOT NULL,
 best_score INT UNSIGNED NOT NULL DEFAULT 0,
 reset_at DATETIME NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 INDEX(updated_at),
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
