#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f .env ]]; then echo 'Missing .env. Follow backend/README.md.' >&2; exit 1; fi
# Serialize manual and Actions deploys on the host. Never delete data volumes.
exec 9>.deploy.lock
flock -n 9 || { echo 'Another deployment is running.' >&2; exit 1; }
docker compose build app
docker compose up -d db
for attempt in {1..60}; do
  if docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" -e "SELECT 1"' >/dev/null 2>&1; then break; fi
  if [[ "$attempt" == 60 ]]; then echo 'Database did not become ready.' >&2; exit 1; fi
  sleep 2
done
# Only additive IF NOT EXISTS migrations. Make a private backup before them.
mkdir -p .deploy-backups
chmod 700 .deploy-backups
backup=".deploy-backups/db-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysqldump --single-transaction --no-tablespaces -u"$MYSQL_USER" "$MYSQL_DATABASE"' | gzip > "$backup"
chmod 600 "$backup"
for migration in backend/database/migrations/*.sql; do
  docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"' < "$migration"
done
docker compose up -d --no-deps app
port="$(docker compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["app"]["ports"][0]["published"])')"
for attempt in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:${port}/api/health" >/dev/null; then echo 'Şut ve Gol deployment is healthy.'; exit 0; fi
  sleep 2
done
echo 'Health check failed. Check docker compose logs --tail=100 app.' >&2
exit 1
