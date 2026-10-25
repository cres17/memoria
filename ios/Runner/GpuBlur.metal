// Precise blur: compile this file with -fno-fast-math.
#include <metal_stdlib>
using namespace metal;

struct BlurParams { int lines; int length; int lineStride; int step; int radius; int channels; };

// fast_blur.dart의 반사 규칙과 탭 순서, 정수 버림을 유지한다.
// CPU는 double, 이 커널은 float로 합산하므로 바이트 동일성은 보장하지 않는다.
kernel void blur_pass(device const uchar *from [[buffer(0)]],
                      device uchar *to [[buffer(1)]],
                      constant BlurParams &p [[buffer(2)]],
                      device const float *k [[buffer(3)]],
                      uint2 pos [[thread_position_in_grid]]) {
  int x = int(pos.x), line = int(pos.y);
  if (x >= p.length || line >= p.lines) return;
  int base = line * p.lineStride;
  float r = 0.0f, g = 0.0f, b = 0.0f, a = 0.0f;
  for (int j = -p.radius, t = 0; j <= p.radius; ++j, ++t) {
    int q = x + j;
    int gpos = q < 0 ? -q : (q >= p.length ? p.length - (q - p.length) - 1 : q);
    int i = base + gpos * p.step;
    float c = k[t];
    r += c * float(from[i]); g += c * float(from[i + 1]); b += c * float(from[i + 2]);
    if (p.channels == 4) a += c * float(from[i + 3]);
  }
  int d = base + x * p.step;
  to[d] = uchar(int(r)); to[d + 1] = uchar(int(g)); to[d + 2] = uchar(int(b));
  if (p.channels == 4) to[d + 3] = uchar(int(a));
}
