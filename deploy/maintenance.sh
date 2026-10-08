#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec 9>.deploy.lock
flock -n 9 || exit 0
mkdir -p .deploy-backups
chmod 700 .deploy-backups
umask 077
backup=".deploy-backups/db-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysqldump --single-transaction --no-tablespaces -u"$MYSQL_USER" "$MYSQL_DATABASE"' | gzip > "$backup"
# Expire only this application's recovery snapshots, never Docker volumes.
find .deploy-backups -maxdepth 1 -type f -name 'db-*.sql.gz' -mtime +28 -delete
docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"' <<'SQL'
DELETE FROM api_rate_limits WHERE window_start < DATE_SUB(NOW(), INTERVAL 2 DAY);
DELETE FROM auth_challenges WHERE expires_at < NOW();
DELETE FROM duel_queue WHERE last_seen_ms < UNIX_TIMESTAMP(NOW())*1000-15000;
SQL
