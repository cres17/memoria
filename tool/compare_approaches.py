"""
Compare current implementation vs simple Lab mean/std transfer (Reinhard).
"""
import math
import numpy as np
from PIL import Image

TEST_DIR = r"c:\Users\STORY\Documents\GitHub\memoria\test"

# ─── Color space utils (same as before) ──────────────────────────────────────

XN, YN, ZN = 0.95047, 1.00000, 1.08883

def linearize(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def delinearize(c):
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * (np.maximum(c, 0) ** (1/2.4)) - 0.055)

def f_lab(t):
    d = 6/29
    return np.where(t > d**3, t**(1/3), t/(3*d*d) + 4/29)

def f_inv(t):
    d = 6/29
    return np.where(t > d, t**3, 3*d*d*(t - 4/29))

def to_lab(img):
    r, g, b = img[...,0], img[...,1], img[...,2]
    rl, gl, bl = linearize(r), linearize(g), linearize(b)
    x = 0.4124564*rl + 0.3575761*gl + 0.1804375*bl
    y = 0.2126729*rl + 0.7151522*gl + 0.0721750*bl
    z = 0.0193339*rl + 0.1191920*gl + 0.9503041*bl
    fx = f_lab(x/XN); fy = f_lab(y/YN); fz = f_lab(z/ZN)
    return np.stack([116*fy-16, 500*(fx-fy), 200*(fy-fz)], axis=-1)

def from_lab(lab):
    L, a, b = lab[...,0], lab[...,1], lab[...,2]
    fy = (L+16)/116; fx = a/500+fy; fz = fy-b/200
    x = f_inv(fx)*XN; y = f_inv(fy)*YN; z = f_inv(fz)*ZN
    rl =  3.2404542*x - 1.5371385*y - 0.4985314*z
    gl = -0.9692660*x + 1.8760108*y + 0.0415560*z
    bl =  0.0556434*x - 0.2040259*y + 1.0572252*z
    return delinearize(np.stack([rl,gl,bl], axis=-1).clip(0,1)).clip(0,1)

# ─── Metrics ─────────────────────────────────────────────────────────────────

def delta_e(a, b):
    d = a.astype(np.float64) - b.astype(np.float64)
    return float(np.mean(np.sqrt(np.sum(d**2, axis=-1))))

def psnr(a_u8, b_u8):
    mse = np.mean((a_u8.astype(np.float64)-b_u8.astype(np.float64))**2)
    return float('inf') if mse == 0 else 10*math.log10(255**2/mse)

def mae_rgb(a_u8, b_u8):
    d = np.abs(a_u8.astype(np.float64)-b_u8.astype(np.float64))
    return [float(d[...,c].mean()) for c in range(3)]

def blue_delta_e(target, result):
    r,g,b = target[...,0],target[...,1],target[...,2]
    mask = (b - np.maximum(r,g)) > 0.05
    if mask.sum() == 0:
        return None, 0
    t_lab = to_lab(target)[mask]
    r_lab = to_lab(result)[mask]
    dE = float(np.mean(np.sqrt(np.sum((t_lab-r_lab)**2, axis=-1))))
    return dE, int(mask.sum())

# ─── Approach A: Current (per-channel RGB histogram matching) ─────────────────

def build_neutral_cdf():
    mu, sigma = 115.0, 55.0
    h = np.exp(-0.5*((np.arange(256)-mu)/sigma)**2)
    h /= h.sum()
    return np.cumsum(h)

NEUTRAL_CDF = build_neutral_cdf()

def channel_curve(ch_u8):
    hist = np.bincount(ch_u8.ravel(), minlength=256).astype(float)
    scdf = np.cumsum(hist/hist.sum())
    curve = np.zeros(256, dtype=int)
    for i in range(256):
        j = int(np.searchsorted(scdf, NEUTRAL_CDF[i], side='left'))
        curve[i] = min(j, 255)
    for i in range(1,256):
        if curve[i] < curve[i-1]: curve[i] = curve[i-1]
    return curve

def apply_lut_trilinear(img, lut):
    ri = img[...,0]*32; gi = img[...,1]*32; bi = img[...,2]*32
    r0 = np.floor(ri).astype(int).clip(0,31); r1 = (r0+1).clip(0,32)
    g0 = np.floor(gi).astype(int).clip(0,31); g1 = (g0+1).clip(0,32)
    b0 = np.floor(bi).astype(int).clip(0,31); b1 = (b0+1).clip(0,32)
    rf = (ri-r0)[...,None]; gf = (gi-g0)[...,None]; bf = (bi-b0)[...,None]
    c000=lut[r0,g0,b0]; c100=lut[r1,g0,b0]; c010=lut[r0,g1,b0]; c110=lut[r1,g1,b0]
    c001=lut[r0,g0,b1]; c101=lut[r1,g0,b1]; c011=lut[r0,g1,b1]; c111=lut[r1,g1,b1]
    c00=c000+(c100-c000)*rf; c10=c010+(c110-c010)*rf
    c01=c001+(c101-c001)*rf; c11=c011+(c111-c011)*rf
    c0=c00+(c10-c00)*gf; c1=c01+(c11-c01)*gf
    return (c0+(c1-c0)*bf).clip(0,1)

def generate_lut_current(style_f32):
    """Current approach: RGB per-channel histogram matching + zone Lab tint."""
    h,w = style_f32.shape[:2]
    if max(h,w) > 512:
        sc = 512/max(h,w)
        p = Image.fromarray((style_f32*255).astype(np.uint8))
        p = p.resize((int(w*sc),int(h*sc)), Image.LANCZOS)
        s = np.array(p)/255.0
    else:
        s = style_f32

    r8 = (s[...,0]*255).round().clip(0,255).astype(int)
    g8 = (s[...,1]*255).round().clip(0,255).astype(int)
    b8 = (s[...,2]*255).round().clip(0,255).astype(int)

    rC = channel_curve(r8); gC = channel_curve(g8); bC = channel_curve(b8)

    # Blue blend
    r_f, g_f, b_f = s[...,0].ravel(), s[...,1].ravel(), s[...,2].ravel()
    blue_dom = b_f - np.maximum(r_f, g_f)
    blue_mask = blue_dom > 0.02
    n = r_f.size
    blue_count = blue_mask.sum()
    if blue_count > 500:
        blue_b8 = b8.ravel()[blue_mask]
        blueCurve = channel_curve(blue_b8)
        blueRatio = min(blue_count/n, 1.0)
        baseWeight = min(0.25+0.55*blueRatio, 0.8)
        for i in range(256):
            hm = min(max((i-32)/223.0, 0.0), 1.0)
            w_ = baseWeight * hm
            bC[i] = int(round((1-w_)*bC[i]+w_*blueCurve[i]))
            bC[i] = min(max(bC[i],0),255)
        for i in range(1,256):
            if bC[i]<bC[i-1]: bC[i]=bC[i-1]

    # Zone Lab casts
    lab = to_lab(s)
    L = lab[...,0].ravel(); a = lab[...,1].ravel(); b_ = lab[...,2].ravel()
    blue_cast = blue_count/n if n>0 else 0
    tint_str = min(0.15 + 0.12*(blue_count/(n*55.0) if blue_count>0 else 0), 0.30)
    # simplified blueCastStrength
    sc_dict = {}
    for zone, mask in [('s', L<35), ('m', (L>=35)&(L<65)), ('h', L>=65)]:
        sc_dict[zone] = (a[mask].mean() if mask.sum()>10 else 0,
                         b_[mask].mean() if mask.sum()>10 else 0)

    DIM = 33
    lut = np.zeros((DIM,DIM,DIM,3), dtype=np.float32)
    for ri in range(DIM):
        for gi in range(DIM):
            for bi in range(DIM):
                r_8 = int(round(ri/32*255)); g_8 = int(round(gi/32*255)); b_8 = int(round(bi/32*255))
                r1 = rC[r_8]/255.0; g1 = gC[g_8]/255.0; b1 = bC[b_8]/255.0
                lab_px = to_lab(np.array([[[r1,g1,b1]]],dtype=np.float32))[0,0]
                Lv = lab_px[0]
                def gw(l, c, sig=25.0): return math.exp(-0.5*(l-c)**2/sig**2)
                ws=gw(Lv,17.5); wm=gw(Lv,50.0); wh=gw(Lv,82.5); wt=ws+wm+wh+1e-10
                zA=(ws*sc_dict['s'][0]+wm*sc_dict['m'][0]+wh*sc_dict['h'][0])/wt
                zB=(ws*sc_dict['s'][1]+wm*sc_dict['m'][1]+wh*sc_dict['h'][1])/wt
                aOut=np.clip(lab_px[1]+tint_str*zA,-110,110)
                bOut=np.clip(lab_px[2]+tint_str*zB,-110,110)
                out=from_lab(np.array([[[Lv,aOut,bOut]]],dtype=np.float32))[0,0]
                lut[ri,gi,bi]=out
    return lut

# ─── Approach B: Simple Lab mean/std transfer (Reinhard) ─────────────────────

# Neutral Lab stats (fixed constants from spec)
MU_L, SIG_L = 50.0, 18.0
MU_A, SIG_A =  0.0,  8.0
MU_B, SIG_B =  0.0,  8.0

def generate_lut_simple(style_f32):
    """New approach: Lab mean/std transfer only."""
    h,w = style_f32.shape[:2]
    if max(h,w) > 512:
        sc = 512/max(h,w)
        p = Image.fromarray((style_f32*255).astype(np.uint8))
        p = p.resize((int(w*sc),int(h*sc)), Image.LANCZOS)
        s = np.array(p)/255.0
    else:
        s = style_f32

    lab = to_lab(s.astype(np.float32))
    muL_s  = float(lab[...,0].mean()); sigL_s = float(lab[...,0].std())
    muA_s  = float(lab[...,1].mean()); sigA_s = float(lab[...,1].std())
    muB_s  = float(lab[...,2].mean()); sigB_s = float(lab[...,2].std())

    # ratio clamp 0.5~2.0
    rL = np.clip(sigL_s/SIG_L, 0.5, 2.0)
    rA = np.clip(sigA_s/SIG_A, 0.5, 2.0)
    rB = np.clip(sigB_s/SIG_B, 0.5, 2.0)

    print(f"      Style Lab stats: μL={muL_s:.1f} σL={sigL_s:.1f} | "
          f"μa={muA_s:.1f} σa={sigA_s:.1f} | μb={muB_s:.1f} σb={sigB_s:.1f}")
    print(f"      Ratios: rL={rL:.2f} rA={rA:.2f} rB={rB:.2f}")

    DIM = 33
    lut = np.zeros((DIM,DIM,DIM,3), dtype=np.float32)
    for ri in range(DIM):
        for gi in range(DIM):
            for bi in range(DIM):
                rgb = np.array([[[ri/32, gi/32, bi/32]]], dtype=np.float32)
                lab_px = to_lab(rgb)[0,0]
                L2 = (lab_px[0] - MU_L)*rL + muL_s
                a2 = (lab_px[1] - MU_A)*rA + muA_s
                b2 = (lab_px[2] - MU_B)*rB + muB_s
                out = from_lab(np.array([[[L2,a2,b2]]],dtype=np.float32))[0,0]
                lut[ri,gi,bi] = np.clip(out,0,1)
    return lut

# ─── Approach C: Simple + tone curve (spec full method) ──────────────────────

def build_style_cdf(L_channel_flat):
    hist = np.zeros(256)
    indices = (L_channel_flat / 100.0 * 255).clip(0,255).astype(int)
    for i in indices: hist[i] += 1
    hist /= hist.sum()
    return np.cumsum(hist)

# Fixed neutral L CDF: N(mu=50, sig=18) in Lab L space [0..100] → 256 bins
def build_neutral_L_cdf():
    mu, sig = 50.0, 18.0
    bins = np.arange(256) * 100.0 / 255.0
    h = np.exp(-0.5*((bins-mu)/sig)**2)
    h /= h.sum()
    return np.cumsum(h)

NEUTRAL_L_CDF = build_neutral_L_cdf()

def build_tone_curve(style_L_cdf):
    curve = np.zeros(256)
    for i in range(256):
        target = NEUTRAL_L_CDF[i]
        j = int(np.searchsorted(style_L_cdf, target, side='left'))
        curve[i] = min(j, 255)
    for i in range(1,256):
        if curve[i] < curve[i-1]: curve[i] = curve[i-1]
    return curve  # maps neutral 256-bin index → style 256-bin index

def generate_lut_full(style_f32):
    """Spec full method: tone curve on L + mean/std on a,b."""
    h,w = style_f32.shape[:2]
    if max(h,w) > 512:
        sc = 512/max(h,w)
        p = Image.fromarray((style_f32*255).astype(np.uint8))
        p = p.resize((int(w*sc),int(h*sc)), Image.LANCZOS)
        s = np.array(p)/255.0
    else:
        s = style_f32

    lab = to_lab(s.astype(np.float32))
    muL_s  = float(lab[...,0].mean()); sigL_s = float(lab[...,0].std())
    muA_s  = float(lab[...,1].mean()); sigA_s = float(lab[...,1].std())
    muB_s  = float(lab[...,2].mean()); sigB_s = float(lab[...,2].std())

    rA = np.clip(sigA_s/SIG_A, 0.5, 2.0)
    rB = np.clip(sigB_s/SIG_B, 0.5, 2.0)

    # Build tone curve for L
    style_L_cdf = build_style_cdf(lab[...,0].ravel())
    tone_curve = build_tone_curve(style_L_cdf)

    DIM = 33
    lut = np.zeros((DIM,DIM,DIM,3), dtype=np.float32)
    for ri in range(DIM):
        for gi in range(DIM):
            for bi in range(DIM):
                rgb = np.array([[[ri/32, gi/32, bi/32]]], dtype=np.float32)
                lab_px = to_lab(rgb)[0,0]

                # Tone curve on L (256-bin index)
                L_idx = int(lab_px[0]/100*255)
                L1 = tone_curve[L_idx]  # still in 256-bin space
                # Convert back to Lab L [0..100]
                L1_lab = L1 / 255.0 * 100.0

                # Mean/std shift on all channels
                L2 = (L1_lab - MU_L) * np.clip(sigL_s/SIG_L, 0.5, 2.0) + muL_s
                a2 = (lab_px[1] - MU_A) * rA + muA_s
                b2 = (lab_px[2] - MU_B) * rB + muB_s

                out = from_lab(np.array([[[L2,a2,b2]]],dtype=np.float32))[0,0]
                lut[ri,gi,bi] = np.clip(out,0,1)
    return lut

# ─── Run comparison ───────────────────────────────────────────────────────────

def load(path):
    return np.array(Image.open(path).convert('RGB'), dtype=np.float32)/255.0

def run_pair(n):
    print(f"\n{'='*62}")
    print(f"  PAIR {n}")
    print(f"{'='*62}")

    style = load(f"{TEST_DIR}/보정본_{n}.jpg")
    orig  = load(f"{TEST_DIR}/원본_{n}.jpg")

    # Resize style to orig size for comparison
    if style.shape != orig.shape:
        p = Image.fromarray((style*255).astype(np.uint8))
        p = p.resize((orig.shape[1], orig.shape[0]), Image.LANCZOS)
        style = np.array(p)/255.0

    corr_u8 = (style*255).round().astype(np.uint8)
    corr_lab = to_lab(style)

    results = {}

    for name, gen_fn in [
        ("A. Current (RGB hist match)", generate_lut_current),
        ("B. Simple  (Lab μ/σ only)  ", generate_lut_simple),
        ("C. Full    (tone curve + μ/σ)", generate_lut_full),
    ]:
        print(f"\n  [{name}]")
        lut = gen_fn(style)
        filt = apply_lut_trilinear(orig, lut)

        filt_u8  = (filt*255).round().astype(np.uint8)
        filt_lab = to_lab(filt)

        dE   = delta_e(corr_lab, filt_lab)
        ps   = psnr(corr_u8, filt_u8)
        mae  = mae_rgb(corr_u8, filt_u8)
        bl_dE, bl_cnt = blue_delta_e(style, filt)

        orig_lab = to_lab(orig)
        dE_base  = delta_e(corr_lab, orig_lab)
        recover  = max(0, (dE_base-dE)/dE_base*100)

        print(f"    Delta E:      {dE:.2f}   (baseline {dE_base:.2f}, recovery {recover:.1f}%)")
        print(f"    PSNR:         {ps:.1f} dB")
        print(f"    MAE R/G/B:    {mae[0]:.2f} / {mae[1]:.2f} / {mae[2]:.2f}")
        if bl_dE is not None:
            print(f"    Blue dE:      {bl_dE:.2f}  ({bl_cnt} blue px)")

        results[name.strip()] = {'dE': dE, 'psnr': ps, 'mae': mae,
                                  'blue_dE': bl_dE, 'recover': recover}

    return results

if __name__ == '__main__':
    print("Comparing 3 approaches on test pairs...")
    print("  A = current code  (RGB per-channel histogram matching + zone Lab tint)")
    print("  B = simple        (Lab mean/std transfer, 6 numbers)")
    print("  C = full spec     (tone curve on L + Lab mean/std on a,b)")

    r1 = run_pair(1)
    r2 = run_pair(2)

    print(f"\n{'='*62}")
    print("  SUMMARY")
    print(f"{'='*62}")
    print(f"\n  {'Approach':<38} {'dE P1':>6} {'dE P2':>6} {'avg dE':>7} {'avg recover':>12}")
    print(f"  {'-'*38} {'-'*6} {'-'*6} {'-'*7} {'-'*12}")
    for key in r1:
        dE1 = r1[key]['dE']; dE2 = r2[key]['dE']
        av = (dE1+dE2)/2
        rv = (r1[key]['recover']+r2[key]['recover'])/2
        print(f"  {key:<38} {dE1:>6.2f} {dE2:>6.2f} {av:>7.2f} {rv:>11.1f}%")

    print(f"\n  {'Approach':<38} {'blue dE P1':>10} {'blue dE P2':>10}")
    print(f"  {'-'*38} {'-'*10} {'-'*10}")
    for key in r1:
        b1 = r1[key]['blue_dE']; b2 = r2[key]['blue_dE']
        s1 = f"{b1:.2f}" if b1 else "N/A"
        s2 = f"{b2:.2f}" if b2 else "N/A"
        print(f"  {key:<38} {s1:>10} {s2:>10}")
