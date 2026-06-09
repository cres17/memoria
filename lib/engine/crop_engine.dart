import 'package:image/image.dart' as img;
import '../domain/models/edit_operation.dart';
import '../domain/models/crop_ratio_preset.dart';

/// Applies the crop state boundaries to the input image.
img.Image cropImage(img.Image image, CropState state) {
  var out = image;
  if (image.width <= 0 || image.height <= 0) return out;

  final W = out.width.toDouble();
  final H = out.height.toDouble();

  // Check if we have customized boundaries (different from default 0.0, 0.0, 1.0, 1.0)
  final isCustomBounds = state.cropLeft > 0.0001 ||
      state.cropTop > 0.0001 ||
      state.cropRight < 0.9999 ||
      state.cropBottom < 0.9999;

  if (isCustomBounds) {
    final x = (state.cropLeft * W).round().clamp(0, out.width - 1);
    final y = (state.cropTop * H).round().clamp(0, out.height - 1);
    final w = ((state.cropRight - state.cropLeft) * W).round().clamp(1, out.width - x);
    final h = ((state.cropBottom - state.cropTop) * H).round().clamp(1, out.height - y);
    return img.copyCrop(out, x: x, y: y, width: w, height: h);
  } else {
    // Standard centering/fitting based on ratio preset
    final double? targetRatio;
    if (state.ratio == CropRatioPreset.original) {
      targetRatio = W / H;
    } else {
      targetRatio = state.ratio.ratio;
    }

    if (targetRatio != null && targetRatio > 0) {
      int cropW, cropH;
      if (W / H > targetRatio) {
        cropH = H.round();
        cropW = (H * targetRatio).round();
      } else {
        cropW = W.round();
        cropH = (W / targetRatio).round();
      }
      final x = (W * state.centerX - cropW / 2).round().clamp(0, out.width - cropW);
      final y = (H * state.centerY - cropH / 2).round().clamp(0, out.height - cropH);
      return img.copyCrop(out, x: x, y: y, width: cropW, height: cropH);
    }
  }

  return out;
}
