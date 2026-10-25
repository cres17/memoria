// Port of memoria-gpu-bench: fast NR, identical formulas.

#define USE_FAST 1
#include <metal_stdlib>
using namespace metal;

#ifdef USE_FAST
  #define PW(a,b) fast::pow(a,b)
  #define EX(a) fast::exp(a)
#else
  #define PW(a,b) precise::pow(a,b)
  #define EX(a) precise::exp(a)
#endif

constant float XN = 0.95047f;
constant float YN = 1.00000f;
constant float ZN = 1.08883f;

static float linearize(float c) { return c <= 0.04045f ? c / 12.92f : PW((c + 0.055f) / 1.055f, 2.4f); }
static float delinearize(float c) { return c <= 0.0031308f ? 12.92f * c : 1.055f * PW(c, 1.0f / 2.4f) - 0.055f; }
static float fLab(float t) {
  const float d = 6.0f / 29.0f;
  return t > d * d * d ? PW(t, 1.0f / 3.0f) : t / (3.0f * d * d) + 4.0f / 29.0f;
}
static float fInv(float t) {
  const float d = 6.0f / 29.0f;
  return t > d ? t * t * t : 3.0f * d * d * (t - 4.0f / 29.0f);
}

kernel void rgb_to_lab(device const uchar *src [[buffer(0)]],
                       device float4 *lab [[buffer(1)]],
                       constant int &channels [[buffer(2)]],
                       uint gid [[thread_position_in_grid]]) {
  float r = float(src[gid * channels]) / 255.0f;
  float g = float(src[gid * channels + 1]) / 255.0f;
  float b = float(src[gid * channels + 2]) / 255.0f;
  float rl = linearize(r), gl = linearize(g), bl = linearize(b);
  float x = 0.4124564f * rl + 0.3575761f * gl + 0.1804375f * bl;
  float y = 0.2126729f * rl + 0.7151522f * gl + 0.0721750f * bl;
  float z = 0.0193339f * rl + 0.1191920f * gl + 0.9503041f * bl;
  float fx = fLab(x / XN), fy = fLab(y / YN), fz = fLab(z / ZN);
  lab[gid] = float4(116.0f * fy - 16.0f, 500.0f * (fx - fy), 200.0f * (fy - fz), 0.0f);
}

struct NrParams {
  int width; int height;
  int lumRadius; int colRadius;
  float sigRangeL2; float sigRangeC2;
  float detailBlend;
};

kernel void bilateral_lab(device const float4 *lab [[buffer(0)]],
                          device float4 *outLab [[buffer(1)]],
                          constant NrParams &p [[buffer(2)]],
                          device const float *lumSpatial [[buffer(3)]],
                          device const float *colSpatial [[buffer(4)]],
                          uint2 pos [[thread_position_in_grid]]) {
  if (int(pos.x) >= p.width || int(pos.y) >= p.height) return;
  int x = int(pos.x), y = int(pos.y), W = p.width, H = p.height;
  float4 c = lab[y * W + x];
  float oL = c.x, oA = c.y, oB = c.z;
  if (p.lumRadius > 0) {
    int r = p.lumRadius, n = 2 * r + 1;
    float sumL = 0.0f, wSum = 0.0f;
    for (int dy = -r; dy <= r; dy++) {
      int ny = clamp(y + dy, 0, H - 1);
      for (int dx = -r; dx <= r; dx++) {
        int nx = clamp(x + dx, 0, W - 1);
        float nL = lab[ny * W + nx].x;
        float dL = nL - c.x;
        float w = EX(-(dL * dL) / p.sigRangeL2) * lumSpatial[(dy + r) * n + (dx + r)];
        sumL += w * nL; wSum += w;
      }
    }
    float filtered = wSum > 1e-8f ? sumL / wSum : c.x;
    oL = c.x * p.detailBlend + filtered * (1.0f - p.detailBlend);
  }
  if (p.colRadius > 0) {
    int r = p.colRadius, n = 2 * r + 1;
    float sumA = 0.0f, sumB = 0.0f, wSum = 0.0f;
    for (int dy = -r; dy <= r; dy++) {
      int ny = clamp(y + dy, 0, H - 1);
      for (int dx = -r; dx <= r; dx++) {
        int nx = clamp(x + dx, 0, W - 1);
        float4 nb = lab[ny * W + nx];
        float dA = nb.y - c.y, dB = nb.z - c.z;
        float w = EX(-(dA * dA + dB * dB) / p.sigRangeC2) * colSpatial[(dy + r) * n + (dx + r)];
        sumA += w * nb.y; sumB += w * nb.z; wSum += w;
      }
    }
    float fA = wSum > 1e-8f ? sumA / wSum : c.y;
    float fB = wSum > 1e-8f ? sumB / wSum : c.z;
    oA = c.y * p.detailBlend + fA * (1.0f - p.detailBlend);
    oB = c.z * p.detailBlend + fB * (1.0f - p.detailBlend);
  }
  outLab[y * W + x] = float4(oL, oA, oB, 0.0f);
}

// Dart의 double.round()는 0.5에서 0에서 먼 쪽으로 올린다. 값이 0 이상이라 floor(v + 0.5)와 같다.
static uchar to8(float v) { return uchar(clamp(floor(v * 255.0f + 0.5f), 0.0f, 255.0f)); }

kernel void lab_to_rgb(device const float4 *lab [[buffer(0)]],
                       device uchar *dst [[buffer(1)]],
                       device const uchar *src [[buffer(3)]],
                       constant int &channels [[buffer(2)]],
                       uint gid [[thread_position_in_grid]]) {
  float4 c = lab[gid];
  float fy = (c.x + 16.0f) / 116.0f;
  float fx = c.y / 500.0f + fy;
  float fz = fy - c.z / 200.0f;
  float x = fInv(fx) * XN, y = fInv(fy) * YN, z = fInv(fz) * ZN;
  float rl = 3.2404542f * x - 1.5371385f * y - 0.4985314f * z;
  float gl = -0.9692660f * x + 1.8760108f * y + 0.0415560f * z;
  float bl = 0.0556434f * x - 0.2040259f * y + 1.0572252f * z;
  float r = clamp(delinearize(clamp(rl, 0.0f, 1.0f)), 0.0f, 1.0f);
  float g = clamp(delinearize(clamp(gl, 0.0f, 1.0f)), 0.0f, 1.0f);
  float b = clamp(delinearize(clamp(bl, 0.0f, 1.0f)), 0.0f, 1.0f);
  dst[gid * channels] = to8(r); dst[gid * channels + 1] = to8(g); dst[gid * channels + 2] = to8(b);
  if (channels == 4) dst[gid * channels + 3] = src[gid * channels + 3];
}
