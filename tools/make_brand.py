#!/usr/bin/env python3
"""Marka görsellerini tek kaynaktan (assets/brand/app-icon.png) üretir:
dış zemini şeffaf amblem, iOS/Android ikon setleri ve iOS açılış görseli."""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets/brand/app-icon.png"
MARK = ROOT / "assets/branding/sut-ve-gol-mark-transparent.png"
FONT = ROOT / "assets/fonts/TitilliumWeb-Bold.ttf"
IOS_ICONS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
LAUNCH = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
ANDROID_RES = ROOT / "android/app/src/main/res"
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def save(img, path):
    if path.exists():
        old = Image.open(path)
        if old.size == img.size and old.mode == img.mode:
            if ImageChops.difference(old, img).getbbox() is None:
                return
    img.save(path, optimize=True)


def edge_color(img):
    w, h = img.size
    px = img.load()
    ring = [px[x, y] for y in range(h) for x in (0, 1, w - 2, w - 1)]
    ring += [px[x, y] for x in range(w) for y in (0, 1, h - 2, h - 1)]
    mid = len(ring) // 2
    return tuple(sorted(p[i] for p in ring)[mid] for i in range(3))


def nearest_anchor(src, anchor, x, y, w, h, radius=6):
    for r in range(1, radius + 1):
        cells = [(x + dx, y - r) for dx in range(-r, r + 1)]
        cells += [(x + dx, y + r) for dx in range(-r, r + 1)]
        cells += [(x - r, y + dy) for dy in range(-r + 1, r)]
        cells += [(x + r, y + dy) for dy in range(-r + 1, r)]
        for cx, cy in cells:
            if 0 <= cx < w and 0 <= cy < h and anchor[cx, cy]:
                return src[cx, cy]
    return None


def make_mark(icon):
    """Yalnızca dış zemine bağlı laciverti şeffaflaştırır; kapalı bölgeler
    (top benekleri, file gözleri) ikondaki gibi lacivert kalır."""
    w, h = icon.size
    bg = edge_color(icon)
    diff = ImageChops.difference(icon, Image.new("RGB", icon.size, bg)).split()
    dist = ImageChops.lighter(ImageChops.lighter(diff[0], diff[1]), diff[2])
    solid = dist.point(lambda v: 255 if v >= 60 else 0)
    outer = solid.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.MinFilter(13))
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if outer.getpixel(corner) == 0:
            ImageDraw.floodfill(outer, corner, 128)
    outer = outer.point(lambda v: 255 if v == 128 else 0)
    band = outer.filter(ImageFilter.MaxFilter(5))
    anchor = dist.point(lambda v: 255 if v >= 150 else 0).load()
    src, dpx, opx, bpx = icon.load(), dist.load(), outer.load(), band.load()
    out = icon.convert("RGBA")
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if not bpx[x, y]:
                continue
            c = src[x, y]
            d = dpx[x, y]
            if d < 10:
                if opx[x, y]:
                    dst[x, y] = (*bg, 0)
                continue
            u = (c[0] - bg[0], c[1] - bg[1], c[2] - bg[2])
            fg = nearest_anchor(src, anchor, x, y, w, h)
            if fg is None:
                a = (d - 10) / 200
            else:
                v = (fg[0] - bg[0], fg[1] - bg[1], fg[2] - bg[2])
                a = (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / (
                    v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
                )
            a = min(1.0, max(0.0, a))
            if a <= 0.03:
                dst[x, y] = (*bg, 0)
            elif a >= 0.97:
                dst[x, y] = (*c, 255)
            else:
                dst[x, y] = (
                    *(min(255, max(0, round(bg[i] + u[i] / a))) for i in range(3)),
                    round(a * 255),
                )
    return out


def text(draw, s, size, center, fill, spacing):
    font = ImageFont.truetype(str(FONT), round(size))
    widths = [draw.textlength(ch, font=font) for ch in s]
    x = center[0] - (sum(widths) + spacing * (len(s) - 1)) / 2
    for ch, cw in zip(s, widths):
        draw.text((x, center[1]), ch, font=font, fill=fill, anchor="lm")
        x += cw + spacing


def make_launch(mark):
    """paintLogo ile aynı yerleşim: amblem solda, ŞUT VE / GOL sağda."""
    for scale, name in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
        w, h = 280 * scale, 113 * scale
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        size = round(h * 0.86)
        img.alpha_composite(
            mark.resize((size, size), Image.LANCZOS),
            (round(w * 0.015), round(h * 0.03)),
        )
        draw = ImageDraw.Draw(img)
        text(draw, "ŞUT VE", w * 0.145, (w * 0.68, h * 0.32), (245, 247, 255), 0)
        text(draw, "GOL", w * 0.195, (w * 0.68, h * 0.67), (255, 107, 24), w * 0.009)
        save(img, LAUNCH / name)


def make_ios_icons(icon):
    for item in json.loads((IOS_ICONS / "Contents.json").read_text())["images"]:
        if not item.get("filename"):
            continue
        n = round(float(item["size"].split("x")[0]) * float(item["scale"].rstrip("x")))
        save(icon.resize((n, n), Image.LANCZOS), IOS_ICONS / item["filename"])


def make_android_icons(icon):
    for dpi, n in ANDROID_SIZES.items():
        save(icon.resize((n, n), Image.LANCZOS), ANDROID_RES / f"mipmap-{dpi}/ic_launcher.png")


if __name__ == "__main__":
    icon = Image.open(ICON).convert("RGB")
    mark = make_mark(icon)
    save(mark, MARK)
    make_launch(mark)
    make_ios_icons(icon)
    make_android_icons(icon)
    print("Şeffaf amblem, iOS/Android ikonları ve açılış görseli üretildi.")
