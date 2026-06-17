import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'geometry_transforms.dart';
import 'lut_engine.dart';
import 'portrait_engine.dart';
import 'blend_modes.dart' as bm;
import 'brush_engine.dart';
import 'color_utils.dart';
import 'inpainting.dart';
import 'raw_processor.dart';
import 'crop_engine.dart';

// ─────────────────────────────────────────────────────────
//  EditOperationPlayer
//  EditSession의 활성 ops를 순서대로 재적용해 최종 img.Image를 반환합니다.
//  프리뷰(960px)와 내보내기(전체 해상도) 모두 이 경로를 공유합니다.
//  isolate 안전: ML 마스크(segmentMask, depthMap)는 호출자가 주입합니다.
// ─────────────────────────────────────────────────────────

class EditOperationPlayerArgs {
  final img.Image original;
  final EditSession session;
  final int? upToIndex; // null = 모든 활성 ops
  final Uint8List? lutBytes; // 현재 필터 LUT
  final Float32List? segmentMask; // portrait 효과용 AI 마스크
  final Float32List? depthMap; // bokeh 효과용 depth map
  final Uint8List? blendImageBytes; // creative blend 이미지
  final Uint8List? frameBytes; // creative 프레임
  final Uint8List? textOverlayBytes; // 다국어 텍스트 오버레이 투명 레이어

  const EditOperationPlayerArgs({
    required this.original,
    required this.session,
    this.upToIndex,
    this.lutBytes,
    this.segmentMask,
    this.depthMap,
    this.blendImageBytes,
    this.frameBytes,
    this.textOverlayBytes,
  });
}

class EditOperationPlayer {
  const EditOperationPlayer();

  // ── 메인 진입점 ─────────────────────────────────────────

  static img.Image playStatic(EditOperationPlayerArgs args) {
    return const EditOperationPlayer().play(args);
  }

  Future<img.Image> playInIsolate(EditOperationPlayerArgs args) async {
    return await Isolate.run(() => playStatic(args));
  }

  img.Image play(EditOperationPlayerArgs args) {
    final ops = args.upToIndex != null
        ? args.session.ops.sublist(0, args.upToIndex)
        : args.session.activeOps;

    var image = args.original;

    for (final op in ops) {
      image = _applyOp(
        image,
        op,
        lutBytes: args.lutBytes,
        segmentMask: args.segmentMask,
        depthMap: args.depthMap,
        blendImageBytes: args.blendImageBytes,
        frameBytes: args.frameBytes,
        textOverlayBytes: args.textOverlayBytes,
      );
    }

    return image;
  }

  // ── 단일 op 적용 ─────────────────────────────────────────

  img.Image _applyOp(
    img.Image image,
    EditOperation op, {
    Uint8List? lutBytes,
    Float32List? segmentMask,
    Float32List? depthMap,
    Uint8List? blendImageBytes,
    Uint8List? frameBytes,
    Uint8List? textOverlayBytes,
  }) {
    switch (op.tool) {
      case EditToolType.globalAdjust:
      case EditToolType.details:
      case EditToolType.hslAdjust:
      case EditToolType.splitTone:
      case EditToolType.grainOverlay:
        return _applyGlobalAdjust(image, op.params ?? AdjustParams.zero);

      case EditToolType.filter:
        return _applyFilter(
          image,
          params: op.params ?? AdjustParams.zero,
          lutBytes: lutBytes,
          intensity: op.intensity ?? 1.0,
        );

      case EditToolType.curve:
        if (op.curves == null || op.curves!.isEmpty) return image;
        final withCurves = _mergeCurvesIntoParams(
          op.params ?? AdjustParams.zero,
          op.curves!,
        );
        return applyImagePipeline(
            image: image, params: withCurves, intensity: 1.0);

      case EditToolType.crop:
        if (op.cropState == null) return image;
        return _applyCrop(image, op.cropState!);

      case EditToolType.portrait:
        if (op.portrait == null) return image;
        return _applyPortrait(
          image,
          op.portrait!,
          segmentMask: segmentMask,
          depthMap: depthMap,
        );

      case EditToolType.creative:
        if (op.creative == null) return image;
        return _applyCreative(
          image,
          op.creative!,
          blendImageBytes: blendImageBytes,
          frameBytes: frameBytes,
          textOverlayBytes: textOverlayBytes,
        );

      // Phase 2 이후 미구현 — 원본 반환
      case EditToolType.brush:
        if (op.brushMask == null) return image;
        return applyBrushCorrection(
          image: image,
          brush: op.brushMask!,
          lutBytes: lutBytes,
        );

      case EditToolType.selective:
        if (op.selectivePoints == null || op.selectivePoints!.isEmpty) {
          return image;
        }
        return _applySelective(image, op.selectivePoints!);

      case EditToolType.heal:
        if (op.healStrokes == null || op.healStrokes!.isEmpty) return image;
        return _applyHeal(image, op.healStrokes!);

      case EditToolType.rawDevelop:
        return _applyRawDevelop(image, op.params ?? AdjustParams.zero);

      case EditToolType.vignette:
      case EditToolType.glow:
      case EditToolType.drama:
      case EditToolType.lightLeak:
      case EditToolType.halation:
        return _applyGlobalAdjust(image, op.params ?? AdjustParams.zero);
    }
  }

  // ── globalAdjust ─────────────────────────────────────────

  img.Image _applyGlobalAdjust(img.Image image, AdjustParams params) {
    if (params.isZero) return image;
    return applyImagePipeline(image: image, params: params, intensity: 1.0);
  }

  // ── filter ───────────────────────────────────────────────

  img.Image _applyFilter(
    img.Image image, {
    required AdjustParams params,
    Uint8List? lutBytes,
    required double intensity,
  }) {
    return applyImagePipeline(
      image: image,
      params: params,
      lutBytes: lutBytes,
      intensity: intensity,
    );
  }

  // ── curve ────────────────────────────────────────────────

  img.Image _applySelective(img.Image image, List<SelectivePoint> points) {
    var out = image;
    for (final point in points) {
      if (point.localParams.isZero || point.radius <= 0) continue;

      final adjusted = applyImagePipeline(
        image: out,
        params: point.localParams,
        intensity: 1.0,
      );
      final next = img.Image.from(out);
      final centerX = point.x.clamp(0.0, 1.0) * (out.width - 1);
      final centerY = point.y.clamp(0.0, 1.0) * (out.height - 1);
      final radiusPx = point.radius.clamp(0.0, 1.0) *
          math.min(out.width, out.height).toDouble();
      if (radiusPx <= 0) continue;

      LabColor? targetLab;
      if (point.mode == SelectiveMode.colorAuto) {
        final cx = centerX.round().clamp(0, out.width - 1);
        final cy = centerY.round().clamp(0, out.height - 1);
        final p = out.getPixel(cx, cy);
        targetLab = rgbToLab(RgbColor(
          p.rNormalized.toDouble(),
          p.gNormalized.toDouble(),
          p.bNormalized.toDouble(),
        ));
      }

      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          final dx = (x - centerX) / radiusPx;
          final dy = (y - centerY) / radiusPx;
          final dist = math.sqrt(dx * dx + dy * dy);
          var mask = (1.0 - ((dist - 0.68) / 0.32)).clamp(0.0, 1.0);
          if (mask <= 0) continue;

          if (targetLab != null) {
            final p = out.getPixel(x, y);
            final lab = rgbToLab(RgbColor(
              p.rNormalized.toDouble(),
              p.gNormalized.toDouble(),
              p.bNormalized.toDouble(),
            ));
            final dl = (lab.l - targetLab.l) / 100.0;
            final da = (lab.a - targetLab.a) / 128.0;
            final db = (lab.b - targetLab.b) / 128.0;
            final colorDistance = math.sqrt(dl * dl + da * da + db * db);
            final colorMask =
                (1.0 - ((colorDistance - 0.10) / 0.28)).clamp(0.0, 1.0);
            mask *= colorMask;
            if (mask <= 0) continue;
          }

          final a = adjusted.getPixel(x, y);
          final b = out.getPixel(x, y);
          next.setPixelRgb(
            x,
            y,
            (b.r + (a.r - b.r) * mask).round().clamp(0, 255),
            (b.g + (a.g - b.g) * mask).round().clamp(0, 255),
            (b.b + (a.b - b.b) * mask).round().clamp(0, 255),
          );
        }
      }
      out = next;
    }
    return out;
  }

  img.Image _applyHeal(img.Image image, List<HealStroke> strokes) {
    final samples = _healStrokeSamples(strokes);
    if (samples.isEmpty) return image;
    final mask = createBrushMask(
      width: image.width,
      height: image.height,
      strokes: samples,
    );
    return applyHealing(image, mask);
  }

  List<({double x, double y, double radius})> _healStrokeSamples(
    List<HealStroke> strokes,
  ) {
    final samples = <({double x, double y, double radius})>[];
    for (final stroke in strokes) {
      if (stroke.path.isEmpty || stroke.radius <= 0) continue;
      Map<String, double>? previous;
      for (final point in stroke.path) {
        final x = (point['x'] ?? 0.0).clamp(0.0, 1.0);
        final y = (point['y'] ?? 0.0).clamp(0.0, 1.0);
        if (previous == null) {
          samples.add((x: x, y: y, radius: stroke.radius));
        } else {
          final px = (previous['x'] ?? x).clamp(0.0, 1.0);
          final py = (previous['y'] ?? y).clamp(0.0, 1.0);
          final distance = math.sqrt(math.pow(x - px, 2) + math.pow(y - py, 2));
          final steps = math.max(1, (distance / (stroke.radius * 0.45)).ceil());
          for (var i = 1; i <= steps; i++) {
            final t = i / steps;
            samples.add((
              x: px + (x - px) * t,
              y: py + (y - py) * t,
              radius: stroke.radius,
            ));
          }
        }
        previous = point;
      }
    }
    return samples;
  }

  img.Image _applyRawDevelop(img.Image image, AdjustParams params) {
    var out = image;
    final nr = math.max(params.luminanceNR, params.colourNR);
    if (nr > 0) out = applyNoiseReduction(out, nr);

    final residual = params.copyWith(luminanceNR: 0, colourNR: 0, nrDetail: 0);
    if (!residual.isZero) {
      out = applyImagePipeline(image: out, params: residual, intensity: 1.0);
    }
    return out;
  }

  AdjustParams _mergeCurvesIntoParams(
    AdjustParams base,
    Map<CurveChannel, CurveData> curves,
  ) {
    return base.copyWith(
      luminanceCurve: curves[CurveChannel.luminance] ?? base.luminanceCurve,
      rgbCurve: curves[CurveChannel.rgb] ?? base.rgbCurve,
      redCurve: curves[CurveChannel.red] ?? base.redCurve,
      greenCurve: curves[CurveChannel.green] ?? base.greenCurve,
      blueCurve: curves[CurveChannel.blue] ?? base.blueCurve,
    );
  }

  // ── crop / rotate / flip / perspective ──────────────────

  img.Image _applyCrop(img.Image image, CropState state) {
    var out = image;

    if (state.expandTop > 0 ||
        state.expandBottom > 0 ||
        state.expandLeft > 0 ||
        state.expandRight > 0) {
      out = _applyExpand(out, state);
    }

    if (state.flipH || state.flipV) {
      final dir = state.flipH && state.flipV
          ? img.FlipDirection.both
          : state.flipH
              ? img.FlipDirection.horizontal
              : img.FlipDirection.vertical;
      out = img.copyFlip(out, direction: dir);
    }

    if (state.rotation != 0) {
      out = img.copyRotate(out, angle: state.rotation);
    }

    if (state.perspH != 0 || state.perspV != 0) {
      out = applyPerspectiveSkewInverse(out, state.perspH, state.perspV);
    }

    return cropImage(out, state);
  }

  img.Image _applyExpand(img.Image image, CropState state) {
    final addLeft = (image.width * state.expandLeft).round();
    final addRight = (image.width * state.expandRight).round();
    final addTop = (image.height * state.expandTop).round();
    final addBottom = (image.height * state.expandBottom).round();

    if (addLeft == 0 && addRight == 0 && addTop == 0 && addBottom == 0) {
      return image;
    }

    final newW = image.width + addLeft + addRight;
    final newH = image.height + addTop + addBottom;
    final dst = img.Image(width: newW, height: newH);

    final mode = state.expandMode;
    if (mode == 'black') {
      dst.clear(img.ColorRgba8(0, 0, 0, 255));
    } else if (mode == 'white') {
      dst.clear(img.ColorRgba8(255, 255, 255, 255));
    }

    for (var y = 0; y < newH; y++) {
      for (var x = 0; x < newW; x++) {
        if (x >= addLeft &&
            x < addLeft + image.width &&
            y >= addTop &&
            y < addTop + image.height) {
          dst.setPixel(x, y, image.getPixel(x - addLeft, y - addTop));
        } else if (mode == 'smart') {
          // 스마트 확장: 엣지 반사(Edge Mirroring) 보간
          int sx;
          if (x < addLeft) {
            final dist = addLeft - 1 - x;
            sx = dist % (image.width * 2);
            if (sx >= image.width) {
              sx = 2 * image.width - 1 - sx;
            }
          } else if (x >= addLeft + image.width) {
            final dist = x - (addLeft + image.width);
            sx = image.width - 1 - (dist % (image.width * 2));
            if (sx < 0) {
              sx = -sx - 1;
            }
          } else {
            sx = x - addLeft;
          }

          int sy;
          if (y < addTop) {
            final dist = addTop - 1 - y;
            sy = dist % (image.height * 2);
            if (sy >= image.height) {
              sy = 2 * image.height - 1 - sy;
            }
          } else if (y >= addTop + image.height) {
            final dist = y - (addTop + image.height);
            sy = image.height - 1 - (dist % (image.height * 2));
            if (sy < 0) {
              sy = -sy - 1;
            }
          } else {
            sy = y - addTop;
          }

          sx = sx.clamp(0, image.width - 1);
          sy = sy.clamp(0, image.height - 1);
          dst.setPixel(x, y, image.getPixel(sx, sy));
        }
      }
    }

    return dst;
  }

  // ── portrait ─────────────────────────────────────────────

  img.Image _applyPortrait(
    img.Image image,
    PortraitParams portrait, {
    Float32List? segmentMask,
    Float32List? depthMap,
  }) {
    if (portrait.isZero) return image;

    final mask = segmentMask ?? _ovalFaceMaskPlayer(image.width, image.height);
    var out = image;

    if (portrait.smooth > 0) {
      out = applySkinSmoothing(out, mask, portrait.smooth);
    }
    if (portrait.spotlight > 0) {
      out = applyFaceSpotlight(out, mask, portrait.spotlight);
    }
    if (portrait.skinTone != SkinTone.none) {
      out = applySkinToning(
          out, mask, portrait.skinTone, portrait.skinToneStrength);
    }
    if (portrait.headYaw != 0 || portrait.headPitch != 0) {
      out = applyHeadPoseWarp(
        out,
        mask,
        yaw: portrait.headYaw,
        pitch: portrait.headPitch,
      );
    }
    if (portrait.bokeh > 0) {
      final dm =
          depthMap ?? _fallbackDepthFromMask(mask, out.width, out.height);
      out = applyDepthBokeh(out, dm, portrait.bokeh);
    }

    return out;
  }

  // ── creative ─────────────────────────────────────────────

  img.Image _applyCreative(
    img.Image image,
    CreativeParams creative, {
    Uint8List? blendImageBytes,
    Uint8List? frameBytes,
    Uint8List? textOverlayBytes,
  }) {
    if (creative.isZero) return image;
    var out = image;

    if (creative.blendOpacity > 0) {
      Uint8List? rawBlend;
      if (blendImageBytes != null) {
        rawBlend = blendImageBytes;
      } else if (creative.blendImagePath != null) {
        final f = File(creative.blendImagePath!);
        if (f.existsSync()) rawBlend = f.readAsBytesSync();
      }
      if (rawBlend != null) {
        final blend = img.decodeImage(rawBlend);
        if (blend != null) {
          out = bm.blendImages(
            dst: out,
            src: blend,
            mode: creative.blendMode,
            opacity: creative.blendOpacity.clamp(0.0, 1.0),
          );
        }
      }
    }

    if (frameBytes != null && creative.frameIndex >= 0) {
      final frame = img.decodeImage(frameBytes);
      if (frame != null) {
        out = img.compositeImage(out, frame, dstW: out.width, dstH: out.height);
      }
    }

    if (textOverlayBytes != null) {
      final textImg = img.decodeImage(textOverlayBytes);
      if (textImg != null) {
        out = img.compositeImage(
          out,
          textImg,
          blend: img.BlendMode.alpha,
          dstW: out.width,
          dstH: out.height,
        );
      }
    } else {
      final text = creative.overlayText.trim();
      if (text.isNotEmpty) {
        final c = creative.textColorValue;
        final color = img.ColorRgba8(
          (c >> 16) & 0xff,
          (c >> 8) & 0xff,
          c & 0xff,
          (c >> 24) & 0xff,
        );
        final textLayer = img.Image(
          width: out.width,
          height: out.height,
          numChannels: 4,
        );
        final scale = (creative.textSize / 48.0).clamp(0.25, 4.0);
        final baseX = (out.width * creative.textX).round();
        final baseY = (out.height * creative.textY).round();
        img.drawString(
          textLayer,
          text,
          font: img.arial48,
          x: 0,
          y: 0,
          color: color,
          wrap: true,
        );
        final scaled = scale == 1.0
            ? textLayer
            : img.copyResize(
                textLayer,
                width: (textLayer.width * scale).round().clamp(1, out.width * 4),
                height:
                    (textLayer.height * scale).round().clamp(1, out.height * 4),
                interpolation: img.Interpolation.linear,
              );
        final dstX = (baseX - scaled.width / 2).round();
        final dstY = (baseY - scaled.height / 2).round();
        out = img.compositeImage(
          out,
          scaled,
          dstX: dstX,
          dstY: dstY,
          blend: img.BlendMode.alpha,
        );
      }
    }

    return out;
  }
}

// ── 모듈-레벨 헬퍼 ────────────────────────────────────────

Float32List _ovalFaceMaskPlayer(int width, int height) {
  final mask = Float32List(width * height);
  final cx = width * 0.5;
  final cy = height * 0.38;
  final rx = width * 0.26;
  final ry = height * 0.33;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = (x - cx) / rx;
      final ny = (y - cy) / ry;
      final d = math.sqrt(nx * nx + ny * ny);
      mask[y * width + x] = (1.0 - ((d - 0.78) / 0.22)).clamp(0.0, 1.0);
    }
  }
  return mask;
}

Float32List _fallbackDepthFromMask(Float32List mask, int w, int h) {
  final depth = Float32List(w * h);
  for (int i = 0; i < depth.length; i++) {
    depth[i] = 1.0 - mask[i];
  }
  return depth;
}
