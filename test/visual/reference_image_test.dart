import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/inpainting.dart';
import 'package:memoria/engine/sky_mask.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';

/// 실제 사진에 고정 레시피를 적용한 결과를 저장된 기준 PNG와 픽셀 단위로 비교한다.
///
/// 기존 골든 테스트는 해시/요약값이라 어디가 얼마나 달라졌는지 알 수 없다. 이 테스트는
/// 허용 오차 안에서 비교하고, 실패하면 차이 이미지를 `build/visual_diff/`에 남긴다.
///
/// 의도한 변경이면 기준을 다시 만든다:
///   UPDATE_REFERENCES=1 flutter test test/visual/reference_image_test.dart
/// 그리고 바뀐 PNG를 눈으로 확인한 뒤 커밋한다.
const _longEdge = 256;
const _maxMeanDiff = 0.6; // 채널 평균 절대 오차(0~255)
const _maxP99Diff = 4; // 채널 오차 99 퍼센타일
const _maxChanged = 0.03; // 오차 8 초과 픽셀 비율
const _maxBlockMean = 1.5; // 16×16 블록 평균 오차의 최댓값(작은 영역의 국소 변화를 잡는다)
const _maxDrift = 0.01; // 오차 2 초과 픽셀 비율(좁은 영역의 미세한 변화를 잡는다)

final _update = Platform.environment['UPDATE_REFERENCES'] == '1';

final gpuVisualReferenceCases =
    <String, ({String photo, EditorRenderRecipe recipe})>{
  'tone_balance': (
    photo: 'p1',
    recipe: _recipe(
      const AdjustParams(
        exposure: 0.3,
        contrast: 16,
        saturation: 14,
        temperature: 10,
        highlights: -20,
        shadows: 18,
      ),
    ),
  ),
  'film_look': (
    photo: 'p2',
    recipe: _recipe(
      const AdjustParams(
          contrast: 8,
          saturation: -6,
          grainStrength: 14,
          grainSize: 1.2,
          grainSeed: 11),
      effect: ArtisticEffect.vintage,
      effectStrength: 0.7,
    ),
  ),
  'sky_cooler': (
    photo: 'p1',
    recipe: _recipe(
      AdjustParams.zero,
      sky: const SkyAdjust(brightness: -40, saturation: 40, warmth: -60),
    ),
  ),
  'local_dodge_burn_selective': (
    photo: 'p2',
    recipe: _recipe(
      AdjustParams.zero,
      selective: true,
      dodgeBurn: true,
    ),
  ),
  'tilt_shift_heal': (
    photo: 'p1',
    recipe: _recipe(
      AdjustParams.zero,
      tilt: true,
      heal: const [HealSpot(x: 0.5, y: 0.5, radius: 0.08)],
    ),
  ),
};

void main() {
  late img.Image photo1;
  late img.Image photo2;

  setUpAll(() {
    photo1 = _load('test/원본_1.jpg');
    photo2 = _load('test/원본_2.jpg');
  });

  for (final entry in gpuVisualReferenceCases.entries) {
    test('기준 이미지와 일치: ${entry.key}', () async {
      final source = entry.value.photo == 'p1' ? photo1 : photo2;
      final rendered = await EditorRenderer.renderExport(
        source: source.clone(),
        recipe: entry.value.recipe,
      );
      final file = File('test/visual/references/${entry.key}.png');

      if (_update) {
        file.writeAsBytesSync(img.encodePng(rendered, level: 9));
        return;
      }
      expect(file.existsSync(), isTrue,
          reason:
              '기준 이미지가 없습니다. UPDATE_REFERENCES=1 로 만든 뒤 확인하고 커밋하세요: ${file.path}');
      final reference = img.decodePng(file.readAsBytesSync())!;
      expect([
        rendered.width,
        rendered.height
      ], [
        reference.width,
        reference.height
      ], reason: '크기가 달라졌습니다');

      final diff = compareVisualReference(rendered, reference);
      if (!diff.ok) {
        final dir = Directory('build/visual_diff')..createSync(recursive: true);
        File('${dir.path}/${entry.key}.actual.png')
            .writeAsBytesSync(img.encodePng(rendered));
        File('${dir.path}/${entry.key}.diff.png')
            .writeAsBytesSync(img.encodePng(_diffImage(rendered, reference)));
      }
      expect(diff.mean, lessThanOrEqualTo(_maxMeanDiff),
          reason: diff.toString());
      expect(diff.p99, lessThanOrEqualTo(_maxP99Diff), reason: diff.toString());
      expect(diff.changedRatio, lessThanOrEqualTo(_maxChanged),
          reason: diff.toString());
      expect(diff.driftRatio, lessThanOrEqualTo(_maxDrift),
          reason: diff.toString());
      expect(diff.worstBlock, lessThanOrEqualTo(_maxBlockMean),
          reason: diff.toString());
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('비교기 자체 검증: 같은 이미지는 통과, 눈에 띄는 변화는 실패', () {
    final a = img.Image(width: 32, height: 32);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        a.setPixelRgb(x, y, x * 8, y * 8, 128);
      }
    }
    expect(compareVisualReference(a, a.clone()).ok, isTrue);
    final b = a.clone();
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        b.setPixelRgb(x, y, 255 - x * 8, 0, 128);
      }
    }
    expect(compareVisualReference(a, b).ok, isFalse);
    // 한 채널이 1단계씩 흔들리는 정도(부동소수 오차 수준)는 통과
    final c = a.clone();
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        final p = c.getPixel(x, y);
        c.setPixelRgb(x, y, (p.r + 1).clamp(0, 255), p.g, p.b);
      }
    }
    expect(compareVisualReference(a, c).ok, isTrue);
  });
}

img.Image _load(String path) {
  return prepareVisualReferenceImage(
      img.decodeJpg(File(path).readAsBytesSync())!);
}

img.Image prepareVisualReferenceImage(img.Image decoded) {
  final baked = img.bakeOrientation(decoded);
  final scale =
      _longEdge / (baked.width > baked.height ? baked.width : baked.height);
  return img.copyResize(
    baked,
    width: (baked.width * scale).round(),
    height: (baked.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

class VisualReferenceDiff {
  final double mean;
  final int p99;
  final double changedRatio;
  final double driftRatio;
  final double worstBlock;
  const VisualReferenceDiff(
      this.mean, this.p99, this.changedRatio, this.driftRatio, this.worstBlock);

  bool get ok =>
      mean <= _maxMeanDiff &&
      p99 <= _maxP99Diff &&
      changedRatio <= _maxChanged &&
      driftRatio <= _maxDrift &&
      worstBlock <= _maxBlockMean;

  @override
  String toString() =>
      'mean=${mean.toStringAsFixed(3)} p99=$p99 changed>8=${(changedRatio * 100).toStringAsFixed(2)}% drift>2=${(driftRatio * 100).toStringAsFixed(2)}% block=${worstBlock.toStringAsFixed(2)}';
}

VisualReferenceDiff compareVisualReference(img.Image a, img.Image b) {
  final histogram = List<int>.filled(256, 0);
  var sum = 0;
  var changed = 0;
  var drift = 0;
  var pixels = 0;
  const block = 16;
  final blocksX = (a.width + block - 1) ~/ block;
  final blockSums =
      List<int>.filled(blocksX * ((a.height + block - 1) ~/ block), 0);
  final blockCounts = List<int>.filled(blockSums.length, 0);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      var worst = 0;
      for (final d in [
        (pa.r - pb.r).abs().toInt(),
        (pa.g - pb.g).abs().toInt(),
        (pa.b - pb.b).abs().toInt(),
      ]) {
        histogram[d]++;
        sum += d;
        blockSums[(y ~/ block) * blocksX + x ~/ block] += d;
        blockCounts[(y ~/ block) * blocksX + x ~/ block]++;
        if (d > worst) worst = d;
      }
      if (worst > 8) changed++;
      if (worst > 2) drift++;
      pixels++;
    }
  }
  final total = pixels * 3;
  var acc = 0;
  var p99 = 0;
  for (var i = 0; i < 256; i++) {
    acc += histogram[i];
    if (acc >= total * 0.99) {
      p99 = i;
      break;
    }
  }
  var worstBlock = 0.0;
  for (var i = 0; i < blockSums.length; i++) {
    final m = blockSums[i] / blockCounts[i];
    if (m > worstBlock) worstBlock = m;
  }
  return VisualReferenceDiff(
      sum / total, p99, changed / pixels, drift / pixels, worstBlock);
}

img.Image _diffImage(img.Image a, img.Image b) {
  final out = img.Image(width: a.width, height: a.height);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      final d = [
        (pa.r - pb.r).abs(),
        (pa.g - pb.g).abs(),
        (pa.b - pb.b).abs(),
      ].reduce((m, v) => v > m ? v : m);
      final v = (d * 8).clamp(0, 255).toInt();
      out.setPixelRgb(x, y, v, 0, 255 - v);
    }
  }
  return out;
}

EditorRenderRecipe _recipe(
  AdjustParams params, {
  ArtisticEffect effect = ArtisticEffect.none,
  double effectStrength = 1,
  SkyAdjust sky = const SkyAdjust(),
  bool selective = false,
  bool dodgeBurn = false,
  bool tilt = false,
  List<HealSpot> heal = const [],
}) =>
    EditorRenderRecipe(
      adjustParams: params,
      lutBytes: null,
      intensity: 1,
      crop: const CropState(),
      cropAspectRatio: null,
      effect: effect,
      effectStrength: effectStrength,
      grainVariant: 2,
      selectiveActive: selective,
      selectiveX: 0.35,
      selectiveY: 0.4,
      selectiveBrightness: 25,
      selectiveContrast: 10,
      selectiveSaturation: 15,
      selectiveRadius: 0.3,
      dodgeBurnActive: dodgeBurn,
      dodgeStrength: 0.5,
      dodgeY: 0.3,
      dodgeRadius: 0.3,
      burnStrength: 0.5,
      burnY: 0.8,
      burnRadius: 0.3,
      tiltActive: tilt,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.25,
      tiltMaxBlur: 6,
      lensActive: false,
      lensFocusDepth: 0,
      lensMaxRadius: 0,
      portrait: PortraitParams.zero,
      creative: CreativeParams.zero,
      brushStrokes: const [],
      sky: sky,
      healStrokes: heal,
    );
