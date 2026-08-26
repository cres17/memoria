import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/blur_engine.dart';
import 'package:memoria/engine/frame_overlay.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';

class EditorRenderResources {
  final Float32List? segmentMask;
  final int segmentMaskWidth;
  final int segmentMaskHeight;
  final Uint8List? blendImageBytes;
  final Uint8List? frameBytes;
  final String? overlayTextOverride;
  final Uint8List? textOverlayBytes;

  const EditorRenderResources({
    this.segmentMask,
    this.segmentMaskWidth = 0,
    this.segmentMaskHeight = 0,
    this.blendImageBytes,
    this.frameBytes,
    this.overlayTextOverride,
    this.textOverlayBytes,
  });

  EditorRenderResources copyWith({
    Float32List? segmentMask,
    int? segmentMaskWidth,
    int? segmentMaskHeight,
  }) {
    return EditorRenderResources(
      segmentMask: segmentMask ?? this.segmentMask,
      segmentMaskWidth: segmentMaskWidth ?? this.segmentMaskWidth,
      segmentMaskHeight: segmentMaskHeight ?? this.segmentMaskHeight,
      blendImageBytes: blendImageBytes,
      frameBytes: frameBytes,
      overlayTextOverride: overlayTextOverride,
      textOverlayBytes: textOverlayBytes,
    );
  }
}

/// Isolate-safe preview render input shared by the editor UI and tests.
///
/// Spatial transforms have already been committed to [imageBytes] by the
/// interactive preview stage. The worker therefore applies only the visual
/// recipe, matching the image shown by [EditorPage] without duplicating crop
/// or rotation.
class EditorPreviewRenderRequest {
  final int width;
  final int height;
  final Uint8List imageBytes;
  final EditorRenderRecipe recipe;
  final EditorRenderResources resources;

  const EditorPreviewRenderRequest({
    required this.width,
    required this.height,
    required this.imageBytes,
    required this.recipe,
    required this.resources,
  });
}

/// Canonical production renderer shared by preview and export.
class EditorRenderer {
  /// Preview isolate entrypoint used by the production editor page.
  static Future<Uint8List> renderPreviewBytes(
    EditorPreviewRenderRequest request,
  ) async {
    var image = img.Image.fromBytes(
      width: request.width,
      height: request.height,
      bytes: request.imageBytes.buffer,
      bytesOffset: request.imageBytes.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    image = await applyVisual(image, request.recipe, request.resources);
    return Uint8List.fromList(img.encodePng(image));
  }

  static img.Image preparePreviewSource(
    img.Image source,
    EditorRenderRecipe recipe, {
    int maxLongEdge = 720,
    bool skipCrop = false,
    bool skipTransforms = false,
  }) {
    final spatial = EditorSpatialRenderer.apply(
      source,
      recipe,
      skipCrop: skipCrop,
      skipTransforms: skipTransforms,
    );
    final longest = math.max(spatial.width, spatial.height);
    if (longest <= maxLongEdge) return spatial;
    final scale = maxLongEdge / longest;
    return img.copyResize(
      spatial,
      width: (spatial.width * scale).round(),
      height: (spatial.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  static img.Image prepareExportSource(
    img.Image source,
    EditorRenderRecipe recipe, {
    int? maxDimension,
  }) {
    final prepared = _resizeExportInput(source, maxDimension: maxDimension);
    return EditorSpatialRenderer.apply(prepared, recipe);
  }

  static img.Image _resizeExportInput(
    img.Image source, {
    int? maxDimension,
  }) {
    var prepared = source;
    if (maxDimension != null &&
        (source.width > maxDimension || source.height > maxDimension)) {
      final scale = maxDimension / math.max(source.width, source.height);
      prepared = img.copyResize(
        source,
        width: (source.width * scale).round(),
        height: (source.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    return prepared;
  }

  static Future<img.Image> renderPreview({
    required img.Image source,
    required EditorRenderRecipe recipe,
    EditorRenderResources resources = const EditorRenderResources(),
    int maxLongEdge = 720,
  }) async {
    final prepared = preparePreviewSource(
      source,
      recipe,
      maxLongEdge: maxLongEdge,
    );
    return applyVisual(
      prepared,
      recipe,
      _prepareSpatialMask(
        resources,
        recipe,
        sourceWidth: source.width,
        sourceHeight: source.height,
        targetWidth: prepared.width,
        targetHeight: prepared.height,
      ),
    );
  }

  static Future<img.Image> renderExport({
    required img.Image source,
    required EditorRenderRecipe recipe,
    EditorRenderResources resources = const EditorRenderResources(),
    int? maxDimension,
    void Function(double progress)? onProgress,
  }) async {
    final sourceForSpatial = _resizeExportInput(
      source,
      maxDimension: maxDimension,
    );
    final prepared = prepareExportSource(
      source,
      recipe,
      maxDimension: maxDimension,
    );
    onProgress?.call(0.15);
    return applyVisual(
      prepared,
      recipe,
      _prepareSpatialMask(
        resources,
        recipe,
        sourceWidth: sourceForSpatial.width,
        sourceHeight: sourceForSpatial.height,
        targetWidth: prepared.width,
        targetHeight: prepared.height,
      ),
      onProgress: onProgress,
    );
  }

  static EditorRenderResources _prepareSpatialMask(
    EditorRenderResources resources,
    EditorRenderRecipe recipe, {
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    final data = resources.segmentMask;
    final sourceMask = EditorSpatialMask(
      data ?? Float32List(0),
      resources.segmentMaskWidth,
      resources.segmentMaskHeight,
    );
    if (data == null || !sourceMask.isValid) return resources;

    final aligned = EditorSpatialRenderer.applyMask(
      sourceMask.resize(sourceWidth, sourceHeight),
      recipe,
    ).resize(targetWidth, targetHeight);
    return resources.copyWith(
      segmentMask: aligned.data,
      segmentMaskWidth: aligned.width,
      segmentMaskHeight: aligned.height,
    );
  }

  static Future<img.Image> applyVisual(
    img.Image image,
    EditorRenderRecipe recipe,
    EditorRenderResources resources, {
    void Function(double progress)? onProgress,
  }) async {
    var out = applyImagePipeline(
      image: image,
      params: recipe.adjustParams,
      lutBytes: recipe.lutBytes,
      intensity: recipe.intensity,
    );
    onProgress?.call(0.40);

    if (recipe.effect != ArtisticEffect.none) {
      out = await applyArtisticEffect(
        out,
        recipe.effect,
        strength: recipe.effectStrength,
        grainVariant: recipe.grainVariant,
      );
    }
    onProgress?.call(0.55);

    if (recipe.selectiveActive) {
      out = applySelectiveAdjust(out, [
        LocalSelectivePoint(
          x: recipe.selectiveX,
          y: recipe.selectiveY,
          brightness: recipe.selectiveBrightness,
          contrast: recipe.selectiveContrast,
          saturation: recipe.selectiveSaturation,
          radius: recipe.selectiveRadius,
        ),
      ]);
    }
    if (recipe.dodgeBurnActive) {
      final strokes = recipe.brushStrokes.isNotEmpty
          ? recipe.brushStrokes
          : [
              if (recipe.dodgeStrength > 0)
                DodgeBurnStroke(
                  x: 0.5,
                  y: recipe.dodgeY,
                  radius: recipe.dodgeRadius,
                  strength: recipe.dodgeStrength,
                  isDodge: true,
                ),
              if (recipe.burnStrength > 0)
                DodgeBurnStroke(
                  x: 0.5,
                  y: recipe.burnY,
                  radius: recipe.burnRadius,
                  strength: recipe.burnStrength,
                  isDodge: false,
                ),
            ];
      out = applyDodgeBurn(out, strokes);
    }
    if (recipe.tiltActive) {
      out = applyLinearTiltShift(
        image: out,
        focusCenter: recipe.tiltFocusCenter,
        focusBandWidth: recipe.tiltBandWidth,
        maxBlur: recipe.tiltMaxBlur,
      );
    }
    if (recipe.lensActive) {
      out = applyLensBlur(
        image: out,
        depthMap: _radialDepthMap(out.width, out.height),
        focusDepth: recipe.lensFocusDepth,
        maxBlurRadius: recipe.lensMaxRadius,
      );
    }
    onProgress?.call(0.70);

    var segmentMask = resources.segmentMask;
    if (segmentMask != null &&
        resources.segmentMaskWidth > 0 &&
        resources.segmentMaskHeight > 0) {
      final sourceMask = EditorSpatialMask(
        segmentMask,
        resources.segmentMaskWidth,
        resources.segmentMaskHeight,
      );
      segmentMask = sourceMask.isValid
          ? sourceMask.resize(out.width, out.height).data
          : null;
    }
    out = _applyPortrait(out, recipe, segmentMask);
    return _applyCreative(out, recipe, resources);
  }

  static img.Image _applyPortrait(
    img.Image image,
    EditorRenderRecipe recipe,
    Float32List? segmentMask,
  ) {
    final portrait = recipe.portrait;
    if (portrait.smooth <= 0 &&
        portrait.spotlight <= 0 &&
        portrait.skinTone == SkinTone.none) {
      return image;
    }
    if (segmentMask == null ||
        segmentMask.length != image.width * image.height) {
      return image;
    }
    var out = image;
    if (portrait.smooth > 0) {
      out = applySkinSmoothing(out, segmentMask, portrait.smooth);
    }
    if (portrait.spotlight > 0) {
      out = applyFaceSpotlight(out, segmentMask, portrait.spotlight);
    }
    if (portrait.skinTone != SkinTone.none) {
      out = applySkinToning(
        out,
        segmentMask,
        portrait.skinTone,
        portrait.skinToneStrength,
      );
    }
    return out;
  }

  static Future<img.Image> _applyCreative(
    img.Image image,
    EditorRenderRecipe recipe,
    EditorRenderResources resources,
  ) async {
    var out = image;
    final creative = recipe.creative;
    if (creative.blendOpacity > 0) {
      final blend = resources.blendImageBytes == null
          ? null
          : img.decodeImage(resources.blendImageBytes!);
      if (blend != null) {
        out = bm.blendImages(
          dst: out,
          src: blend,
          mode: creative.blendMode,
          opacity: creative.blendOpacity.clamp(0.0, 1.0),
        );
      }
    }

    if (resources.frameBytes != null) {
      final frame = img.decodeImage(resources.frameBytes!);
      if (frame != null) {
        out = img.compositeImage(
          out,
          buildFrameOverlay(frame),
          dstW: out.width,
          dstH: out.height,
        );
      }
    }

    if (resources.textOverlayBytes != null) {
      final textImage = img.decodeImage(resources.textOverlayBytes!);
      if (textImage != null) {
        return img.compositeImage(
          out,
          textImage,
          blend: img.BlendMode.alpha,
          dstW: out.width,
          dstH: out.height,
        );
      }
      return out;
    }

    final text = (resources.overlayTextOverride ?? creative.overlayText).trim();
    if (text.isEmpty) return out;
    final colorValue = creative.textColorValue;
    final color = img.ColorRgba8(
      (colorValue >> 16) & 0xff,
      (colorValue >> 8) & 0xff,
      colorValue & 0xff,
      (colorValue >> 24) & 0xff,
    );
    const baseSize = 48.0;
    final scale = (creative.textSize / baseSize).clamp(0.25, 4.0);
    final canvas = img.Image(
      width: out.width,
      height: out.height,
      numChannels: 4,
    );
    img.drawString(
      canvas,
      text,
      font: img.arial48,
      y: (out.height - baseSize * 2.2).round().clamp(0, out.height - 1),
      color: color,
      wrap: true,
    );
    if (scale == 1.0) {
      return img.compositeImage(
        out,
        canvas,
        blend: img.BlendMode.alpha,
        dstW: out.width,
        dstH: out.height,
      );
    }
    final scaledWidth = (out.width * scale).round().clamp(1, out.width * 4);
    final scaledHeight = (out.height * scale).round().clamp(1, out.height * 4);
    final scaled = img.copyResize(
      canvas,
      width: scaledWidth,
      height: scaledHeight,
      interpolation: img.Interpolation.linear,
    );
    final cropX =
        ((scaledWidth - out.width) / 2).round().clamp(0, scaledWidth - 1);
    final cropY = (scaledHeight - out.height).clamp(0, scaledHeight - 1);
    final cropped = img.copyCrop(
      scaled,
      x: cropX,
      y: cropY,
      width: out.width.clamp(1, scaledWidth - cropX),
      height: out.height.clamp(1, scaledHeight - cropY),
    );
    return img.compositeImage(
      out,
      cropped,
      blend: img.BlendMode.alpha,
      dstW: out.width,
      dstH: out.height,
    );
  }

  static Float32List _radialDepthMap(int width, int height) {
    final map = Float32List(width * height);
    final centerX = width / 2.0;
    final centerY = height / 2.0;
    final maxDistance = math.sqrt(centerX * centerX + centerY * centerY);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        map[y * width + x] = math.sqrt(dx * dx + dy * dy) / maxDistance;
      }
    }
    return map;
  }
}
