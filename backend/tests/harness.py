#!/usr/bin/env python3
"""Backend testleri için yerel koşum ortamı.

PHP'nin yerleşik sunucusunu (php -S) yerel bir MySQL test veritabanına bağlı
olarak başlatır, şemayı sıfırdan uygular ve HTTP çağrıları için küçük bir
istemci sunar. Gereksinimler: PHP 8.1+ (Homebrew php@8.4 yolu varsayılan),
yerel MySQL (root, parolasız) ve mysql CLI.

Kullanım: python3 backend/tests/run_tests.py  (bu modülü içe alır)
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # backend/
PHP = os.environ.get("SV_PHP", "/usr/local/opt/php@8.4/bin/php")
MYSQL = os.environ.get("SV_MYSQL", shutil.which("mysql") or "mysql")
DB_NAME = os.environ.get("SV_DB", f"sutvegol_test_{os.getpid()}")
DB_USER = os.environ.get("SV_DB_USER", "root")
DB_PASS = os.environ.get("SV_DB_PASS", "")
APP_KEY = "ab" * 32  # HS256 için en az 32 bayt


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def mysql(sql: str, db: str | None = DB_NAME) -> str:
    cmd = [MYSQL, f"-u{DB_USER}"]
    if DB_PASS:
        cmd.append(f"-p{DB_PASS}")
    if db:
        cmd.append(db)
    out = subprocess.run(cmd, input=sql, text=True, capture_output=True)
    if out.returncode != 0:
        raise RuntimeError(f"mysql hatası: {out.stderr.strip()}\nSQL: {sql[:200]}")
    return out.stdout


def reset_schema(collation: str = "utf8mb4_unicode_ci") -> None:
    """Creates a new isolated test database; never drops an existing database.

    `collation`: veritabanı varsayılanı. Canlıdaki gibi (docker MYSQL_DATABASE → sunucu
    varsayılanı utf8mb4_0900_ai_ci) harmanlama karışımı hatalarını yakalamak için verilebilir.
    """
    if not DB_NAME.startswith("sutvegol_test_") or not DB_NAME.replace('_','').isalnum():
        raise ValueError("Only newly-created sutvegol_test_* databases are allowed")
    if not collation.replace('_', '').isalnum():
        raise ValueError("invalid collation")
    mysql(
        f"CREATE DATABASE {DB_NAME} "
        f"CHARACTER SET utf8mb4 COLLATE {collation};",
        db=None,
    )
    sql = (ROOT / "database/schema.sql").read_text()
    migrations = sorted((ROOT / "database/migrations").glob("*.sql")) if (ROOT / "database/migrations").exists() else []
    for m in migrations:
        sql += "\n" + m.read_text()
    mysql(sql)


class Server:
    """php -S süreci; `with Server() as s:` ile kullanılır."""

    def __init__(self, port: int | None = None, docroot: str = "public", env: dict | None = None):
        self.port = port or _free_port()
        self.docroot = docroot
        self.extra_env = env or {}
        self.base = f"http://127.0.0.1:{self.port}"
        self.proc: subprocess.Popen | None = None
        self.log = Path("/tmp") / f"sutvegol-php-{self.port}.log"
        self.log_file = None

    def __enter__(self) -> "Server":
        env = dict(os.environ)
        env.update(
            {
                "DB_DSN": f"mysql:host=127.0.0.1;dbname={DB_NAME};charset=utf8mb4",
                "DB_USER": DB_USER,
                "DB_PASS": DB_PASS,
                "APP_KEY": APP_KEY,
                "APP_URL": self.base,
                "APPLE_CLIENT_ID": "com.globalmedia.sutVeGol",
                "GOOGLE_CLIENT_IDS": "test-client.apps.googleusercontent.com",
                "PHP_CLI_SERVER_WORKERS": "4",
            }
        )
        env.update(self.extra_env)
        self.log_file = open(self.log, "w")
        self.proc = subprocess.Popen(
            [PHP, "-S", f"127.0.0.1:{self.port}", "-t", str(ROOT / self.docroot)],
            env=env,
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                if self.docroot != "public":
                    with socket.create_connection(("127.0.0.1", self.port), timeout=1):
                        return self
                if self.get("/health")[1].get("ok"):
                    return self
            except Exception:
                time.sleep(0.1)
        self.__exit__()
        raise RuntimeError(f"PHP sunucusu açılmadı; log: {self.log}")

    def __exit__(self, *exc) -> None:
        if self.proc:
            import signal
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if self.log_file:
            self.log_file.close()

    # ------------------------------------------------------------ HTTP
    def call(self, method: str, path: str, data=None, token: str | None = None, headers=None):
        body = None if data is None else json.dumps(data).encode()
        req = urllib.request.Request(self.base + path, data=body, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Platform", "test")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.status, json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as e:
            raw = e.read()
            e.close()
            try:
                return e.code, json.loads(raw or b"{}")
            except json.JSONDecodeError:
                return e.code, {"ok": False, "raw": raw.decode(errors="replace")[:500]}

    def get(self, path, token=None):
        return self.call("GET", path, token=token)

    def post(self, path, data=None, token=None):
        return self.call("POST", path, data if data is not None else {}, token=token)

    def put(self, path, data=None, token=None):
        return self.call("PUT", path, data if data is not None else {}, token=token)

    def delete(self, path, data=None, token=None):
        return self.call("DELETE", path, data if data is not None else {}, token=token)

    # ------------------------------------------------------------ yardımcılar
    def register(self, name: str) -> dict:
        """Yeni kullanıcı; {'token','user','refresh'} döner."""
        status, r = self.post(
            "/v1/auth/register",
            {"email": f"{name}@test.local", "password": "password1", "username": name},
        )
        assert status == 200 and r.get("ok"), (status, r)
        mysql("DELETE FROM api_rate_limits")  # testler IP başı kayıt sınırına takılmasın
        return {"token": r["accessToken"], "refresh": r["refreshToken"], "user": r["user"], "name": name}


def stage_for(score: int) -> str:
    return "stadium" if score >= 1200 else "cage" if score >= 700 else "beach" if score >= 300 else "street"


class V2Run:
    """Düello v2 skor kuralının sunucudan bağımsız Python karşılığı; geçerli olay üretir.

    Gol 30 × combo (x1→x2→x3, tavan 3); 5. ardışık golde Kral Modu (10 sn, sabit x2);
    ıskalama/timeout combo'yu ve Kral Modu'nu sıfırlar, maçı bitirmez. `t` vuruş anı, `rt`
    sonucun işlendiği an (varsayılan t + 1 sn; timeout'ta t). Kral Modu `rt` ile işler.
    """

    def __init__(self):
        self.t = self.rt = self.seq = self.score = self.shots = self.hits = self.misses = 0
        self.streak = self.max_streak = self.fever_hits = self.fever_t = 0
        self.fever = False

    def event(self, hit=True, dt=1500, timeout=False, resolve=1000):
        self.t += dt
        t, stage = self.t, stage_for(self.score)
        rt = t if timeout else t + resolve
        self.rt = rt
        self.seq += 1
        self.shots += 1
        if timeout or not hit:
            hit = False
            self.misses += 1
            self.streak, self.fever, self.fever_t, mult = 0, False, 0, 0
        else:
            self.hits += 1
            if self.fever and rt < self.fever_t + 10000:
                mult = 2
                self.streak += 1
                self.fever_hits += 1
            else:
                self.streak = (0 if self.fever else self.streak) + 1
                mult = min(3, self.streak)
                self.fever = self.streak >= 5
                self.fever_t = rt if self.fever else 0
            self.score += 30 * mult
            self.max_streak = max(self.max_streak, self.streak)
        return dict(v=2, seq=self.seq, t=t, rt=rt, stage=stage, view="wide",
                    target=[660, 1350], chord=[0, 0] if timeout else [0, -500], dev=0,
                    tMax=0 if timeout else .5, power=0 if timeout else .5,
                    keeper=[None, None], path="timeout" if timeout else ("net" if hit else "out"),
                    hit=hit, end=[0, 0] if timeout else [660, 1350], drop=None,
                    score=self.score, streak=self.streak, fever=self.fever,
                    feverLeft=round(max(0, (self.fever_t + 10000 - rt) / 1000), 2) if self.fever else 0,
                    shots=self.shots, hits=self.hits, misses=self.misses,
                    feverHits=self.fever_hits, maxStreak=self.max_streak, mult=mult)
