import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';
import 'package:memoria/features/editor/utils/text_rasterizer.dart';

class EditorPortraitMaskResource {
  final Float32List data;
  final int width;
  final int height;

  const EditorPortraitMaskResource({
    required this.data,
    required this.width,
    required this.height,
  });
}

class EditorResourcePreparationRequest {
  final EditorRenderRecipe recipe;
  final img.Image maskSource;
  final String maskSourceKey;
  final EditorTargetGeometry targetGeometry;
  final int frameIndex;
  final String? blendImagePath;
  final bool preparePortraitMask;
  final bool prepareTextOverlay;

  const EditorResourcePreparationRequest({
    required this.recipe,
    required this.maskSource,
    required this.maskSourceKey,
    required this.targetGeometry,
    required this.frameIndex,
    required this.blendImagePath,
    required this.preparePortraitMask,
    required this.prepareTextOverlay,
  });
}

class EditorPreparedResources {
  final EditorRenderResources renderResources;
  final EditorTargetGeometry targetGeometry;

  const EditorPreparedResources({
    required this.renderResources,
    required this.targetGeometry,
  });
}

enum EditorResourceFailureKind { frame, blend, portraitMask, textOverlay }

class EditorResourcePreparationFailure implements Exception {
  final EditorResourceFailureKind kind;
  final Object cause;

  const EditorResourcePreparationFailure(this.kind, this.cause);

  @override
  String toString() => 'EditorResourcePreparationFailure(${kind.name})';
}

typedef EditorFrameLoader = Future<Uint8List?> Function(int index);
typedef EditorBlendLoader = Future<Uint8List?> Function(String path);
typedef EditorPortraitMaskLoader = Future<EditorPortraitMaskResource?> Function(
    img.Image source, String sourceKey);

/// Prepares all non-recipe renderer inputs in an explicit coordinate space.
///
/// It deliberately returns bytes and dimensions only: neither the renderer nor
/// its isolate workers may read paths or invoke Flutter text APIs.
class EditorResourcePreparer {
  final EditorFrameLoader _loadFrame;
  final EditorBlendLoader _loadBlend;
  final EditorPortraitMaskLoader _loadPortraitMask;

  const EditorResourcePreparer({
    required EditorFrameLoader loadFrame,
    required EditorBlendLoader loadBlend,
    required EditorPortraitMaskLoader loadPortraitMask,
  })  : _loadFrame = loadFrame,
        _loadBlend = loadBlend,
        _loadPortraitMask = loadPortraitMask;

  Future<EditorPreparedResources> prepare(
    EditorResourcePreparationRequest request,
  ) async {
    final frameFuture = request.frameIndex < 0
        ? Future<Uint8List?>.value(null)
        : _loadFrame(request.frameIndex);
    final blendPath = request.blendImagePath;
    final blendFuture =
        blendPath == null || request.recipe.creative.blendOpacity <= 0
            ? Future<Uint8List?>.value(null)
            : _loadBlend(blendPath);
    final maskFuture = request.preparePortraitMask
        ? _loadPortraitMask(request.maskSource, request.maskSourceKey)
        : Future<EditorPortraitMaskResource?>.value(null);

    final frameBytes = await _load(
      EditorResourceFailureKind.frame,
      frameFuture,
    );
    final blendBytes = await _load(
      EditorResourceFailureKind.blend,
      blendFuture,
    );
    final mask = await _load(
      EditorResourceFailureKind.portraitMask,
      maskFuture,
    );
    final textBytes = await _load(
      EditorResourceFailureKind.textOverlay,
      _prepareTextOverlay(request),
    );

    return EditorPreparedResources(
      targetGeometry: request.targetGeometry,
      renderResources: EditorRenderResources(
        segmentMask: mask?.data,
        segmentMaskWidth: mask?.width ?? 0,
        segmentMaskHeight: mask?.height ?? 0,
        blendImageBytes: blendBytes,
        frameBytes: frameBytes,
        textOverlayBytes: textBytes,
      ),
    );
  }

  Future<T> _load<T>(
    EditorResourceFailureKind kind,
    Future<T> future,
  ) async {
    try {
      return await future;
    } catch (error) {
      throw EditorResourcePreparationFailure(kind, error);
    }
  }

  Future<Uint8List?> _prepareTextOverlay(
    EditorResourcePreparationRequest request,
  ) async {
    final creative = request.recipe.creative;
    if (!request.prepareTextOverlay ||
        creative.overlayText.trim().isEmpty ||
        !request.targetGeometry.isValid) {
      return null;
    }
    return TextRasterizer.rasterize(
      text: creative.overlayText,
      fontFamily: creative.fontFamily,
      textSize: creative.textSize,
      color: Color(creative.textColorValue),
      textX: creative.textX,
      textY: creative.textY,
      rotationDegrees: creative.textRotation,
      imageWidth: request.targetGeometry.width,
      imageHeight: request.targetGeometry.height,
    );
  }
}
