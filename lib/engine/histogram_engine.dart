import 'dart:typed_data';

/// 256-bin histogram for R, G, B, and luminance channels.
/// All counts are raw pixel counts (not normalized).
/// Isolate-safe: takes only Uint8List + dimensions, no Flutter objects.
class HistogramData {
  final Uint32List r;
  final Uint32List g;
  final Uint32List b;
  final Uint32List luminance;

  const HistogramData({
    required this.r,
    required this.g,
    required this.b,
    required this.luminance,
  });

  /// Peak count across all four channels (useful for normalization).
  int get peak {
    int m = 0;
    for (int i = 0; i < 256; i++) {
      if (r[i] > m) m = r[i];
      if (g[i] > m) m = g[i];
      if (b[i] > m) m = b[i];
      if (luminance[i] > m) m = luminance[i];
    }
    return m;
  }
}

/// Compute a 256-bin histogram from raw RGBA or RGB bytes.
///
/// [rgbaBytes]: raw pixel data from img.Image (3 or 4 bytes per pixel).
/// [numChannels]: 3 for RGB, 4 for RGBA.
///
/// Top-level function so it can be passed to [compute()].
HistogramData computeHistogram(HistogramArgs args) {
  final bytes = args.bytes;
  final nc = args.numChannels;
  final r = Uint32List(256);
  final g = Uint32List(256);
  final b = Uint32List(256);
  final lum = Uint32List(256);

  if (nc < 3) {
    throw ArgumentError.value(nc, 'numChannels', 'must be at least 3');
  }

  final n = bytes.length - (bytes.length % nc);
  for (int i = 0; i + 2 < n; i += nc) {
    final rv = bytes[i];
    final gv = bytes[i + 1];
    final bv = bytes[i + 2];
    r[rv]++;
    g[gv]++;
    b[bv]++;
    // BT.601 integer luminance: (77*R + 150*G + 29*B) >> 8
    final l = (77 * rv + 150 * gv + 29 * bv) >> 8;
    lum[l.clamp(0, 255)]++;
  }

  return HistogramData(r: r, g: g, b: b, luminance: lum);
}

/// Argument bundle for [computeHistogram] (compute() needs a single argument).
class HistogramArgs {
  final Uint8List bytes;
  final int numChannels;
  const HistogramArgs(this.bytes, this.numChannels);
}
