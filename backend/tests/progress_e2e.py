#!/usr/bin/env python3
"""Bulut kaydı uçtan uca: gerçek Flutter istemci kodu ↔ yerel PHP/MySQL.

Yeni bir sutvegol_test_* veritabanı ve yerel `php -S` açar, test kullanıcısı kaydeder,
`test/progress_e2e_test.dart`'ı bu sunucuya dart-define ile koşar (iki cihaz, yeniden kurulum
geri yüklemesi, sıfırlama yayılımı, 409, hesap silme), sonra veritabanını doğrular.
Canlı sunucuya bağlanmaz. Çalıştırma:
  SV_PHP=/usr/local/opt/php@8.4/bin/php python3 backend/tests/progress_e2e.py
"""
import os
import shutil
import subprocess
import sys

from harness import ROOT, Server, mysql, reset_schema

FLUTTER = os.environ.get("SV_FLUTTER", shutil.which("flutter") or "flutter")


def main() -> int:
    reset_schema()
    with Server() as s:
        u = s.register("pr_e2e")
        uid = mysql("SELECT id FROM users WHERE username='pr_e2e'").split()[-1]
        cmd = [FLUTTER, "test", "test/progress_e2e_test.dart",
               f"--dart-define=API_BASE_URL={s.base}",
               f"--dart-define=PROGRESS_E2E_TOKEN={u['token']}",
               f"--dart-define=PROGRESS_E2E_REFRESH={u['refresh']}",
               f"--dart-define=PROGRESS_E2E_USER={u['user']['id']}"]
        out = subprocess.run(cmd, cwd=ROOT.parent, capture_output=True, text=True)
        print(out.stdout[-3000:], out.stderr[-2000:], sep="\n")
        if out.returncode != 0 or "All tests passed" not in out.stdout or "~1" in out.stdout:
            print("FAIL: Flutter uçtan uca testi geçmedi (ya da atlandı)")
            return 1
        rows = mysql(f"SELECT COUNT(*) FROM player_progress WHERE user_id={uid}").split()[-1]
        status = mysql(f"SELECT status FROM users WHERE id={uid}").split()[-1]
        if rows != "0" or status != "deleted":
            print(f"FAIL: hesap silme sonrası player_progress={rows}, status={status}")
            return 1
    print("OK: bulut kaydı uçtan uca (yerel sunucu)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
