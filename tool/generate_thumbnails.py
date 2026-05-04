"""
썸네일 생성 스크립트 — 내장 필터 8개 (portrait, smooth, pop, accentuate,
faded_glow, morning, fine_art, structure) + original

사용법:
  pip install pillow numpy
  python tool/generate_thumbnails.py

출력: assets/images/<id>_thumb.jpg (128×128)
"""

from pathlib import Path
from PIL import Image, ImageFilter, ImageEnhance, ImageDraw
import numpy as np
import math

ASSETS = Path(__file__).parent.parent / "assets" / "images"
ASSETS.mkdir(parents=True, exist_ok=True)

SIZE = 128


def _base_gradient(colors: list[tuple]) -> Image.Image:
    """Simple top-left → bottom-right gradient from a list of (r,g,b)."""
    img = Image.new("RGB", (SIZE, SIZE))
    arr = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    n = len(colors)
    for i, (r, g, b) in enumerate(colors):
        t0 = i / (n - 1) if n > 1 else 0
        t1 = (i + 1) / (n - 1) if n > 1 else 1
        for y in range(SIZE):
            for x in range(SIZE):
                t = (x + y) / (2 * (SIZE - 1))
                if t0 <= t <= t1:
                    local = (t - t0) / (t1 - t0) if (t1 - t0) > 0 else 0
                    if i + 1 < n:
                        nr, ng, nb = colors[i + 1]
                        arr[y, x] = [
                            r + (nr - r) * local,
                            g + (ng - g) * local,
                            b + (nb - b) * local,
                        ]
                    else:
                        arr[y, x] = [r, g, b]
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    return img


def _overlay_label(img: Image.Image, text: str) -> Image.Image:
    out = img.copy()
    draw = ImageDraw.Draw(out)
    # Semi-transparent bottom bar
    bar = Image.new("RGBA", (SIZE, 28), (0, 0, 0, 140))
    out.paste(Image.fromarray(np.array(bar)[:, :, :3]),
              (0, SIZE - 28),
              mask=bar.split()[3])
    draw = ImageDraw.Draw(out)
    draw.text((SIZE // 2, SIZE - 14), text, fill=(255, 255, 255),
              anchor="mm")
    return out


PRESETS: dict[str, dict] = {
    "original": {
        "colors": [(200, 200, 200), (140, 140, 140)],
        "label": "Original",
    },
    "portrait": {
        "colors": [(255, 220, 190), (200, 160, 130), (140, 100, 80)],
        "label": "Portrait",
        "warm": True,
    },
    "smooth": {
        "colors": [(230, 225, 220), (180, 175, 170)],
        "label": "Smooth",
        "blur": 2,
    },
    "pop": {
        "colors": [(80, 160, 220), (200, 80, 80), (80, 200, 120)],
        "label": "Pop",
        "saturate": 1.4,
    },
    "accentuate": {
        "colors": [(30, 30, 50), (80, 80, 120), (160, 160, 200)],
        "label": "Accentuate",
        "contrast": 1.5,
    },
    "faded_glow": {
        "colors": [(210, 190, 180), (180, 165, 155), (160, 145, 135)],
        "label": "Faded Glow",
        "fade": True,
    },
    "morning": {
        "colors": [(255, 230, 160), (255, 200, 100), (200, 140, 80)],
        "label": "Morning",
        "warm": True,
    },
    "fine_art": {
        "colors": [(240, 235, 225), (180, 170, 155), (100, 90, 80)],
        "label": "Fine Art",
        "sepia": True,
    },
    "structure": {
        "colors": [(50, 60, 70), (100, 115, 130), (160, 175, 190)],
        "label": "Structure",
        "sharpen": True,
    },
}


def make_thumb(preset_id: str, cfg: dict) -> None:
    img = _base_gradient(cfg["colors"])

    if cfg.get("blur"):
        img = img.filter(ImageFilter.GaussianBlur(radius=cfg["blur"]))

    if cfg.get("warm"):
        arr = np.array(img, dtype=np.float32)
        arr[:, :, 0] = (arr[:, :, 0] * 1.08).clip(0, 255)
        arr[:, :, 2] = (arr[:, :, 2] * 0.92).clip(0, 255)
        img = Image.fromarray(arr.astype(np.uint8))

    if cfg.get("saturate"):
        img = ImageEnhance.Color(img).enhance(cfg["saturate"])

    if cfg.get("contrast"):
        img = ImageEnhance.Contrast(img).enhance(cfg["contrast"])

    if cfg.get("fade"):
        arr = np.array(img, dtype=np.float32)
        arr = arr * 0.75 + 40
        img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))

    if cfg.get("sepia"):
        arr = np.array(img.convert("L"), dtype=np.float32)
        r = (arr * 1.07).clip(0, 255)
        g = (arr * 0.90).clip(0, 255)
        b = (arr * 0.75).clip(0, 255)
        img = Image.fromarray(
            np.stack([r, g, b], axis=-1).astype(np.uint8))

    if cfg.get("sharpen"):
        img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=160))

    img = _overlay_label(img, cfg["label"])
    out_path = ASSETS / f"{preset_id}_thumb.jpg"
    img.save(out_path, "JPEG", quality=88)
    print(f"  ✓ {out_path.name}")


if __name__ == "__main__":
    print("썸네일 생성 중...")
    for pid, cfg in PRESETS.items():
        make_thumb(pid, cfg)
    print(f"\n완료 — {ASSETS}")
