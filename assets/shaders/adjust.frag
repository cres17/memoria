#include <flutter/runtime_effect.glsl>

// ── Samplers ────────────────────────────────────────────────
uniform sampler2D uTexture;     // source photo (ui.Image → ImageShader)

// 3D LUT: 65×65×65 packed into a 2D atlas (4225 × 65 RGBA8).
// Slice s lays out as row s, columns [0..64].
// Atlas width  W = 65 * 65 = 4225
// Atlas height H = 65
// uLutEnabled == 0.0 → skip LUT lookup
uniform sampler2D uLut;
uniform float     uLutEnabled;  // 0.0 or 1.0
uniform float     uLutDim;      // 65.0
uniform float     uIntensity;   // 0.0 – 1.0  (filter strength)

// 1D curve LUTs (256 × 1 RGBA8, packed as: R=rgb, G=red, B=green, A=blue)
// uCurveEnabled == 0.0 → skip curve application
uniform sampler2D uCurve1D;
uniform float     uCurveEnabled;

// Luminance curve: 256 × 1 R8 texture (delta encoded: value − 0.5 maps to [-0.5,+0.5])
uniform sampler2D uLumCurve;
uniform float     uLumCurveEnabled;

// ── Adjust uniforms ─────────────────────────────────────────
uniform float uExposure;      // –2.0 … +2.0  (stops)
uniform float uContrast;      // –100 … +100
uniform float uSaturation;    // –100 … +100
uniform float uTemperature;   // –100 … +100
uniform float uTint;          // –100 … +100
uniform float uHighlights;    // –100 … +100
uniform float uShadows;       // –100 … +100
uniform float uAmbiance;      // –100 … +100
uniform float uVignette;      // 0 … 100
// sharpen/clarity/structure stay CPU-side (require neighbour samples / multi-pass)

// B&W mixer
uniform float uBnwEnabled;    // 0 or 1
uniform float uBnwRed;        // –100 … +100
uniform float uBnwGreen;
uniform float uBnwBlue;
uniform float uBnwYellow;

// Tonal contrast (zone-based)
uniform float uTonalShadows;     // –100 … +100
uniform float uTonalMidtones;
uniform float uTonalHighlights;

// HSL per-band adjustments (Sprint 2)
// 8 bands: red/orange/yellow/green/cyan/blue/purple/magenta
// Each has hue (-180..+180), saturation (-100..+100), luminance (-100..+100)
uniform vec3 uHslRed;      // (hue, sat, lum)
uniform vec3 uHslOrange;
uniform vec3 uHslYellow;
uniform vec3 uHslGreen;
uniform vec3 uHslCyan;
uniform vec3 uHslBlue;
uniform vec3 uHslPurple;
uniform vec3 uHslMagenta;
uniform float uHslEnabled; // 0 or 1

// Split Toning (Sprint 3)
// Shadow: x=hue(0..360), y=sat(0..100); Highlight: x=hue, y=sat; z=balance(-100..+100)
uniform vec3 uSplitShadow;    // (hue, sat, unused)
uniform vec3 uSplitHighlight; // (hue, sat, unused)
uniform float uSplitBalance;  // -100 .. +100
uniform float uSplitEnabled;  // 0 or 1

// Film Grain (Sprint 3)
uniform float uGrainStrength; // 0 .. 100
uniform float uGrainSize;     // 0.5 .. 3.0
uniform float uGrainSeed;     // integer seed cast to float

// Resolution (pixels) — passed from Dart
uniform vec2  uResolution;
uniform vec2  uOrigin;

out vec4 fragColor;

// ── Helpers ─────────────────────────────────────────────────

float luminance(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Apply 3D LUT via trilinear interpolation on the 2D atlas.
// Atlas layout: dim=65, atlasW = dim*dim, atlasH = dim
// texel (r_idx + b_idx*dim,  g_idx) / (atlasW, atlasH)
vec3 applyLut(vec3 c) {
  float dim    = uLutDim;
  float maxIdx = dim - 1.0;
  float atlasW = dim * dim;
  float atlasH = dim;

  vec3 scaled = clamp(c, 0.0, 1.0) * maxIdx;
  vec3 lo     = floor(scaled);
  vec3 hi     = min(lo + 1.0, maxIdx);
  vec3 f      = scaled - lo;

  // Atlas UV for a lattice point (r, g, b):
  //   u = (r + b * dim + 0.5) / atlasW
  //   v = (g             + 0.5) / atlasH
  #define LUT_UV(r,g,b) vec2((r + b*dim + 0.5)/atlasW, (g + 0.5)/atlasH)

  vec3 c000 = texture(uLut, LUT_UV(lo.r, lo.g, lo.b)).rgb;
  vec3 c100 = texture(uLut, LUT_UV(hi.r, lo.g, lo.b)).rgb;
  vec3 c010 = texture(uLut, LUT_UV(lo.r, hi.g, lo.b)).rgb;
  vec3 c110 = texture(uLut, LUT_UV(hi.r, hi.g, lo.b)).rgb;
  vec3 c001 = texture(uLut, LUT_UV(lo.r, lo.g, hi.b)).rgb;
  vec3 c101 = texture(uLut, LUT_UV(hi.r, lo.g, hi.b)).rgb;
  vec3 c011 = texture(uLut, LUT_UV(lo.r, hi.g, hi.b)).rgb;
  vec3 c111 = texture(uLut, LUT_UV(hi.r, hi.g, hi.b)).rgb;

  vec3 c00 = mix(c000, c100, f.r);
  vec3 c10 = mix(c010, c110, f.r);
  vec3 c01 = mix(c001, c101, f.r);
  vec3 c11 = mix(c011, c111, f.r);
  vec3 c0  = mix(c00,  c10,  f.g);
  vec3 c1  = mix(c01,  c11,  f.g);
  return mix(c0, c1, f.b);
}

// Curve 1D lookup — texture row 0, 256 columns.
// Packed: R channel = rgb master, G = red, B = green, A = blue
vec3 applyCurves(vec3 c) {
  float u_r = (clamp(c.r, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  float u_g = (clamp(c.g, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  float u_b = (clamp(c.b, 0.0, 1.0) * 255.0 + 0.5) / 256.0;

  // RGB master curve (R channel of texture)
  vec4 rgb_r = texture(uCurve1D, vec2(u_r, 0.5));
  vec4 rgb_g = texture(uCurve1D, vec2(u_g, 0.5));
  vec4 rgb_b = texture(uCurve1D, vec2(u_b, 0.5));
  c.r = rgb_r.r;
  c.g = rgb_g.r;
  c.b = rgb_b.r;

  // Per-channel curves (G=red, B=green, A=blue)
  float u2_r = (clamp(c.r, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  float u2_g = (clamp(c.g, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  float u2_b = (clamp(c.b, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  c.r = texture(uCurve1D, vec2(u2_r, 0.5)).g;
  c.g = texture(uCurve1D, vec2(u2_g, 0.5)).b;
  c.b = texture(uCurve1D, vec2(u2_b, 0.5)).a;

  return c;
}

// Luminance curve: delta texture, value 0.5 → delta 0.0
vec3 applyLumCurve(vec3 c) {
  float lum = luminance(c);
  float u   = (clamp(lum, 0.0, 1.0) * 255.0 + 0.5) / 256.0;
  float raw = texture(uLumCurve, vec2(u, 0.5)).r; // [0,1]
  float delta = raw - 0.5;                          // [–0.5, +0.5]
  return clamp(c + delta, 0.0, 1.0);
}

// Gaussian weight for tonal zone
float zonalWeight(float lum, float center) {
  const float sigma = 0.2;
  float d = lum - center;
  return exp(-0.5 * d * d / (sigma * sigma));
}

// ── HSL helpers ─────────────────────────────────────────────

vec3 rgbToHsl(vec3 c) {
  float mx = max(c.r, max(c.g, c.b));
  float mn = min(c.r, min(c.g, c.b));
  float l  = (mx + mn) * 0.5;
  if (mx == mn) return vec3(0.0, 0.0, l);
  float d  = mx - mn;
  float s  = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
  float h;
  if (mx == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
  else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
  else                h = (c.r - c.g) / d + 4.0;
  return vec3(h * 60.0, s, l);
}

float hue2rgb(float p, float q, float t) {
  if (t < 0.0) t += 1.0;
  if (t > 1.0) t -= 1.0;
  if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
  if (t < 0.5)     return q;
  if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
  return p;
}

vec3 hslToRgb(vec3 hsl) {
  float h = hsl.x / 360.0;
  float s = hsl.y;
  float l = hsl.z;
  if (s == 0.0) return vec3(l);
  float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
  float p = 2.0 * l - q;
  return vec3(hue2rgb(p, q, h + 1.0/3.0),
              hue2rgb(p, q, h),
              hue2rgb(p, q, h - 1.0/3.0));
}

float bandWeight(float hue, float center) {
  const float sigma = 35.0;
  float d = abs(hue - center);
  if (d > 180.0) d = 360.0 - d;
  return exp(-0.5 * d * d / (sigma * sigma));
}

vec3 applyHslBands(vec3 c) {
  vec3 hsl = rgbToHsl(c);
  float h = hsl.x;

  // band centers (degrees)
  const vec4 centers1 = vec4(0.0, 30.0, 60.0, 120.0);   // R, O, Y, G
  const vec4 centers2 = vec4(180.0, 240.0, 280.0, 320.0); // C, B, P, M

  // gather weights
  float w0 = bandWeight(h, centers1.x); // red
  float w1 = bandWeight(h, centers1.y); // orange
  float w2 = bandWeight(h, centers1.z); // yellow
  float w3 = bandWeight(h, centers1.w); // green
  float w4 = bandWeight(h, centers2.x); // cyan
  float w5 = bandWeight(h, centers2.y); // blue
  float w6 = bandWeight(h, centers2.z); // purple
  float w7 = bandWeight(h, centers2.w); // magenta

  float totalW = w0+w1+w2+w3+w4+w5+w6+w7;
  if (totalW < 1e-6) return c;

  float dh = (w0*uHslRed.x + w1*uHslOrange.x + w2*uHslYellow.x + w3*uHslGreen.x
            + w4*uHslCyan.x + w5*uHslBlue.x  + w6*uHslPurple.x + w7*uHslMagenta.x) / totalW;
  float ds = (w0*uHslRed.y + w1*uHslOrange.y + w2*uHslYellow.y + w3*uHslGreen.y
            + w4*uHslCyan.y + w5*uHslBlue.y  + w6*uHslPurple.y + w7*uHslMagenta.y) / totalW / 100.0;
  float dl = (w0*uHslRed.z + w1*uHslOrange.z + w2*uHslYellow.z + w3*uHslGreen.z
            + w4*uHslCyan.z + w5*uHslBlue.z  + w6*uHslPurple.z + w7*uHslMagenta.z) / totalW / 100.0;

  float newH = mod(hsl.x + dh + 360.0, 360.0);
  float newS = clamp(hsl.y + ds, 0.0, 1.0);
  float newL = clamp(hsl.z + dl, 0.0, 1.0);

  return hslToRgb(vec3(newH, newS, newL));
}

// ── Split Toning ─────────────────────────────────────────────

vec3 applySplitToning(vec3 c) {
  float lum = luminance(c);
  float splitPoint = 0.5 + uSplitBalance / 200.0;

  float shadowW = 1.0 - clamp(lum / max(splitPoint, 1e-4), 0.0, 1.0);
  float highW   = clamp((lum - splitPoint) / max(1.0 - splitPoint, 1e-4), 0.0, 1.0);

  if (uSplitShadow.y > 0.0 && shadowW > 1e-4) {
    float hRad = uSplitShadow.x * 3.14159265 / 180.0;
    float str  = uSplitShadow.y / 100.0 * shadowW;
    c.r = clamp(c.r + str * cos(hRad) * 0.5, 0.0, 1.0);
    c.g = clamp(c.g + str * cos(hRad - 2.094) * 0.5, 0.0, 1.0);
    c.b = clamp(c.b + str * cos(hRad + 2.094) * 0.5, 0.0, 1.0);
  }
  if (uSplitHighlight.y > 0.0 && highW > 1e-4) {
    float hRad = uSplitHighlight.x * 3.14159265 / 180.0;
    float str  = uSplitHighlight.y / 100.0 * highW;
    c.r = clamp(c.r + str * cos(hRad) * 0.5, 0.0, 1.0);
    c.g = clamp(c.g + str * cos(hRad - 2.094) * 0.5, 0.0, 1.0);
    c.b = clamp(c.b + str * cos(hRad + 2.094) * 0.5, 0.0, 1.0);
  }
  return c;
}

// ── Film Grain (screen-space, luma-weighted) ─────────────────
// Hash-based value noise matching the CPU _applyGrainImage implementation.
float grainHash(float x, float y, float seed) {
  // Integer-style hash in float arithmetic.
  float h = fract(sin(dot(vec2(x, y) + seed * 0.017, vec2(12.9898, 78.233))) * 43758.5453);
  return h * 2.0 - 1.0; // [-1, +1]
}

vec3 applyGrain(vec3 c, vec2 fragCoord) {
  float invSize = 1.0 / clamp(uGrainSize, 0.5, 3.0);
  float tx = floor(fragCoord.x * invSize);
  float ty = floor(fragCoord.y * invSize);

  float noise = grainHash(tx, ty, uGrainSeed);

  float lum = luminance(c);
  float weight = 1.0 - (lum - 0.5) * (lum - 0.5) * 4.0;

  float delta = noise * (uGrainStrength / 100.0) * weight * (25.0 / 255.0);
  return clamp(c + delta, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────
void main() {
  vec2 uv = (FlutterFragCoord().xy - uOrigin) / uResolution;
  vec3 c  = texture(uTexture, uv).rgb;

  // ── 1. 3D LUT (film simulation / custom filter) ──────────
  vec3 base = (uLutEnabled > 0.5) ? applyLut(c) : c;

  // Intensity mix: blend between original and LUT result
  base = mix(c, base, clamp(uIntensity, 0.0, 1.0));

  // ── 2. Exposure ──────────────────────────────────────────
  base *= pow(2.0, uExposure);

  // ── 3. Contrast ──────────────────────────────────────────
  if (abs(uContrast) > 0.01) {
    float f = (259.0 * (uContrast + 255.0)) / (255.0 * (259.0 - uContrast));
    base = f * (base - 0.5) + 0.5;
  }

  // ── 4. Saturation ────────────────────────────────────────
  if (abs(uSaturation) > 0.01) {
    float lum = luminance(base);
    float s   = 1.0 + uSaturation / 100.0;
    base = mix(vec3(lum), base, s);
  }

  // ── 4b. HSL per-band ─────────────────────────────────────
  if (uHslEnabled > 0.5) {
    base = applyHslBands(base);
  }

  // ── 4c. Split Toning ─────────────────────────────────────
  if (uSplitEnabled > 0.5) {
    base = applySplitToning(base);
  }

  // ── 5. Temperature / Tint ────────────────────────────────
  base.r += uTemperature / 1000.0;
  base.b -= uTemperature / 1000.0;
  base.g += uTint / 1000.0;
  base.r -= uTint / 2000.0;

  // ── 6. Highlights / Shadows ──────────────────────────────
  if (abs(uHighlights) > 0.01) {
    float lum  = luminance(base);
    float mask = clamp(lum - 0.5, 0.0, 0.5) * 2.0;
    base += uHighlights / 100.0 * mask * 0.5;
  }
  if (abs(uShadows) > 0.01) {
    float lum  = luminance(base);
    float mask = clamp(0.5 - lum, 0.0, 0.5) * 2.0;
    base += uShadows / 100.0 * mask * 0.5;
  }

  // ── 6b. Ambiance ──────────────────────────────────────────
  if (abs(uAmbiance) > 0.01) {
    float lum = clamp(luminance(base), 0.0, 1.0);
    float a = uAmbiance / 100.0;
    float shadowMask = (1.0 - lum) * (1.0 - lum);
    float highlightMask = lum * lum;
    float brightAdj = a * (0.22 * shadowMask - 0.15 * highlightMask);
    base += brightAdj;

    float satMask = 4.0 * lum * (1.0 - lum);
    float satFactor = 1.0 + a * 0.35 * satMask;
    float newLum = clamp(luminance(base), 0.0, 1.0);
    base = mix(vec3(newLum), base, satFactor);
  }

  // ── 7. Curves (RGB master + per-channel) ─────────────────
  if (uCurveEnabled > 0.5) {
    base = applyCurves(base);
  }

  // ── 8. Luminance curve ───────────────────────────────────
  if (uLumCurveEnabled > 0.5) {
    base = applyLumCurve(base);
  }

  // ── 9. Tonal contrast ────────────────────────────────────
  if (abs(uTonalShadows) > 0.01 || abs(uTonalMidtones) > 0.01 || abs(uTonalHighlights) > 0.01) {
    float lum = luminance(base);
    float ws  = zonalWeight(lum, 0.15);
    float wm  = zonalWeight(lum, 0.50);
    float wh  = zonalWeight(lum, 0.85);
    float tot = ws + wm + wh + 1e-6;

    float adjS = lum + (uTonalShadows    / 100.0) * (1.0 - lum) * 0.25;
    float adjM = lum + (uTonalMidtones   / 100.0) * (lum - 0.5) * 0.25;
    float adjH = lum + (uTonalHighlights / 100.0) * lum          * 0.25;

    float newLum = (ws * adjS + wm * adjM + wh * adjH) / tot;
    base += (newLum - lum);
  }

  // ── 10. B&W mixer ────────────────────────────────────────
  if (uBnwEnabled > 0.5) {
    float wr = 0.299 + uBnwRed    / 100.0 * 0.3;
    float wg = 0.587 + uBnwGreen  / 100.0 * 0.3;
    float wb = 0.114 + uBnwBlue   / 100.0 * 0.3;
    float wy =         uBnwYellow / 100.0 * 0.2;
    float L  = base.r * wr + base.g * wg + base.b * wb + (base.r + base.g) * 0.5 * wy;
    base = vec3(clamp(L, 0.0, 1.0));
  }

  // ── 11. Vignette (elliptical, all edges) ─────────────────
  if (uVignette > 0.01) {
    vec2  dc   = (uv - 0.5) * 2.0;  // –1..1 on both axes
    float dist = length(dc) / sqrt(2.0);
    float mask = 1.0 - dist * dist * (uVignette / 100.0) * 1.2;
    base *= clamp(mask, 0.0, 1.0);
  }

  // ── 12. Film Grain ───────────────────────────────────────
  if (uGrainStrength > 0.01) {
    base = applyGrain(base, FlutterFragCoord().xy);
  }

  fragColor = vec4(clamp(base, 0.0, 1.0), 1.0);
}
