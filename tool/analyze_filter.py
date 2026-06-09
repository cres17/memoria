"""
Memoria filter analysis tool.
Ports the exact Dart algorithm to Python, runs it on the test images,
generates comparison metrics, and analyzes the blue capture failure.
"""
import math
import numpy as np
from PIL import Image

TEST_DIR = r"c:\Users\STORY\Documents\GitHub\memoria\test"

# ─── sRGB ↔ Lab (D65) ────────────────────────────────────────────────────────

XN, YN, ZN = 0.95047, 1.00000, 1.08883

def linearize(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def delinearize(c):
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * (np.maximum(c, 0) ** (1.0/2.4)) - 0.055)

def f_lab(t):
    d = 6.0 / 29.0
    return np.where(t > d**3, t ** (1.0/3.0), t / (3*d*d) + 4.0/29.0)

def f_inv_lab(t):
    d = 6.0 / 29.0
    return np.where(t > d, t**3, 3*d*d*(t - 4.0/29.0))

def rgb_to_lab(img_f32):
    """img_f32: (H,W,3) float32 in [0,1]  →  (H,W,3) Lab"""
    r, g, b = img_f32[...,0], img_f32[...,1], img_f32[...,2]
    rl, gl, bl = linearize(r), linearize(g), linearize(b)
    x = 0.4124564*rl + 0.3575761*gl + 0.1804375*bl
    y = 0.2126729*rl + 0.7151522*gl + 0.0721750*bl
    z = 0.0193339*rl + 0.1191920*gl + 0.9503041*bl
    fx = f_lab(x/XN); fy = f_lab(y/YN); fz = f_lab(z/ZN)
    L  = 116*fy - 16
    a  = 500*(fx - fy)
    bv = 200*(fy - fz)
    return np.stack([L, a, bv], axis=-1)

def lab_to_rgb(lab):
    """lab: (H,W,3)  →  sRGB float32 (H,W,3)"""
    L, a, bv = lab[...,0], lab[...,1], lab[...,2]
    fy = (L + 16) / 116
    fx = a / 500 + fy
    fz = fy - bv / 200
    x = f_inv_lab(fx)*XN
    y = f_inv_lab(fy)*YN
    z = f_inv_lab(fz)*ZN
    rl =  3.2404542*x - 1.5371385*y - 0.4985314*z
    gl = -0.9692660*x + 1.8760108*y + 0.0415560*z
    bl2=  0.0556434*x - 0.2040259*y + 1.0572252*z
    rgb = np.stack([rl, gl, bl2], axis=-1).clip(0,1)
    return delinearize(rgb).clip(0,1)

# ─── Neutral channel CDF (exact port of _buildNeutralChannelCdf) ─────────────

def build_neutral_channel_cdf():
    mu, sigma = 115.0, 55.0
    hist = np.exp(-0.5 * ((np.arange(256) - mu) / sigma)**2)
    hist /= hist.sum()
    return np.cumsum(hist)

NEUTRAL_CDF = build_neutral_channel_cdf()

def channel_curve(channel_u8):
    """port of _channelCurve: returns 256-entry int array."""
    hist = np.bincount(channel_u8, minlength=256).astype(float)
    style_cdf = np.cumsum(hist / hist.sum())
    curve = np.zeros(256, dtype=int)
    for i in range(256):
        target = NEUTRAL_CDF[i]
        j = int(np.searchsorted(style_cdf, target, side='left'))
        curve[i] = min(j, 255)
    # enforce monotonicity
    for i in range(1, 256):
        if curve[i] < curve[i-1]:
            curve[i] = curve[i-1]
    return curve

# ─── Style analysis ───────────────────────────────────────────────────────────

def analyze_style(style_img_f32):
    """Returns profile dict matching StyleProfile fields."""
    h, w = style_img_f32.shape[:2]
    max_dim = max(h, w)
    if max_dim > 512:
        scale = 512.0 / max_dim
        nh, nw = int(h*scale), int(w*scale)
        from PIL import Image as _PIL
        pil = _PIL.fromarray((style_img_f32*255).clip(0,255).astype(np.uint8))
        pil = pil.resize((nw, nh), _PIL.LANCZOS)
        style_img_f32 = np.array(pil, dtype=np.float32) / 255.0

    r = style_img_f32[...,0].ravel()
    g = style_img_f32[...,1].ravel()
    b = style_img_f32[...,2].ravel()

    r8 = (r*255).round().clip(0,255).astype(int)
    g8 = (g*255).round().clip(0,255).astype(int)
    b8 = (b*255).round().clip(0,255).astype(int)

    rCurve = channel_curve(r8)
    gCurve = channel_curve(g8)
    bCurve = channel_curve(b8)

    lab = rgb_to_lab(style_img_f32)
    L_ch = lab[...,0].ravel()
    a_ch = lab[...,1].ravel()
    b_ch = lab[...,2].ravel()

    # Zone casts
    smask = L_ch < 35
    mmask = (L_ch >= 35) & (L_ch < 65)
    hmask = L_ch >= 65

    def zone_cast(mask):
        if mask.sum() > 10:
            return {'a': a_ch[mask].mean(), 'b': b_ch[mask].mean(), 'count': int(mask.sum())}
        return {'a': 0.0, 'b': 0.0, 'count': 0}

    # Blue stats
    blue_dom = b - np.maximum(r, g)
    blue_mask = blue_dom > 0.02
    blue_count = blue_mask.sum()

    if blue_count > 0:
        blueDominance = float(blue_dom[blue_mask].mean().clip(0, 1))
        lab_flat_b = (-b_ch[blue_mask]).clip(0, 110)
        blueCastStrength = float((lab_flat_b / (blue_count * 55.0)).sum().clip(0, 1))
        # blue B channel histogram
        blue_b8 = b8[blue_mask]
        blueBHist = np.bincount(blue_b8, minlength=256).astype(int)
    else:
        blueDominance = 0.0
        blueCastStrength = 0.0
        blueBHist = np.zeros(256, dtype=int)

    n = r.size
    # Blend blue B curve when enough blue pixels
    if blue_count > 500:
        blueCurve = channel_curve(blue_b8)
        blueRatio = min(blue_count / n, 1.0)
        baseWeight = min(0.25 + 0.55 * blueRatio, 0.8)
        for i in range(256):
            high_mask = min(max((i - 32) / 223.0, 0.0), 1.0)
            w = baseWeight * high_mask
            bCurve[i] = int(round((1.0 - w) * bCurve[i] + w * blueCurve[i]))
            bCurve[i] = min(max(bCurve[i], 0), 255)
        for i in range(1, 256):
            if bCurve[i] < bCurve[i-1]:
                bCurve[i] = bCurve[i-1]

    return {
        'rCurve': rCurve, 'gCurve': gCurve, 'bCurve': bCurve,
        'shadowCast': zone_cast(smask),
        'midtoneCast': zone_cast(mmask),
        'highlightCast': zone_cast(hmask),
        'meanL': float(L_ch.mean()),
        'blueDominance': blueDominance,
        'blueCastStrength': blueCastStrength,
        'blueCount': int(blue_count),
        'totalPixels': int(n),
    }

# ─── LUT generation ───────────────────────────────────────────────────────────

DIM = 33

def generate_lut(profile):
    """Returns (DIM,DIM,DIM,3) float32 LUT."""
    base_tint = 0.15
    tint_str = min(max(base_tint + 0.12 * profile['blueCastStrength'], base_tint), 0.30)

    rCurve = profile['rCurve']
    gCurve = profile['gCurve']
    bCurve = profile['bCurve']
    sc = profile['shadowCast']
    mc = profile['midtoneCast']
    hc = profile['highlightCast']

    lut = np.zeros((DIM, DIM, DIM, 3), dtype=np.float32)

    for ri in range(DIM):
        for gi in range(DIM):
            for bi in range(DIM):
                r8 = int(round(ri / 32.0 * 255))
                g8 = int(round(gi / 32.0 * 255))
                b8 = int(round(bi / 32.0 * 255))

                r1 = rCurve[r8] / 255.0
                g1 = gCurve[g8] / 255.0
                b1 = bCurve[b8] / 255.0

                lab = rgb_to_lab(np.array([[[r1, g1, b1]]], dtype=np.float32))[0,0]

                def gw(l, center, sigma=25.0):
                    d = l - center
                    return math.exp(-0.5 * d*d / (sigma*sigma))

                ws = gw(lab[0], 17.5)
                wm = gw(lab[0], 50.0)
                wh = gw(lab[0], 82.5)
                wTotal = ws + wm + wh + 1e-10

                zoneA = (ws*sc['a'] + wm*mc['a'] + wh*hc['a']) / wTotal
                zoneB = (ws*sc['b'] + wm*mc['b'] + wh*hc['b']) / wTotal

                aOut = max(-110.0, min(110.0, lab[1] + tint_str * zoneA))
                bOut = max(-110.0, min(110.0, lab[2] + tint_str * zoneB))

                out = lab_to_rgb(np.array([[[lab[0], aOut, bOut]]], dtype=np.float32))[0,0]
                lut[ri, gi, bi] = out

    return lut

# ─── LUT application (trilinear) ─────────────────────────────────────────────

def apply_lut(img_f32, lut):
    """img_f32: (H,W,3) → (H,W,3) after trilinear LUT lookup."""
    ri = img_f32[...,0] * 32.0
    gi = img_f32[...,1] * 32.0
    bi = img_f32[...,2] * 32.0

    r0 = np.floor(ri).astype(int).clip(0, 31)
    g0 = np.floor(gi).astype(int).clip(0, 31)
    b0 = np.floor(bi).astype(int).clip(0, 31)
    r1 = (r0 + 1).clip(0, 32)
    g1 = (g0 + 1).clip(0, 32)
    b1 = (b0 + 1).clip(0, 32)

    rf = (ri - r0)[..., np.newaxis]
    gf = (gi - g0)[..., np.newaxis]
    bf = (bi - b0)[..., np.newaxis]

    c000 = lut[r0, g0, b0]
    c100 = lut[r1, g0, b0]
    c010 = lut[r0, g1, b0]
    c110 = lut[r1, g1, b0]
    c001 = lut[r0, g0, b1]
    c101 = lut[r1, g0, b1]
    c011 = lut[r0, g1, b1]
    c111 = lut[r1, g1, b1]

    c00 = c000 + (c100 - c000) * rf
    c10 = c010 + (c110 - c010) * rf
    c01 = c001 + (c101 - c001) * rf
    c11 = c011 + (c111 - c011) * rf

    c0 = c00 + (c10 - c00) * gf
    c1 = c01 + (c11 - c01) * gf

    return (c0 + (c1 - c0) * bf).clip(0, 1)

# ─── Metrics ─────────────────────────────────────────────────────────────────

def psnr(a, b):
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64))**2)
    if mse == 0: return float('inf')
    return 10 * math.log10(255**2 / mse)

def delta_e(lab_a, lab_b):
    """Mean Delta E (CIE76) between two Lab images."""
    diff = lab_a.astype(np.float64) - lab_b.astype(np.float64)
    return float(np.mean(np.sqrt(np.sum(diff**2, axis=-1))))

def mae_per_channel(a_u8, b_u8):
    """MAE per channel (0-255)."""
    diff = np.abs(a_u8.astype(np.float64) - b_u8.astype(np.float64))
    return [float(diff[...,c].mean()) for c in range(3)]

def resize_to_match(img, target_shape):
    """Resize img to (H, W) of target_shape."""
    th, tw = target_shape[:2]
    h, w = img.shape[:2]
    if (h, w) == (th, tw):
        return img
    pil = Image.fromarray((img*255).clip(0,255).astype(np.uint8))
    pil = pil.resize((tw, th), Image.LANCZOS)
    return np.array(pil, dtype=np.float32) / 255.0

# ─── Blue analysis ────────────────────────────────────────────────────────────

def analyze_blue_failure(original_f32, corrected_f32, filtered_f32):
    """
    Quantify how well blue is captured.
    Returns per-pixel blue error stats.
    """
    # Isolate blue-dominant pixels (B > R, B > G by margin)
    r, g, b = corrected_f32[...,0], corrected_f32[...,1], corrected_f32[...,2]
    blue_mask = (b - np.maximum(r, g)) > 0.05

    if blue_mask.sum() == 0:
        return {'note': 'No blue-dominant pixels in corrected image'}

    corr_b = corrected_f32[blue_mask]
    filt_b = filtered_f32[blue_mask]
    orig_b = original_f32[blue_mask]

    # Per-channel error on blue pixels
    ch_err_corr_vs_filt = np.abs(corr_b - filt_b).mean(axis=0)

    # Lab comparison on blue pixels
    corr_lab = rgb_to_lab(corrected_f32)[blue_mask]
    filt_lab = rgb_to_lab(filtered_f32)[blue_mask]
    orig_lab = rgb_to_lab(original_f32)[blue_mask]

    # What the corrected image wants (original→corrected delta)
    target_delta_L = (corr_lab[:,0] - orig_lab[:,0]).mean()
    target_delta_a = (corr_lab[:,1] - orig_lab[:,1]).mean()
    target_delta_b = (corr_lab[:,2] - orig_lab[:,2]).mean()

    # What the filter actually achieves (original→filtered delta)
    actual_delta_L = (filt_lab[:,0] - orig_lab[:,0]).mean()
    actual_delta_a = (filt_lab[:,1] - orig_lab[:,1]).mean()
    actual_delta_b = (filt_lab[:,2] - orig_lab[:,2]).mean()

    # Lab b of blues in style vs filtered
    style_mean_lab_b_on_blues = corr_lab[:,2].mean()
    filtered_mean_lab_b_on_blues = filt_lab[:,2].mean()
    original_mean_lab_b_on_blues = orig_lab[:,2].mean()

    dE_blue = float(np.mean(np.sqrt(np.sum((corr_lab - filt_lab)**2, axis=-1))))

    return {
        'blue_pixel_count': int(blue_mask.sum()),
        'blue_pixel_pct': float(blue_mask.mean()*100),
        'R_MAE_on_blue': float(ch_err_corr_vs_filt[0]),
        'G_MAE_on_blue': float(ch_err_corr_vs_filt[1]),
        'B_MAE_on_blue': float(ch_err_corr_vs_filt[2]),
        'delta_E_on_blue': dE_blue,
        'target_Lab_delta': {'L': target_delta_L, 'a': target_delta_a, 'b': target_delta_b},
        'actual_Lab_delta': {'L': actual_delta_L, 'a': actual_delta_a, 'b': actual_delta_b},
        'Lab_b_on_blues': {
            'original': original_mean_lab_b_on_blues,
            'corrected_target': style_mean_lab_b_on_blues,
            'filter_output': filtered_mean_lab_b_on_blues,
        },
    }

# ─── Main pipeline ────────────────────────────────────────────────────────────

def load(path):
    img = Image.open(path).convert('RGB')
    return np.array(img, dtype=np.float32) / 255.0

def run_pair(n):
    print(f"\n{'='*60}")
    print(f"  PAIR {n}")
    print(f"{'='*60}")

    style_path  = f"{TEST_DIR}/보정본_{n}.jpg"
    orig_path   = f"{TEST_DIR}/원본_{n}.jpg"

    style  = load(style_path)   # corrected / style image → used to extract filter
    orig   = load(orig_path)    # original image → filter applied to this

    print(f"Style (보정본_{n}):  {style.shape[1]}×{style.shape[0]}")
    print(f"Original (원본_{n}): {orig.shape[1]}×{orig.shape[0]}")

    # Extract filter from style image
    print("\n[1] Analyzing style image…")
    profile = analyze_style(style)
    print(f"    meanL={profile['meanL']:.1f}  blueDominance={profile['blueDominance']:.3f}  "
          f"blueCastStrength={profile['blueCastStrength']:.3f}  blueCount={profile['blueCount']}")

    print("[2] Generating 33³ LUT…", end=' ', flush=True)
    lut = generate_lut(profile)
    print("done")

    # Apply LUT to original
    print("[3] Applying filter to original…", end=' ', flush=True)
    filtered = apply_lut(orig, lut)
    print("done")

    # Resize style to same size as original for comparison
    corr_resized = resize_to_match(style, orig.shape)

    # Convert to uint8 for metrics
    orig_u8    = (orig*255).round().astype(np.uint8)
    corr_u8    = (corr_resized*255).round().astype(np.uint8)
    filt_u8    = (filtered*255).round().astype(np.uint8)

    # Lab for delta E
    orig_lab   = rgb_to_lab(orig)
    corr_lab   = rgb_to_lab(corr_resized)
    filt_lab   = rgb_to_lab(filtered)

    print("\n── Metrics ──────────────────────────────────────────────")

    # Baseline: how different is original from corrected?
    dE_base   = delta_e(orig_lab, corr_lab)
    mae_base  = mae_per_channel(orig_u8, corr_u8)
    psnr_base = psnr(orig_u8, corr_u8)

    # Filter output vs corrected target
    dE_filt   = delta_e(corr_lab, filt_lab)
    mae_filt  = mae_per_channel(corr_u8, filt_u8)
    psnr_filt = psnr(corr_u8, filt_u8)

    print(f"\n  [Baseline: 원본 vs 보정본 — how much the correction changed]")
    print(f"  Delta E (CIE76): {dE_base:.2f}")
    print(f"  PSNR:            {psnr_base:.1f} dB")
    print(f"  MAE R/G/B:       {mae_base[0]:.2f} / {mae_base[1]:.2f} / {mae_base[2]:.2f}")

    print(f"\n  [Result: 필터 적용 vs 보정본 — how close the filter got]")
    print(f"  Delta E (CIE76): {dE_filt:.2f}  (lower = better)")
    print(f"  PSNR:            {psnr_filt:.1f} dB  (higher = better)")
    print(f"  MAE R/G/B:       {mae_filt[0]:.2f} / {mae_filt[1]:.2f} / {mae_filt[2]:.2f}")

    # Recovery ratio: how much of the correction was captured?
    recover_pct_dE = max(0, (dE_base - dE_filt) / dE_base * 100)
    print(f"\n  Recovery (Delta E):  {recover_pct_dE:.1f}% of correction captured")

    # Per-zone Lab stats
    print("\n  [Zone Lab stats — 보정본 vs 필터]")
    for zone_name, mask_fn in [
        ("Shadow  (L<35) ", lambda l: l[...,0] < 35),
        ("Midtone (35-65)", lambda l: (l[...,0]>=35)&(l[...,0]<65)),
        ("Highlt  (L≥65) ", lambda l: l[...,0] >= 65),
    ]:
        m = mask_fn(corr_lab)
        if m.sum() == 0: continue
        dE_zone = float(np.mean(np.sqrt(np.sum((corr_lab[m] - filt_lab[m])**2, axis=-1))))
        corr_mA = corr_lab[m,1].mean(); filt_mA = filt_lab[m,1].mean()
        corr_mB = corr_lab[m,2].mean(); filt_mB = filt_lab[m,2].mean()
        print(f"    {zone_name}  dE={dE_zone:.2f}  "
              f"a: corr={corr_mA:+.1f} filt={filt_mA:+.1f}  "
              f"b: corr={corr_mB:+.1f} filt={filt_mB:+.1f}")

    print("\n── Blue analysis ─────────────────────────────────────────")
    blue = analyze_blue_failure(orig, corr_resized, filtered)
    if 'note' in blue:
        print(f"  {blue['note']}")
    else:
        print(f"  Blue pixels in corrected:  {blue['blue_pixel_count']} ({blue['blue_pixel_pct']:.1f}%)")
        print(f"  Delta E on blue pixels:    {blue['delta_E_on_blue']:.2f}")
        print(f"  MAE R/G/B on blue pixels:  {blue['R_MAE_on_blue']:.3f} / "
              f"{blue['G_MAE_on_blue']:.3f} / {blue['B_MAE_on_blue']:.3f}")
        td = blue['target_Lab_delta']
        ad = blue['actual_Lab_delta']
        print(f"\n  What correction does to blue pixels (원본→보정본 Lab delta):")
        print(f"    ΔL={td['L']:+.2f}  Δa={td['a']:+.2f}  Δb={td['b']:+.2f}")
        print(f"  What filter achieves on blue pixels (원본→필터 Lab delta):")
        print(f"    ΔL={ad['L']:+.2f}  Δa={ad['a']:+.2f}  Δb={ad['b']:+.2f}")
        lb = blue['Lab_b_on_blues']
        print(f"\n  Lab b-axis (blue/yellow) on blue pixels:")
        print(f"    Original:  {lb['original']:+.2f}")
        print(f"    Target:    {lb['corrected_target']:+.2f}  (보정본이 원하는 값)")
        print(f"    Filter:    {lb['filter_output']:+.2f}  (필터가 실제로 낸 값)")
        miss = lb['filter_output'] - lb['corrected_target']
        print(f"    Miss:      {miss:+.2f}  (양수=너무 노랗게, 음수=덜 파랗게)")

    return {
        'dE_baseline': dE_base, 'dE_filter': dE_filt,
        'psnr_filter': psnr_filt, 'mae_filter': mae_filt,
        'recover_pct': recover_pct_dE, 'blue': blue,
        'profile': profile,
    }

# ─── Structural blue bug diagnosis ───────────────────────────────────────────

def print_structural_diagnosis(r1, r2):
    print(f"\n{'='*60}")
    print("  STRUCTURAL BLUE BUG ANALYSIS")
    print(f"{'='*60}")
    print("""
문제: 파란색 영역을 제대로 재현하지 못함.

[원인 1] Per-channel histogram matching이 전체 통계를 사용
─────────────────────────────────────────────────────────
  B 채널 커브는 이미지 전체의 B 분포를 중립→스타일로 매핑함.
  파란 픽셀과 파랗지 않은 픽셀이 같은 B 채널 값을 가져도,
  이를 구별하지 않고 동일한 곡선을 적용함.

  예: 하늘(순파랑)과 회색 그림자(B≈127)가 같은 B 커브를 받음.
  → 회색 픽셀에 파랑 커브를 적용하면 컬러 캐스트가 생기고,
    파란 픽셀에는 오히려 맞지 않는 커브가 적용될 수 있음.

[원인 2] Lab b 축의 구조적 손실
─────────────────────────────────────────────────────────
  파란색 = Lab에서 b가 매우 음수(-30 ~ -60 범위).
  하지만 Stage 2 (zone Lab tint) strength가 고작 0.15~0.30.

  즉, R/G/B 3개 독립 커브로는 "hue"를 정확히 바꿀 수 없음.
  예를 들어, 순수한 파랑(0,0,1)에 R 커브가 R을 올리면
  → R 증가 → 보라/마젠타로 hue shift (파란색 소실).

[원인 3] blueCount 조건부 blueCurve 블렌딩의 한계
─────────────────────────────────────────────────────────
  blue_count > 500 일 때만 블루 전용 B 커브를 블렌딩하는데,
  블렌딩 범위가 (baseWeight=0.25~0.80) × highMask에 한정됨.
  그리고 R/G 커브는 블루 픽셀을 전혀 구분하지 않으므로
  B 커브만 보정해도 R,G가 파란 영역의 hue를 왜곡함.

[원인 4] Intensity mix가 파란 왜곡을 희석시키지 못함
─────────────────────────────────────────────────────────
  Intensity=1.0이면 왜곡이 그대로 노출.
  Intensity를 낮추면 전반적으로 효과도 줄어들어 근본 해결 안 됨.
""")
    print("[구체적 수치 근거]")
    for i, r in enumerate([r1, r2], 1):
        b = r['blue']
        if 'note' not in b:
            td = b['target_Lab_delta']
            ad = b['actual_Lab_delta']
            lb = b['Lab_b_on_blues']
            print(f"\n  Pair {i}:")
            print(f"    파란 픽셀 수:     {b['blue_pixel_count']} ({b['blue_pixel_pct']:.1f}%)")
            print(f"    파란 영역 Delta E: {b['delta_E_on_blue']:.2f}")
            print(f"    Lab b 목표값:     {lb['corrected_target']:+.2f}")
            print(f"    Lab b 실제출력:   {lb['filter_output']:+.2f}")
            print(f"    Lab b 미스:       {lb['filter_output']-lb['corrected_target']:+.2f}")
            print(f"    목표 Δb (blue):   {td['b']:+.2f}  vs  실제 Δb: {ad['b']:+.2f}")
            capture_b = ad['b']/td['b']*100 if abs(td['b'])>0.1 else float('nan')
            print(f"    b축 캡처율:       {capture_b:.1f}%")
        else:
            print(f"\n  Pair {i}: {b['note']}")

if __name__ == '__main__':
    r1 = run_pair(1)
    r2 = run_pair(2)
    print_structural_diagnosis(r1, r2)
