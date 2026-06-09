"""
Stage 1 — .cube LUT 파일 수집
GitHub Search API + 직접 URL 목록으로 공개 LUT를 자동 다운로드한다.

실행: python 1_download_luts.py
환경변수(선택): GITHUB_TOKEN — GitHub API rate limit 5000req/h (미설정 시 60req/h)
목표: data/luts/ 에 .cube 파일 200개+
"""

import os
import re
import time
import hashlib
import requests
from pathlib import Path

OUT_DIR    = Path("data/luts")
OUT_DIR.mkdir(parents=True, exist_ok=True)

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
HEADERS = {"Authorization": f"token {GITHUB_TOKEN}"} if GITHUB_TOKEN else {}

# ── 직접 다운로드 URL 목록 ────────────────────────────────────────────────────
# 공개 LUT 저장소에서 검증된 .cube 파일 raw URL
DIRECT_URLS = [
    # Colour-science 예제 LUT
    "https://raw.githubusercontent.com/colour-science/colour/develop/"
    "colour/io/luts/tests/resources/iridas_cube/ACES_Proxy_10_to_ACES.cube",
    "https://raw.githubusercontent.com/colour-science/colour/develop/"
    "colour/io/luts/tests/resources/iridas_cube/LogC_Camera_to_LogC_Monitor.cube",
    "https://raw.githubusercontent.com/colour-science/colour/develop/"
    "colour/io/luts/tests/resources/iridas_cube/identity.cube",
    # Filmbox / OpenColorIO 예제
    "https://raw.githubusercontent.com/imageworks/OpenColorIO-Configs/master/"
    "aces_1.2/luts/Log2_48_nits_Shaper.cube",
]

# ── GitHub API 검색 쿼리 ──────────────────────────────────────────────────────
SEARCH_QUERIES = [
    "extension:cube LUT_3D_SIZE",
    "filename:.cube LUT color grade",
    "filename:.cube cinematic LUT",
    "filename:.cube film emulation",
]


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def validate_cube(content: str) -> tuple[bool, int]:
    """
    .cube 파일 유효성 검사.
    Returns (is_valid, lut_dim).
    """
    dim = None
    data_lines = 0
    for line in content.splitlines():
        line = line.strip()
        if line.startswith("LUT_3D_SIZE"):
            try:
                dim = int(line.split()[-1])
            except ValueError:
                return False, 0
        elif line and not line.startswith("#") and not line.startswith("TITLE") \
                and not line.startswith("LUT") and not line.startswith("DOMAIN"):
            parts = line.split()
            if len(parts) == 3:
                try:
                    [float(x) for x in parts]
                    data_lines += 1
                except ValueError:
                    pass

    if dim is None or data_lines == 0:
        return False, 0
    expected = dim ** 3
    # 허용 오차 ±5%
    return abs(data_lines - expected) / expected < 0.05, dim


def download_url(url: str, session: requests.Session) -> bool:
    """URL에서 .cube 파일을 다운로드. 성공 시 True."""
    try:
        r = session.get(url, timeout=15)
        if r.status_code != 200:
            return False
        content = r.text
        valid, dim = validate_cube(content)
        if not valid:
            print(f"  ✗ 유효하지 않은 LUT: {url[:60]}")
            return False

        h = sha256_of(r.content)
        fname = OUT_DIR / f"dl_{h}_{dim}.cube"
        if fname.exists():
            return False  # 중복

        fname.write_text(content, encoding="utf-8")
        print(f"  ✓ {dim}³  {fname.name}  ← {url[:60]}")
        return True
    except Exception as e:
        print(f"  ✗ {url[:60]}: {e}")
        return False


def search_github(query: str, session: requests.Session, max_results: int = 30) -> list[str]:
    """GitHub Code Search API로 .cube 파일 raw URL 목록 반환."""
    raw_urls = []
    params = {"q": query, "per_page": min(max_results, 30)}
    try:
        r = session.get(
            "https://api.github.com/search/code",
            params=params, headers=HEADERS, timeout=20
        )
        if r.status_code == 403:
            print("  GitHub API rate limit 초과. GITHUB_TOKEN 설정 권장.")
            return []
        if r.status_code != 200:
            return []

        data = r.json()
        for item in data.get("items", []):
            raw_url = item.get("html_url", "").replace(
                "github.com", "raw.githubusercontent.com"
            ).replace("/blob/", "/")
            if raw_url.endswith(".cube"):
                raw_urls.append(raw_url)

        # API 친화적 속도 제한
        time.sleep(2)
    except Exception as e:
        print(f"  GitHub 검색 오류: {e}")
    return raw_urls


def main():
    session = requests.Session()
    session.headers.update({"User-Agent": "Memoria-LUT-Collector/1.0"})

    downloaded = 0

    # 1단계: 직접 URL 다운로드
    print(f"\n[1/2] 직접 URL {len(DIRECT_URLS)}개 다운로드...")
    for url in DIRECT_URLS:
        if download_url(url, session):
            downloaded += 1

    # 2단계: GitHub API 검색
    print(f"\n[2/2] GitHub 검색 ({len(SEARCH_QUERIES)}개 쿼리)...")
    if not GITHUB_TOKEN:
        print("  ※ GITHUB_TOKEN 미설정 — rate limit 60req/h (느림)")

    for query in SEARCH_QUERIES:
        print(f"  검색: {query}")
        urls = search_github(query, session)
        for url in urls:
            if download_url(url, session):
                downloaded += 1
        time.sleep(3)  # GitHub API 친화적 지연

    # 결과 요약
    cube_files = list(OUT_DIR.glob("*.cube"))
    print(f"\n완료: {downloaded}개 신규 다운로드 / 총 {len(cube_files)}개 ({OUT_DIR})")
    if len(cube_files) < 50:
        print("  ※ LUT 수가 적습니다. 4_generate_synthetic_luts.py로 보완하세요.")


if __name__ == "__main__":
    main()
