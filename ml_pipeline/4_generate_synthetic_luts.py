"""
Stage 1 — 수학적 LUT 2000개 즉시 생성 (인터넷 불필요)

6개 카테고리로 다양한 색 스타일을 수학 변환으로 표현한다.
65³ 그리드를 벡터화 연산으로 처리하므로 LUT 1개 < 1초,
multiprocessing 사용 시 2000개 ≈ 5분.

출력: data/synthetic_luts/*.bin  (65³ float16 binary)
실행: python 4_generate_synthetic_luts.py
"""

import math
import struct
import hashlib
import multiprocessing as mp
from pathlib import Path

import numpy as np

from lut_axis_contract import save_float16_lut

OUT_DIR  = Path("data/synthetic_luts")
OUT_DIR.mkdir(parents=True, exist_ok=True)

LUT_DIM  = 65
SEED     = 42

# ── 공통 그리드 ───────────────────────────────────────────────────────────────

def _make_grid() -> np.ndarray:
    """(LUT_DIM³, 3) float32 RGB 그리드 [0,1]"""
    c = np.linspace(0, 1, LUT_DIM, dtype=np.float32)
    r, g, b = np.meshgrid(c, c, c, indexing="ij")
    return np.stack([r, g, b], axis=-1).reshape(-1, 3)


GRID = _make_grid()  # 공유 상수


def save_lut(lut: np.ndarray, path: Path):
    save_float16_lut(lut, path)


# ── 색공간 변환 유틸 ──────────────────────────────────────────────────────────

def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def linear_to_srgb(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.0031308, 12.92 * c,
                    1.055 * np.power(np.maximum(c, 0), 1/2.4) - 0.055)

def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[...,0], rgb[...,1], rgb[...,2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d  = mx - mn + 1e-9
    h  = np.where(mx == r, (g - b) / d % 6,
         np.where(mx == g, (b - r) / d + 2,
                           (r - g) / d + 4)) / 6.0
    with np.errstate(divide='ignore', invalid='ignore'):
        s = np.where(mx > 0, (mx - mn) / mx, 0.0)
    v  = mx
    return np.stack([h % 1.0, s, v], axis=-1)

def hsv_to_rgb(hsv: np.ndarray) -> np.ndarray:
    h, s, v = hsv[...,0] * 6, hsv[...,1], hsv[...,2]
    i = h.astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    rgb = np.stack([
        np.where(i==0,v, np.where(i==1,q, np.where(i==2,p,
          np.where(i==3,p, np.where(i==4,t, v))))),
        np.where(i==0,t, np.where(i==1,v, np.where(i==2,v,
          np.where(i==3,q, np.where(i==4,p, p))))),
        np.where(i==0,p, np.where(i==1,p, np.where(i==2,t,
          np.where(i==3,v, np.where(i==4,v, q))))),
    ], axis=-1)
    return np.clip(rgb, 0, 1)


# ── 카테고리 1: 색온도 변환 (400개) ──────────────────────────────────────────
# planckian locus 근사 → XYZ → sRGB 변환 행렬

def _kelvin_to_xy(K: float) -> tuple[float, float]:
    """CIE 1931 xy 색도 근사 (1667K~25000K)."""
    if K <= 4000:
        x = -0.2661239e9/K**3 - 0.2343589e6/K**2 + 0.8776956e3/K + 0.179910
    else:
        x = -3.0258469e9/K**3 + 2.1070379e6/K**2 + 0.2226347e3/K + 0.240390
    if K <= 2222:
        y = -1.1063814*x**3 - 1.34811020*x**2 + 2.18555832*x - 0.20219683
    elif K <= 4000:
        y = -0.9549476*x**3 - 1.37418593*x**2 + 2.09137015*x - 0.16748867
    else:
        y =  3.0817580*x**3 - 5.87338670*x**2 + 3.75112997*x - 0.37001483
    return x, y

def _wb_matrix(K: float) -> np.ndarray:
    """색온도 K에서 D65 화이트 밸런스 보정 행렬 (3×3)."""
    x, y = _kelvin_to_xy(K)
    z = 1 - x - y
    # XYZ 화이트 포인트
    Xw, Yw, Zw = x/y, 1.0, z/y
    # D65 기준 화이트
    Xd, Yd, Zd = 0.95047, 1.0, 1.08883
    # Von Kries 변환 (Bradford)
    M_brad = np.array([
        [ 0.8951,  0.2664, -0.1614],
        [-0.7502,  1.7135,  0.0367],
        [ 0.0389, -0.0685,  1.0296],
    ])
    src = M_brad @ np.array([Xw, Yw, Zw])
    dst = M_brad @ np.array([Xd, Yd, Zd])
    scale = np.diag(dst / (src + 1e-9))
    return np.linalg.inv(M_brad) @ scale @ M_brad

def generate_temperature_lut(K: float) -> np.ndarray:
    M   = _wb_matrix(K)
    rgb = GRID.copy()
    lin = srgb_to_linear(rgb)
    out = (lin @ M.T).clip(0, 1)
    return linear_to_srgb(out).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 카테고리 2: 필름 곡선 (400개) ────────────────────────────────────────────

def _s_curve(x: np.ndarray, toe: float, shoulder: float,
             gamma: float) -> np.ndarray:
    """파라미터화된 S-curve."""
    x = np.power(np.clip(x, 0, 1), gamma)
    # toe: 어두운 영역 compression
    # shoulder: 밝은 영역 roll-off
    low  = x / (1 + (toe - 1) * (1 - x))
    high = 1 - (1 - x) / (1 + (shoulder - 1) * x)
    lum  = 0.2126*x[...,0] + 0.7152*x[...,1] + 0.0722*x[...,2]
    t    = lum[..., None]
    return np.clip(low * (1 - t) + high * t, 0, 1)

def generate_film_lut(toe: float, shoulder: float,
                      gamma: float, saturation: float) -> np.ndarray:
    rgb  = GRID.copy()
    out  = _s_curve(rgb, toe, shoulder, gamma)
    # 채도 조정
    lum  = (0.2126*out[...,0] + 0.7152*out[...,1] + 0.0722*out[...,2])[...,None]
    out  = lum + (out - lum) * saturation
    return np.clip(out, 0, 1).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 카테고리 3: 스플릿 톤 (300개) ────────────────────────────────────────────

def generate_split_tone_lut(shadow_hue: float, shadow_sat: float,
                             highlight_hue: float, highlight_sat: float) -> np.ndarray:
    rgb = GRID.copy()
    lum = (0.2126*rgb[...,0] + 0.7152*rgb[...,1] + 0.0722*rgb[...,2])
    # shadow/highlight 마스크 (부드러운 전환)
    s_mask = np.clip(1 - lum * 3, 0, 1)[..., None]
    h_mask = np.clip(lum * 3 - 2, 0, 1)[..., None]
    # 색조 오프셋 (HSV 공간)
    hsv = rgb_to_hsv(rgb)
    sh  = np.copy(hsv)
    # shadow 색조
    sh[..., 0] = (sh[..., 0] +
                  s_mask[..., 0] * shadow_sat * math.sin(2*math.pi*shadow_hue)) % 1
    sh[..., 1] = np.clip(sh[..., 1] + s_mask[..., 0] * shadow_sat * 0.3, 0, 1)
    # highlight 색조
    sh[..., 0] = (sh[..., 0] +
                  h_mask[..., 0] * highlight_sat * math.sin(2*math.pi*highlight_hue)) % 1
    sh[..., 1] = np.clip(sh[..., 1] + h_mask[..., 0] * highlight_sat * 0.3, 0, 1)
    return np.clip(hsv_to_rgb(sh), 0, 1).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 카테고리 4: HSL 선택 조정 (300개) ────────────────────────────────────────

def generate_selective_hsl_lut(target_hue: float, hue_range: float,
                                hue_shift: float, sat_shift: float,
                                lum_shift: float) -> np.ndarray:
    rgb = GRID.copy()
    hsv = rgb_to_hsv(rgb)
    h   = hsv[..., 0]
    # 대상 색조 주변 Gaussian 마스크
    d    = np.minimum(np.abs(h - target_hue), 1 - np.abs(h - target_hue))
    mask = np.exp(-0.5 * (d / (hue_range + 1e-3)) ** 2)[..., None]
    sh   = np.copy(hsv)
    sh[..., 0] = (sh[..., 0] + mask[..., 0] * hue_shift) % 1
    sh[..., 1] = np.clip(sh[..., 1] + mask[..., 0] * sat_shift, 0, 1)
    sh[..., 2] = np.clip(sh[..., 2] + mask[..., 0] * lum_shift, 0, 1)
    return np.clip(hsv_to_rgb(sh), 0, 1).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 카테고리 5: 빈티지/페이드 (300개) ────────────────────────────────────────

def generate_fade_lut(black_lift: float, white_compress: float,
                      fade_r: float, fade_g: float, fade_b: float,
                      saturation: float) -> np.ndarray:
    rgb = GRID.copy()
    # 화이트 포인트 압축 + 블랙 리프트
    out = rgb * (1 - black_lift - white_compress) + black_lift
    # 색조 페이드 (흰 안개 효과)
    fade_color = np.array([fade_r, fade_g, fade_b])
    out = out * (1 - saturation * 0.5) + fade_color * saturation * 0.5
    # 채도 저하
    lum = (0.2126*out[...,0] + 0.7152*out[...,1] + 0.0722*out[...,2])[...,None]
    out = lum + (out - lum) * (1 - saturation * 0.3)
    return np.clip(out, 0, 1).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 카테고리 6: 시네마틱 (300개) ─────────────────────────────────────────────
# 오렌지-틸, 틸-오렌지, 아쿠아-오렌지, 무라사키 등 유명 색 체계

CINEMATIC_STYLES = [
    # (이름, shadow_hue, shadow_sat, highlight_hue, highlight_sat, gamma, contrast)
    ("orange_teal",    0.50, 0.35, 0.08, 0.40, 1.05, 1.10),
    ("teal_orange",    0.08, 0.35, 0.50, 0.40, 1.05, 1.10),
    ("aqua_orange",    0.54, 0.30, 0.07, 0.35, 1.00, 1.05),
    ("cyberpunk",      0.75, 0.50, 0.30, 0.45, 0.95, 1.20),
    ("warm_vintage",   0.05, 0.20, 0.10, 0.15, 1.10, 0.90),
    ("cold_nordic",    0.58, 0.25, 0.60, 0.20, 1.00, 1.05),
    ("desert_sunset",  0.08, 0.40, 0.06, 0.50, 1.05, 1.15),
    ("forest_green",   0.35, 0.30, 0.33, 0.20, 1.00, 1.00),
]

def generate_cinematic_lut(style_idx: int, variant: float) -> np.ndarray:
    s = CINEMATIC_STYLES[style_idx % len(CINEMATIC_STYLES)]
    _, sh, ss, hh, hs, gamma, contrast = s
    # variant로 파라미터 미세 조정 (다양성 확보)
    sh  = (sh + variant * 0.05) % 1
    hh  = (hh + variant * 0.03) % 1
    rgb = GRID.copy()
    # split tone
    lut = generate_split_tone_lut(sh, ss + variant*0.1,
                                  hh, hs + variant*0.1)
    # tone curve
    lut_flat = lut.reshape(-1, 3)
    lut_flat = _s_curve(lut_flat, 1.0 + variant*0.2,
                        1.0 + variant*0.3, gamma)
    # contrast
    lum = (0.2126*lut_flat[:,0]+0.7152*lut_flat[:,1]+0.0722*lut_flat[:,2])[:,None]
    lut_flat = np.clip(lum + (lut_flat - lum) * contrast, 0, 1)
    return lut_flat.reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


# ── 생성 작업 ─────────────────────────────────────────────────────────────────

def _worker(args):
    idx, params = args
    category, *p = params
    try:
        if   category == "temperature":
            lut = generate_temperature_lut(*p)
        elif category == "film":
            lut = generate_film_lut(*p)
        elif category == "split_tone":
            lut = generate_split_tone_lut(*p)
        elif category == "selective_hsl":
            lut = generate_selective_hsl_lut(*p)
        elif category == "fade":
            lut = generate_fade_lut(*p)
        elif category == "cinematic":
            lut = generate_cinematic_lut(*p)
        else:
            return idx, False

        out_path = OUT_DIR / f"syn_{idx:05d}.bin"
        save_lut(lut.astype(np.float32), out_path)
        return idx, True
    except Exception as e:
        print(f"  ✗ idx={idx}: {e}")
        return idx, False


def build_job_list(rng: np.random.Generator) -> list:
    jobs = []

    # 1. 색온도 (400개): 2500K ~ 10000K
    for K in np.linspace(2500, 10000, 400):
        jobs.append(("temperature", float(K)))

    # 2. 필름 곡선 (400개)
    for _ in range(400):
        jobs.append(("film",
            float(rng.uniform(0.8, 2.0)),   # toe
            float(rng.uniform(0.8, 2.0)),   # shoulder
            float(rng.uniform(0.8, 1.3)),   # gamma
            float(rng.uniform(0.6, 1.4)),   # saturation
        ))

    # 3. 스플릿 톤 (300개)
    for _ in range(300):
        jobs.append(("split_tone",
            float(rng.uniform(0, 1)),        # shadow hue
            float(rng.uniform(0.05, 0.4)),   # shadow sat
            float(rng.uniform(0, 1)),        # highlight hue
            float(rng.uniform(0.05, 0.4)),   # highlight sat
        ))

    # 4. HSL 선택 조정 (300개)
    for _ in range(300):
        jobs.append(("selective_hsl",
            float(rng.uniform(0, 1)),          # target hue
            float(rng.uniform(0.05, 0.2)),     # hue range
            float(rng.uniform(-0.1, 0.1)),     # hue shift
            float(rng.uniform(-0.3, 0.3)),     # sat shift
            float(rng.uniform(-0.15, 0.15)),   # lum shift
        ))

    # 5. 빈티지/페이드 (300개)
    for _ in range(300):
        fc = rng.uniform(0.7, 1.0, size=3)
        jobs.append(("fade",
            float(rng.uniform(0.0, 0.12)),   # black lift
            float(rng.uniform(0.0, 0.10)),   # white compress
            float(fc[0]), float(fc[1]), float(fc[2]),  # fade color
            float(rng.uniform(0.1, 0.5)),    # saturation
        ))

    # 6. 시네마틱 (300개)
    for i in range(300):
        jobs.append(("cinematic",
            i % len(CINEMATIC_STYLES),
            float(rng.uniform(-0.5, 0.5)),  # variant
        ))

    return jobs


def main():
    rng  = np.random.default_rng(SEED)
    jobs = build_job_list(rng)

    print(f"총 {len(jobs)}개 LUT 생성 시작 → {OUT_DIR}/")
    print(f"CPU 코어: {mp.cpu_count()}")

    args = list(enumerate(jobs))

    n_success = 0
    with mp.Pool(processes=min(mp.cpu_count(), 8)) as pool:
        from tqdm import tqdm
        for idx, ok in tqdm(pool.imap_unordered(_worker, args),
                            total=len(args), desc="LUT 생성"):
            if ok:
                n_success += 1

    print(f"\n완료: {n_success}/{len(jobs)}개 생성 ({OUT_DIR})")
    total = len(list(OUT_DIR.glob("*.bin")))
    print(f"data/synthetic_luts/ 총 .bin 파일: {total}개")


if __name__ == "__main__":
    main()
