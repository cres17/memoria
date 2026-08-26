import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/features/editor/editor_render_recipe.dart';

/// Shared spatial stage for preview and full-resolution export.
///
/// Crop, flip, rotation, perspective, and canvas expansion must be performed
/// before the visual recipe. Interactive editor tools may opt out of a stage
/// only while their Flutter overlay renders that stage live.
class EditorSpatialRenderer {
  /// Computes the exact output dimensions of the spatial stage without
  /// allocating pixels. Text overlays use this geometry before export so their
  /// target canvas matches the renderer after resize/crop/rotation.
  static EditorTargetGeometry outputGeometry(
    int sourceWidth,
    int sourceHeight,
    EditorRenderRecipe recipe, {
    int? maxDimension,
  }) {
    var width = sourceWidth;
    var height = sourceHeight;
    if (maxDimension != null &&
        (width > maxDimension || height > maxDimension)) {
      final scale = maxDimension / math.max(width, height);
      width = (width * scale).round();
      height = (height * scale).round();
    }
    final crop = recipe.crop;
    width +=
        (width * crop.expandLeft).round() + (width * crop.expandRight).round();
    height += (height * crop.expandTop).round() +
        (height * crop.expandBottom).round();
    final bounds = _cropBounds(width, height, recipe);
    if (bounds != null) {
      width = bounds.width;
      height = bounds.height;
    }
    final normalizedRotation = crop.rotation % 360;
    if (normalizedRotation == 90 ||
        normalizedRotation == -90 ||
        normalizedRotation == 270 ||
        normalizedRotation == -270) {
      final temporary = width;
      width = height;
      height = temporary;
    } else if (normalizedRotation % 90 != 0) {
      // Keep this in lockstep with image.copyRotate's generic branch. It
      // expands the destination canvas to the rotated source bounding box.
      final radians = normalizedRotation * math.pi / 180;
      final rotatedWidth = (width * math.cos(radians)).abs() +
          (height * math.sin(radians)).abs();
      final rotatedHeight = (width * math.sin(radians)).abs() +
          (height * math.cos(radians)).abs();
      width = rotatedWidth.toInt();
      height = rotatedHeight.toInt();
    }
    return EditorTargetGeometry(width: width, height: height);
  }

  static img.Image apply(
    img.Image source,
    EditorRenderRecipe recipe, {
    bool skipCrop = false,
    bool skipTransforms = false,
  }) {
    final crop = recipe.crop;
    var image = source;
    if (crop.expandTop > 0 ||
        crop.expandBottom > 0 ||
        crop.expandLeft > 0 ||
        crop.expandRight > 0) {
      image = _applyExpand(
        image,
        crop.expandTop,
        crop.expandBottom,
        crop.expandLeft,
        crop.expandRight,
        crop.expandMode,
      );
    }
    if (!skipCrop) image = _applyCrop(image, recipe);
    if (skipTransforms) return image;

    if (crop.flipH || crop.flipV) {
      final direction = crop.flipH && crop.flipV
          ? img.FlipDirection.both
          : crop.flipH
              ? img.FlipDirection.horizontal
              : img.FlipDirection.vertical;
      image = img.copyFlip(image, direction: direction);
    }
    if (crop.rotation != 0) {
      image = img.copyRotate(image, angle: crop.rotation);
    }
    if (crop.perspH != 0 || crop.perspV != 0) {
      image = _applyPerspective(image, crop.perspH, crop.perspV);
    }
    return image;
  }

  static img.Image _applyCrop(img.Image image, EditorRenderRecipe recipe) {
    final bounds = _cropBounds(image.width, image.height, recipe);
    if (bounds == null) return image;
    return img.copyCrop(
      image,
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
    );
  }

  static _CropBounds? _cropBounds(
    int imageWidth,
    int imageHeight,
    EditorRenderRecipe recipe,
  ) {
    final crop = recipe.crop;
    if (crop.cropLeft > 0.0 ||
        crop.cropTop > 0.0 ||
        crop.cropRight < 1.0 ||
        crop.cropBottom < 1.0) {
      final x = (imageWidth * crop.cropLeft).round().clamp(0, imageWidth - 1);
      final y = (imageHeight * crop.cropTop).round().clamp(0, imageHeight - 1);
      final width = (imageWidth * (crop.cropRight - crop.cropLeft))
          .round()
          .clamp(1, imageWidth - x);
      final height = (imageHeight * (crop.cropBottom - crop.cropTop))
          .round()
          .clamp(1, imageHeight - y);
      return _CropBounds(x, y, width, height);
    }

    final ratio = recipe.cropAspectRatio;
    if (ratio == null) return null;
    final width = imageWidth.toDouble();
    final height = imageHeight.toDouble();
    final int cropWidth;
    final int cropHeight;
    if (width / height > ratio) {
      cropHeight = height.round();
      cropWidth = (height * ratio).round();
    } else {
      cropWidth = width.round();
      cropHeight = (width / ratio).round();
    }
    final x = (width * crop.centerX - cropWidth / 2)
        .round()
        .clamp(0, width.round() - cropWidth);
    final y = (height * crop.centerY - cropHeight / 2)
        .round()
        .clamp(0, height.round() - cropHeight);
    return _CropBounds(x, y, cropWidth, cropHeight);
  }

  static img.Image _applyPerspective(
    img.Image source,
    double horizontalDegrees,
    double verticalDegrees,
  ) {
    final shearX = math.tan(horizontalDegrees * math.pi / 180);
    final shearY = math.tan(verticalDegrees * math.pi / 180);
    final width = source.width;
    final height = source.height;
    final centerX = (width - 1) / 2.0;
    final centerY = (height - 1) / 2.0;
    final destination = img.Image(width: width, height: height);
    final rawDenominator = 1 - shearX * shearY;
    final denominator = rawDenominator.abs() < 0.0001 ? 0.0001 : rawDenominator;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final sourceX = (dx - shearY * dy) / denominator + centerX;
        final sourceY = (dy - shearX * dx) / denominator + centerY;
        if (sourceX >= 0 &&
            sourceX < width - 1 &&
            sourceY >= 0 &&
            sourceY < height - 1) {
          destination.setPixel(
            x,
            y,
            source.getPixelInterpolate(sourceX, sourceY),
          );
        } else {
          destination.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }
    return destination;
  }

  static img.Image _applyExpand(
    img.Image image,
    double expandTop,
    double expandBottom,
    double expandLeft,
    double expandRight,
    String expandMode,
  ) {
    final addLeft = (image.width * expandLeft).round();
    final addRight = (image.width * expandRight).round();
    final addTop = (image.height * expandTop).round();
    final addBottom = (image.height * expandBottom).round();
    if (addLeft == 0 && addRight == 0 && addTop == 0 && addBottom == 0) {
      return image;
    }

    final newWidth = image.width + addLeft + addRight;
    final newHeight = image.height + addTop + addBottom;
    final destination = img.Image(width: newWidth, height: newHeight);
    if (expandMode == 'black') {
      destination.clear(img.ColorRgba8(0, 0, 0, 255));
    } else if (expandMode == 'white') {
      destination.clear(img.ColorRgba8(255, 255, 255, 255));
    }

    for (var y = 0; y < newHeight; y++) {
      for (var x = 0; x < newWidth; x++) {
        if (x >= addLeft &&
            x < addLeft + image.width &&
            y >= addTop &&
            y < addTop + image.height) {
          destination.setPixel(x, y, image.getPixel(x - addLeft, y - addTop));
        } else if (expandMode == 'smart') {
          destination.setPixel(
            x,
            y,
            image.getPixel(
              _mirroredCoordinate(x - addLeft, image.width),
              _mirroredCoordinate(y - addTop, image.height),
            ),
          );
        }
      }
    }
    return destination;
  }

  static int _mirroredCoordinate(int coordinate, int length) {
    if (length <= 1) return 0;
    final period = length * 2;
    var value = coordinate % period;
    if (value < 0) value += period;
    if (value >= length) value = period - 1 - value;
    return value.clamp(0, length - 1);
  }

  /// Applies the spatial recipe to a segmentation mask in source coordinates.
  ///
  /// A mask is deliberately expanded with zero-valued pixels even when the
  /// image uses the smart expansion mode: generated canvas has no inferred
  /// subject and must not receive portrait-only corrections.
  static EditorSpatialMask applyMask(
    EditorSpatialMask source,
    EditorRenderRecipe recipe, {
    bool skipCrop = false,
    bool skipTransforms = false,
  }) {
    var mask = source;
    final crop = recipe.crop;
    if (crop.expandTop > 0 ||
        crop.expandBottom > 0 ||
        crop.expandLeft > 0 ||
        crop.expandRight > 0) {
      mask = mask.expand(
        crop.expandTop,
        crop.expandBottom,
        crop.expandLeft,
        crop.expandRight,
      );
    }
    if (!skipCrop) {
      final bounds = _cropBounds(mask.width, mask.height, recipe);
      if (bounds != null) mask = mask._crop(bounds);
    }
    if (skipTransforms) return mask;
    if (crop.flipH) mask = mask.flipHorizontal();
    if (crop.flipV) mask = mask.flipVertical();
    if (crop.rotation != 0) mask = mask.rotate(crop.rotation);
    if (crop.perspH != 0 || crop.perspV != 0) {
      mask = mask.perspective(crop.perspH, crop.perspV);
    }
    return mask;
  }
}

class EditorTargetGeometry {
  final int width;
  final int height;

  const EditorTargetGeometry({required this.width, required this.height});

  bool get isValid => width > 0 && height > 0;
}

class _CropBounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const _CropBounds(this.x, this.y, this.width, this.height);
}

/// Float32 scalar raster used for coordinate-safe segmentation masks.
class EditorSpatialMask {
  final Float32List data;
  final int width;
  final int height;

  const EditorSpatialMask(this.data, this.width, this.height);

  bool get isValid => width > 0 && height > 0 && data.length == width * height;

  EditorSpatialMask resize(int targetWidth, int targetHeight) {
    if (!isValid || targetWidth <= 0 || targetHeight <= 0) return this;
    if (targetWidth == width && targetHeight == height) return this;
    final output = Float32List(targetWidth * targetHeight);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY =
          targetHeight == 1 ? 0.0 : y * (height - 1) / (targetHeight - 1);
      for (var x = 0; x < targetWidth; x++) {
        final sourceX =
            targetWidth == 1 ? 0.0 : x * (width - 1) / (targetWidth - 1);
        output[y * targetWidth + x] = _sampleLinear(sourceX, sourceY);
      }
    }
    return EditorSpatialMask(output, targetWidth, targetHeight);
  }

  EditorSpatialMask expand(
    double top,
    double bottom,
    double left,
    double right,
  ) {
    if (!isValid) return this;
    final addLeft = (width * left).round();
    final addRight = (width * right).round();
    final addTop = (height * top).round();
    final addBottom = (height * bottom).round();
    if (addLeft == 0 && addRight == 0 && addTop == 0 && addBottom == 0) {
      return this;
    }
    final targetWidth = width + addLeft + addRight;
    final targetHeight = height + addTop + addBottom;
    final output = Float32List(targetWidth * targetHeight);
    for (var y = 0; y < height; y++) {
      final sourceOffset = y * width;
      final targetOffset = (y + addTop) * targetWidth + addLeft;
      output.setRange(targetOffset, targetOffset + width, data, sourceOffset);
    }
    return EditorSpatialMask(output, targetWidth, targetHeight);
  }

  EditorSpatialMask _crop(_CropBounds bounds) {
    if (!isValid) return this;
    final output = Float32List(bounds.width * bounds.height);
    for (var y = 0; y < bounds.height; y++) {
      final sourceOffset = (bounds.y + y) * width + bounds.x;
      final targetOffset = y * bounds.width;
      output.setRange(
        targetOffset,
        targetOffset + bounds.width,
        data,
        sourceOffset,
      );
    }
    return EditorSpatialMask(output, bounds.width, bounds.height);
  }

  EditorSpatialMask flipHorizontal() {
    if (!isValid) return this;
    final output = Float32List(data.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        output[y * width + x] = data[y * width + (width - 1 - x)];
      }
    }
    return EditorSpatialMask(output, width, height);
  }

  EditorSpatialMask flipVertical() {
    if (!isValid) return this;
    final output = Float32List(data.length);
    for (var y = 0; y < height; y++) {
      final targetOffset = y * width;
      final sourceOffset = (height - 1 - y) * width;
      output.setRange(targetOffset, targetOffset + width, data, sourceOffset);
    }
    return EditorSpatialMask(output, width, height);
  }

  EditorSpatialMask rotate(double angle) {
    if (!isValid) return this;
    final normalized = angle % 360.0;
    if ((normalized % 90.0) == 0.0) {
      switch (normalized ~/ 90.0) {
        case 1:
          return _rotate90();
        case 2:
          return _rotate180();
        case 3:
          return _rotate270();
        default:
          return this;
      }
    }

    final radians = normalized * math.pi / 180.0;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final outputWidth =
        ((width * cosine).abs() + (height * sine).abs()).toInt();
    final outputHeight =
        ((width * sine).abs() + (height * cosine).abs()).toInt();
    if (outputWidth <= 0 || outputHeight <= 0) return this;
    final output = Float32List(outputWidth * outputHeight);
    final sourceCenterX = 0.5 * width;
    final sourceCenterY = 0.5 * height;
    final destinationCenterX = 0.5 * outputWidth;
    final destinationCenterY = 0.5 * outputHeight;
    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        final sourceX = sourceCenterX +
            (x - destinationCenterX) * cosine +
            (y - destinationCenterY) * sine;
        final sourceY = sourceCenterY -
            (x - destinationCenterX) * sine +
            (y - destinationCenterY) * cosine;
        if (sourceX >= 0 &&
            sourceX < width - 1 &&
            sourceY >= 0 &&
            sourceY < height - 1) {
          output[y * outputWidth + x] =
              data[sourceY.toInt() * width + sourceX.toInt()];
        }
      }
    }
    return EditorSpatialMask(output, outputWidth, outputHeight);
  }

  EditorSpatialMask _rotate90() {
    final output = Float32List(data.length);
    for (var y = 0; y < width; y++) {
      for (var x = 0; x < height; x++) {
        output[y * height + x] = data[(height - 1 - x) * width + y];
      }
    }
    return EditorSpatialMask(output, height, width);
  }

  EditorSpatialMask _rotate180() {
    final output = Float32List(data.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        output[y * width + x] = data[(height - 1 - y) * width + width - 1 - x];
      }
    }
    return EditorSpatialMask(output, width, height);
  }

  EditorSpatialMask _rotate270() {
    final output = Float32List(data.length);
    for (var y = 0; y < width; y++) {
      for (var x = 0; x < height; x++) {
        output[y * height + x] = data[x * width + width - 1 - y];
      }
    }
    return EditorSpatialMask(output, height, width);
  }

  EditorSpatialMask perspective(
      double horizontalDegrees, double verticalDegrees) {
    if (!isValid) return this;
    final shearX = math.tan(horizontalDegrees * math.pi / 180);
    final shearY = math.tan(verticalDegrees * math.pi / 180);
    final centerX = (width - 1) / 2.0;
    final centerY = (height - 1) / 2.0;
    final rawDenominator = 1 - shearX * shearY;
    final denominator = rawDenominator.abs() < 0.0001 ? 0.0001 : rawDenominator;
    final output = Float32List(data.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final sourceX = (dx - shearY * dy) / denominator + centerX;
        final sourceY = (dy - shearX * dx) / denominator + centerY;
        if (sourceX >= 0 &&
            sourceX < width - 1 &&
            sourceY >= 0 &&
            sourceY < height - 1) {
          output[y * width + x] = _sampleLinear(sourceX, sourceY);
        }
      }
    }
    return EditorSpatialMask(output, width, height);
  }

  double _sampleLinear(double x, double y) {
    final x0 = x.toInt();
    final y0 = y.toInt();
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final dx = x - x0;
    final dy = y - y0;
    final top = data[y0 * width + x0] * (1 - dx) + data[y0 * width + x1] * dx;
    final bottom =
        data[y1 * width + x0] * (1 - dx) + data[y1 * width + x1] * dx;
    return top * (1 - dy) + bottom * dy;
  }
}
