/// Run from project root: dart run tool/generate_thumbs.dart
/// Uses the project's own 'image' package to generate 128x128 JPEG thumbnails.
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  Directory('assets/images').createSync(recursive: true);

  _gen('original', _original);
  _gen('vivid',    _vivid);
  _gen('cool',     _cool);
  _gen('warm',     _warm);
  _gen('fade',     _fade);
  _gen('noir',     _noir);
  _gen('pastel',   _pastel);
  _gen('golden',   _golden);

  print('Done — 8 thumbnails written to assets/images/');
}

void _gen(String id, _ColorFn fn) {
  const size = 128;
  final image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final c = fn(x / (size - 1), y / (size - 1));
      image.setPixelRgb(x, y,
        (c.$1 * 255).round().clamp(0, 255),
        (c.$2 * 255).round().clamp(0, 255),
        (c.$3 * 255).round().clamp(0, 255),
      );
    }
  }
  final jpg = img.encodeJpg(image, quality: 88);
  File('assets/images/${id}_thumb.jpg').writeAsBytesSync(jpg);
  print('  [$id] assets/images/${id}_thumb.jpg');
}

typedef _ColorFn = (double r, double g, double b) Function(double tx, double ty);

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _sCurve(double x, double s) => x + (x * x * (3 - 2 * x) - x) * s;

// Original: neutral grey-to-white diagonal
(double, double, double) _original(double tx, double ty) {
  final v = _lerp(0.18, 0.88, (tx + ty) / 2);
  return (v, v, v);
}

// Vivid: high-saturation rainbow sweep
(double, double, double) _vivid(double tx, double ty) {
  final r = _sCurve(_lerp(0.9, 0.1, tx), 0.2);
  final g = _sCurve(_lerp(0.1, 0.8, tx * 0.7 + ty * 0.3), 0.15);
  final b = _sCurve(_lerp(0.1, 0.95, ty), 0.2);
  return (r, g, b);
}

// Cool: blue-teal gradient
(double, double, double) _cool(double tx, double ty) {
  final t = (tx + ty) / 2;
  return (_lerp(0.08, 0.45, t), _lerp(0.30, 0.72, t), _lerp(0.55, 0.98, t));
}

// Warm: amber-gold gradient
(double, double, double) _warm(double tx, double ty) {
  final t = (tx + ty) / 2;
  return (_lerp(0.55, 1.0, t), _lerp(0.30, 0.72, t), _lerp(0.02, 0.22, t));
}

// Fade: matte desaturated
(double, double, double) _fade(double tx, double ty) {
  final t = (tx * 0.6 + ty * 0.4);
  final base = _lerp(0.18, 0.82, t);
  return (base + 0.02, base, base + 0.06);
}

// Noir: high-contrast greyscale with slight blue tint
(double, double, double) _noir(double tx, double ty) {
  final t = (tx * 0.5 + ty * 0.5);
  final v = _sCurve(t, 0.45);
  return (v * 0.90, v * 0.92, v * 1.00);
}

// Pastel: soft pink-lavender
(double, double, double) _pastel(double tx, double ty) {
  final t = (tx + ty) / 2;
  return (_lerp(0.82, 0.98, t), _lerp(0.70, 0.88, t), _lerp(0.80, 0.95, t));
}

// Golden: warm gold → orange sunset
(double, double, double) _golden(double tx, double ty) {
  final t = (tx * 0.7 + ty * 0.3);
  return (_lerp(0.60, 1.0, t), _lerp(0.38, 0.72, t), _lerp(0.02, 0.16, t));
}
