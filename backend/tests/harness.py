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


def reset_schema() -> None:
    """Creates a new isolated test database; never drops an existing database."""
    if not DB_NAME.startswith("sutvegol_test_") or not DB_NAME.replace('_','').isalnum():
        raise ValueError("Only newly-created sutvegol_test_* databases are allowed")
    mysql(
        f"CREATE DATABASE {DB_NAME} "
        "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;",
        db=None,
    )
    sql = (ROOT / "database/schema.sql").read_text()
    migrations = sorted((ROOT / "database/migrations").glob("*.sql")) if (ROOT / "database/migrations").exists() else []
    for m in migrations:
        sql += "\n" + m.read_text()
    mysql(sql)


class Server:
    """php -S süreci; `with Server() as s:` ile kullanılır."""

    def __init__(self, port: int | None = None):
        self.port = port or _free_port()
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
        self.log_file = open(self.log, "w")
        self.proc = subprocess.Popen(
            [PHP, "-S", f"127.0.0.1:{self.port}", "-t", str(ROOT / "public")],
            env=env,
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
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
        return {"token": r["accessToken"], "refresh": r["refreshToken"], "user": r["user"], "name": name}
