#!/usr/bin/env python3
"""App Store ürün sayfası başlığı (21:9, 3840x1646) ve arama sonucu (3:2, 3840x2560)
görsellerini tools/store_artwork/index.html'den headless Chrome ile üretir;
alfa kanalını kaldırır (Apple şeffaflık kabul etmez). Çıktı: store/appstore/."""

import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
HTML = ROOT / "tools/store_artwork/index.html"
OUT = ROOT / "store/appstore"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZES = {"header": (3840, 1646), "search": (3840, 2560)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, (w, h) in SIZES.items():
            raw = Path(tmp) / f"{name}.png"
            # Chrome headless ekran görüntüsünü yazdıktan sonra her zaman kendiliğinden
            # kapanmıyor; dosya oluşup sabitlenince süreci biz sonlandırıyoruz.
            proc = subprocess.Popen(
                [
                    CHROME,
                    "--headless=new",
                    "--no-first-run",
                    "--disable-background-networking",
                    "--disable-component-update",
                    "--hide-scrollbars",
                    "--allow-file-access-from-files",
                    "--force-device-scale-factor=1",
                    f"--user-data-dir={tmp}/profile-{name}",
                    f"--window-size={w},{h}",
                    f"--screenshot={raw}",
                    f"file://{HTML}?layout={name}",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            deadline = time.time() + 90
            last = -1
            while time.time() < deadline:
                time.sleep(1)
                size = raw.stat().st_size if raw.exists() else -1
                if size > 0 and size == last:
                    break
                last = size
            proc.kill()
            proc.wait()
            if not raw.exists():
                raise SystemExit(f"{name}: Chrome ekran görüntüsü üretmedi")
            img = Image.open(raw).convert("RGB")
            assert img.size == (w, h), (name, img.size)
            img.save(OUT / f"{name}-{w}x{h}.png", optimize=True)
            img.save(OUT / f"{name}-{w}x{h}.jpg", quality=94, subsampling=0)
            print(name, img.size, img.mode)


if __name__ == "__main__":
    main()
