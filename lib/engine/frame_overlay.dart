import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Converts legacy opaque RGB frame artwork into an RGBA border overlay.
/// Preview, export, and edit-session playback share this exact contract.
img.Image buildFrameOverlay(
  img.Image frame, {
  double insetFraction = 0.14,
  double featherFraction = 0.018,
}) {
  final width = frame.width;
  final height = frame.height;
  final shortestEdge = math.min(width, height).toDouble();
  final border = shortestEdge * insetFraction.clamp(0.0, 0.45);
  final feather =
      (shortestEdge * featherFraction.clamp(0.0, 0.1)).clamp(1.0, 8.0);
  final overlay = img.Image(width: width, height: height, numChannels: 4);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final edgeDistance = math.min(
        math.min(x.toDouble(), (width - 1 - x).toDouble()),
        math.min(y.toDouble(), (height - 1 - y).toDouble()),
      );
      final keep = ((border - edgeDistance) / feather).clamp(0.0, 1.0);
      final pixel = frame.getPixel(x, y);
      overlay.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        (pixel.a * keep).round(),
      );
    }
  }
  return overlay;
}
