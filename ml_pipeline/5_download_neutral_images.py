"""
Stage 1 — 중립 이미지 다운로드 및 품질 필터링

소스 우선순위:
  1. COCO val2017 (자동 다운로드, 학술 라이선스)
  2. Unsplash API (UNSPLASH_ACCESS_KEY 필요)
  3. Pexels API  (PEXELS_API_KEY 필요)

중립성 기준:
  - 채도 평균 < 0.45 (강한 색조 없음)
  - 히스토그램 클리핑 < 5%
  - 해상도 ≥ 512px

출력: data/neutral_images/*.jpg (256×256)
목표: 1000장+
"""

import io
import os
import time
import zipfile
import hashlib
import requests
import numpy as np
from pathlib import Path
from PIL import Image
from tqdm import tqdm

OUT_DIR = Path("data/neutral_images")
OUT_DIR.mkdir(parents=True, exist_ok=True)

TARGET_SIZE   = (256, 256)
TARGET_COUNT  = 2000
SAT_THRESHOLD = 0.45    # 채도 상한
CLIP_THRESHOLD = 0.05   # 클리핑 비율 상한

UNSPLASH_KEY = os.environ.get("UNSPLASH_ACCESS_KEY", "")
PEXELS_KEY   = os.environ.get("PEXELS_API_KEY", "")

UNSPLASH_QUERIES = [
    "landscape", "portrait", "cityscape", "indoor", "food",
    "nature", "architecture", "street", "studio", "golden hour",
    "forest", "beach", "mountain", "overcast", "flat light",
]

PEXELS_QUERIES = [
    "natural lighting", "flat light", "overcast sky", "studio photo",
    "candid portrait", "street photography",
]


# ── 중립성 필터 ───────────────────────────────────────────────────────────────

def is_neutral_enough(img: Image.Image) -> bool:
    """이미지가 중립 기준을 만족하는지 확인."""
    arr = np.array(img.convert("RGB"), dtype=np.float32) / 255.0
    if arr.shape[0] < 64 or arr.shape[1] < 64:
        return False

    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = np.where(mx > 0, (mx - mn) / mx, 0.0)
    if sat.mean() > SAT_THRESHOLD:
        return False

    clipped = ((arr > 0.97) | (arr < 0.03)).any(axis=-1).mean()
    if clipped > CLIP_THRESHOLD:
        return False

    return True


def process_and_save(img: Image.Image, idx: int) -> bool:
    orig_w, orig_h = img.size
    if min(orig_w, orig_h) < 256:
        return False
    if not is_neutral_enough(img):
        return False

    # 중앙 크롭 후 리사이즈
    short = min(orig_w, orig_h)
    left  = (orig_w - short) // 2
    top   = (orig_h - short) // 2
    img   = img.crop((left, top, left + short, top + short))
    img   = img.resize(TARGET_SIZE, Image.LANCZOS)

    out_path = OUT_DIR / f"{idx:06d}.jpg"
    img.convert("RGB").save(out_path, "JPEG", quality=92)
    return True


# ── COCO val2017 ──────────────────────────────────────────────────────────────

def download_coco(max_images: int = 1000) -> int:
    """COCO val2017에서 최대 max_images장 다운로드."""
    print("\n[소스 1] COCO val2017 다운로드...")
    zip_url  = "http://images.cocodataset.org/zips/val2017.zip"
    zip_path = Path("data/val2017.zip")
    img_dir  = Path("data/val2017_imgs")

    if not img_dir.exists():
        print(f"  ZIP 다운로드 중 (~800MB): {zip_url}")
        r = requests.get(zip_url, stream=True, timeout=120)
        total = int(r.headers.get("content-length", 0))
        with open(zip_path, "wb") as f, tqdm(
            total=total, unit="B", unit_scale=True, desc="  COCO"
        ) as pbar:
            for chunk in r.iter_content(1024 * 64):
                f.write(chunk)
                pbar.update(len(chunk))
        print("  압축 해제 중...")
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall("data/")
        img_dir = Path("data/val2017")
        zip_path.unlink(missing_ok=True)
    else:
        img_dir = Path("data/val2017")

    imgs = sorted(img_dir.glob("*.jpg"))
    np.random.shuffle(imgs)

    saved = 0
    existing = len(list(OUT_DIR.glob("*.jpg")))
    for img_path in tqdm(imgs[:max_images * 3], desc="  COCO 필터링"):
        if saved >= max_images:
            break
        try:
            img = Image.open(img_path)
            if process_and_save(img, existing + saved):
                saved += 1
        except Exception:
            pass

    print(f"  COCO: {saved}장 저장")
    return saved


# ── Unsplash ──────────────────────────────────────────────────────────────────

def download_unsplash(max_per_query: int = 30) -> int:
    if not UNSPLASH_KEY:
        print("\n[소스 2] Unsplash 건너뜀 (UNSPLASH_ACCESS_KEY 미설정)")
        return 0

    print(f"\n[소스 2] Unsplash ({len(UNSPLASH_QUERIES)}개 쿼리)...")
    session = requests.Session()
    session.headers["Authorization"] = f"Client-ID {UNSPLASH_KEY}"
    saved    = 0
    existing = len(list(OUT_DIR.glob("*.jpg")))

    for query in UNSPLASH_QUERIES:
        try:
            r = session.get(
                "https://api.unsplash.com/photos/random",
                params={"count": max_per_query, "query": query},
                timeout=20,
            )
            if r.status_code != 200:
                continue
            for item in r.json():
                url = item.get("urls", {}).get("regular", "")
                if not url:
                    continue
                try:
                    img_r = session.get(url, timeout=20)
                    img   = Image.open(io.BytesIO(img_r.content))
                    if process_and_save(img, existing + saved):
                        saved += 1
                except Exception:
                    pass
            time.sleep(1)
        except Exception as e:
            print(f"  Unsplash 오류 ({query}): {e}")

    print(f"  Unsplash: {saved}장 저장")
    return saved


# ── Pexels ────────────────────────────────────────────────────────────────────

def download_pexels(max_per_query: int = 40) -> int:
    if not PEXELS_KEY:
        print("\n[소스 3] Pexels 건너뜀 (PEXELS_API_KEY 미설정)")
        return 0

    print(f"\n[소스 3] Pexels ({len(PEXELS_QUERIES)}개 쿼리)...")
    session = requests.Session()
    session.headers["Authorization"] = PEXELS_KEY
    saved    = 0
    existing = len(list(OUT_DIR.glob("*.jpg")))

    for query in PEXELS_QUERIES:
        try:
            r = session.get(
                "https://api.pexels.com/v1/search",
                params={"query": query, "per_page": max_per_query},
                timeout=20,
            )
            if r.status_code != 200:
                continue
            for photo in r.json().get("photos", []):
                url = photo.get("src", {}).get("large", "")
                if not url:
                    continue
                try:
                    img_r = session.get(url, timeout=20)
                    img   = Image.open(io.BytesIO(img_r.content))
                    if process_and_save(img, existing + saved):
                        saved += 1
                except Exception:
                    pass
            time.sleep(1)
        except Exception as e:
            print(f"  Pexels 오류 ({query}): {e}")

    print(f"  Pexels: {saved}장 저장")
    return saved


# ── 통계 출력 ─────────────────────────────────────────────────────────────────

def print_stats():
    imgs = list(OUT_DIR.glob("*.jpg"))
    if not imgs:
        return
    sats = []
    for p in imgs[:200]:  # 샘플 200장만
        arr = np.array(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0
        r, g, b = arr[...,0], arr[...,1], arr[...,2]
        mx = np.maximum(np.maximum(r,g),b)
        mn = np.minimum(np.minimum(r,g),b)
        sats.append(np.where(mx>0, (mx-mn)/mx, 0).mean())
    print(f"\n통계 (샘플 200장):")
    print(f"  평균 채도: {np.mean(sats):.3f}  (기준 < {SAT_THRESHOLD})")
    print(f"  총 이미지: {len(imgs)}장")


def main():
    existing = len(list(OUT_DIR.glob("*.jpg")))
    print(f"기존 이미지: {existing}장 / 목표: {TARGET_COUNT}장")

    if existing >= TARGET_COUNT:
        print("이미 충분한 이미지가 있습니다.")
        print_stats()
        return

    need   = TARGET_COUNT - existing
    total  = 0
    total += download_coco(min(need, 1000))
    total += download_unsplash()
    total += download_pexels()

    print(f"\n완료: 총 {len(list(OUT_DIR.glob('*.jpg')))}장 ({OUT_DIR})")
    print_stats()

    final = len(list(OUT_DIR.glob("*.jpg")))
    if final < 500:
        print(f"\n※ 이미지 수({final})가 부족합니다.")
        print("  COCO 다운로드가 안 됐다면 수동으로 이미지를 추가하세요:")
        print(f"  → {OUT_DIR}/ 에 JPG 파일 복사")


if __name__ == "__main__":
    main()
