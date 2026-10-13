#!/usr/bin/env python3
"""Oyuncu güvenliği uçtan uca: gerçek Flutter istemci kodu ↔ yerel PHP/MySQL.

Canlıdaki gibi utf8mb4_0900_ai_ci varsayılanlı yeni bir sutvegol_test_* veritabanı ve yerel
`php -S` açar, iki test oyuncusu kaydeder (hedefin sıralamada skoru olur), sonra
`test/progress_e2e_test.dart` deseniyle `test/moderation_e2e_test.dart`'ı dart-define ile bu
sunucuya koşar (ad filtresi, şikâyet + tekrar + 422/410, engel → "Engellenen oyuncu", engeli
kaldırma) ve veritabanını doğrular. Canlı sunucuya bağlanmaz. Çalıştırma:
  SV_PHP=/usr/local/opt/php@8.4/bin/php python3 backend/tests/moderation_e2e.py
"""
import os
import shutil
import subprocess
import sys

from harness import ROOT, Server, mysql, reset_schema

FLUTTER = os.environ.get("SV_FLUTTER", shutil.which("flutter") or "flutter")


def main() -> int:
    reset_schema("utf8mb4_0900_ai_ci")
    with Server() as s:
        me = s.register("e2e_ben")
        target = s.register("e2e_rakip")
        for who in (me, target):
            st, g = s.post("/v1/games", {"version": "1.0.0"}, who["token"])
            assert st == 201, g
            st, r = s.post(f"/v1/games/{g['sessionId']}/finish", dict(
                nonce=g["nonce"], score=60, shots=2, hits=2, misses=0, feverHits=0, maxStreak=2,
                durationMs=6000, stage="street"), who["token"])
            assert r.get("accepted"), r
        cmd = [FLUTTER, "test", "test/moderation_e2e_test.dart",
               f"--dart-define=API_BASE_URL={s.base}",
               f"--dart-define=MOD_E2E_TOKEN={me['token']}",
               f"--dart-define=MOD_E2E_REFRESH={me['refresh']}",
               f"--dart-define=MOD_E2E_USER={me['user']['id']}",
               f"--dart-define=MOD_E2E_TARGET={target['user']['id']}"]
        out = subprocess.run(cmd, cwd=ROOT.parent, capture_output=True, text=True)
        print(out.stdout[-3000:], out.stderr[-2000:], sep="\n")
        if out.returncode != 0 or "All tests passed" not in out.stdout or "~1" in out.stdout:
            print("FAIL: Flutter uçtan uca testi geçmedi (ya da atlandı)")
            return 1
        row = mysql("SELECT CONCAT_WS('|',r.reason,r.context,r.reported_name,r.status,r.note) FROM user_reports r "
                    "JOIN users a ON a.id=r.reporter_id WHERE a.username='e2e_ben'").strip().splitlines()
        blocks = mysql("SELECT COUNT(*) FROM user_blocks").split()[-1]
        if row[1:] != ["username|leaderboard|e2e_rakip|open|e2e notu"] or blocks != "0":
            print(f"FAIL: veritabanı beklenen durumda değil: rapor={row[1:]}, engel={blocks}")
            return 1
    print("OK: oyuncu güvenliği uçtan uca (yerel sunucu, gerçek istemci)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
