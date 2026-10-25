import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/ai/models/sky_segmenter.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/sky_mask.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:memoria/features/editor/editor_resource_preparer.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';

const _n = SkySegmenter.size;

Float32List _topHalf(double v) {
  final out = Float32List(_n * _n);
  for (var y = 0; y < _n ~/ 2; y++) {
    for (var x = 0; x < _n; x++) {
      out[y * _n + x] = v;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('전처리·후처리', () {
    test('CHW 순서와 0~1 범위로 채운다', () {
      final image = img.Image(width: 8, height: 8);
      image.clear(img.ColorRgb8(255, 0, 128));
      final input = SkySegmenter.preprocess(image);
      const plane = _n * _n;
      expect(input.length, 3 * plane);
      expect(input[0], closeTo(1.0, 1e-6)); // R 평면
      expect(input[plane], closeTo(0.0, 1e-6)); // G 평면
      expect(input[2 * plane], closeTo(128 / 255, 1e-3)); // B 평면
      expect(input[plane - 1], closeTo(1.0, 1e-6));
    });

    test('확률을 0~1로 자르고 NaN은 0으로, 경계는 부드럽게 잇는다', () {
      final raw = _topHalf(1.0);
      raw[0] = double.nan;
      raw[1] = 2.0;
      raw[2] = -1.0;
      raw[3] = 0.5;
      final mask = SkySegmenter.postprocess(raw);
      expect(mask.data[0], 0.0);
      expect(mask.data[1], 1.0);
      expect(mask.data[2], 0.0);
      expect(mask.data[3], closeTo(0.5, 1e-6));
      expect(mask.width, _n);
      expect(mask.height, _n);
    });

    test('하늘 면적이 0.5% 미만이면 하늘 없음으로 본다', () {
      final raw = Float32List(_n * _n);
      for (var i = 0; i < 200; i++) {
        raw[i] = 1.0; // 0.2%
      }
      expect(SkySegmenter.postprocess(raw).isEmpty, isTrue);
      for (var i = 0; i < 1000; i++) {
        raw[i] = 1.0; // 약 1%
      }
      expect(SkySegmenter.postprocess(raw).isEmpty, isFalse);
    });

    test('출력 크기가 다르면 오류', () {
      expect(() => SkySegmenter.postprocess(Float32List(10)), throwsArgumentError);
    });

    test('가짜 추론기로 위쪽 절반만 하늘인 마스크를 만든다', () async {
      final seg = SkySegmenter((input) async {
        expect(input.length, 3 * _n * _n);
        return _topHalf(1.0);
      });
      final mask = await seg.segment(img.Image(width: 40, height: 30));
      expect(mask.sample(0.5, 0.1), closeTo(1.0, 1e-6));
      expect(mask.sample(0.5, 0.9), closeTo(0.0, 1e-6));
    });
  });

  group('렌더러', () {
    img.Image gray(int w, int h) {
      final image = img.Image(width: w, height: h, numChannels: 4);
      image.clear(img.ColorRgba8(120, 120, 120, 255));
      return image;
    }

    double meanLuma(img.Image im, int y0, int y1) {
      var sum = 0.0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = 0; x < im.width; x++) {
          sum += im.getPixel(x, y).r;
          n++;
        }
      }
      return sum / n;
    }

    test('모델 마스크가 있으면 그 영역에만 보정이 적용된다(색 기반 인식은 쓰지 않는다)', () async {
      final out = await EditorRenderer.renderExport(
        source: gray(64, 64),
        recipe: _recipe(sky: const SkyAdjust(brightness: 60)),
        resources: EditorRenderResources(
            skyMask: _topHalf(1.0), skyMaskWidth: _n, skyMaskHeight: _n),
      );
      expect(meanLuma(out, 2, 28), greaterThan(meanLuma(out, 36, 62) + 20));
    });

    test('세로로 뒤집으면 마스크도 같이 뒤집혀 아래쪽이 보정된다', () async {
      final out = await EditorRenderer.renderExport(
        source: gray(64, 64),
        recipe: _recipe(
            sky: const SkyAdjust(brightness: 60),
            crop: const CropState(flipV: true)),
        resources: EditorRenderResources(
            skyMask: _topHalf(1.0), skyMaskWidth: _n, skyMaskHeight: _n),
      );
      expect(meanLuma(out, 36, 62), greaterThan(meanLuma(out, 2, 28) + 20));
    });

    test('빈 마스크(하늘 없음)면 사진을 그대로 둔다', () async {
      final source = gray(64, 64);
      final out = await EditorRenderer.renderExport(
        source: source,
        recipe: _recipe(sky: const SkyAdjust(brightness: 80)),
        resources: EditorRenderResources(
            skyMask: Float32List(_n * _n), skyMaskWidth: _n, skyMaskHeight: _n),
      );
      expect(out.getBytes(), source.getBytes());
    });

    test('모델 마스크가 없으면 기존 색 기반 인식으로 동작한다', () async {
      final sky = img.Image(width: 64, height: 64, numChannels: 4);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          sky.setPixelRgba(x, y, y < 32 ? 110 : 70, y < 32 ? 160 : 110, y < 32 ? 235 : 45, 255);
        }
      }
      final out = await EditorRenderer.renderExport(
        source: sky,
        recipe: _recipe(sky: const SkyAdjust(brightness: -50)),
      );
      expect(meanLuma(out, 2, 28), lessThan(110 - 10));
    });

    test('크기가 맞지 않는 마스크는 무시한다', () async {
      final source = gray(32, 32);
      final out = await EditorRenderer.renderExport(
        source: source,
        recipe: _recipe(sky: const SkyAdjust(brightness: 60)),
        resources: EditorRenderResources(
            skyMask: Float32List(10), skyMaskWidth: _n, skyMaskHeight: _n),
      );
      expect(out.width, 32); // 오류 없이 색 기반 인식으로 처리
    });
  });

  group('리소스 준비', () {
    EditorResourcePreparer preparer({EditorSkyMaskLoader? sky}) =>
        EditorResourcePreparer(
          loadFrame: (_) async => null,
          loadBlend: (_) async => null,
          loadPortraitMask: (_, __) async => null,
          loadSkyMask: sky,
        );

    EditorResourcePreparationRequest request({bool sky = true}) =>
        EditorResourcePreparationRequest(
          recipe: _recipe(),
          maskSource: img.Image(width: 8, height: 8),
          maskSourceKey: 'k',
          targetGeometry: const EditorTargetGeometry(width: 8, height: 8),
          frameIndex: -1,
          blendImagePath: null,
          preparePortraitMask: false,
          prepareTextOverlay: false,
          prepareSkyMask: sky,
        );

    test('요청했을 때만 하늘 마스크를 만든다', () async {
      var calls = 0;
      final p = preparer(sky: (_, __) async {
        calls++;
        return EditorSkyMaskResource(
            data: _topHalf(1), width: _n, height: _n);
      });
      final off = await p.prepare(request(sky: false));
      expect(off.renderResources.skyMask, isNull);
      expect(calls, 0);
      final on = await p.prepare(request());
      expect(on.renderResources.skyMask, isNotNull);
      expect(on.renderResources.skyMaskWidth, _n);
      expect(calls, 1);
    });

    test('모델 실패는 오류로 멈추지 않고 마스크 없음으로 대체된다', () async {
      final p = preparer(sky: (_, __) async => throw StateError('boom'));
      final r = await p.prepare(request());
      expect(r.renderResources.skyMask, isNull);
    });
  });

  group('모델 설치 상태', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('memoria-sky-model-');
      AiManager.instance.clearLocalModelForTesting(kModelSkySeg);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
        return null;
      });
    });

    tearDown(() async {
      AiManager.instance.clearLocalModelForTesting(kModelSkySeg);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('받은 파일이 없으면 준비 상태가 되지 않고 네트워크도 쓰지 않는다', () async {
      expect(await AiManager.instance.restoreIfInstalled(kModelSkySeg), isFalse);
      expect(AiManager.instance.stateOf(kModelSkySeg.key).status,
          ModelStatus.notDownloaded);
    });

    test('크기·해시가 다른 파일은 지우고 준비되지 않는다', () async {
      final f = File('${dir.path}/ai_models/${kModelSkySeg.key}.tflite');
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
      expect(await AiManager.instance.restoreIfInstalled(kModelSkySeg), isFalse);
      expect(f.existsSync(), isFalse);
    });

    test('모델 정보: 고정된 릴리스 주소와 SHA-256', () {
      expect(kModelSkySeg.url, startsWith('https://github.com/cres17/memoria/releases/download/'));
      expect(kModelSkySeg.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(kModelSkySeg.sizeBytes, greaterThan(50 * 1024 * 1024));
      // 해시 계산기 사용 확인(import 유지)
      expect(sha256.convert([1]).toString().length, 64);
    });
  });
}

EditorRenderRecipe _recipe({
  SkyAdjust sky = const SkyAdjust(),
  CropState crop = CropState.identity,
}) =>
    EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: crop,
      cropAspectRatio: null,
      effect: ArtisticEffect.none,
      effectStrength: 1,
      grainVariant: 0,
      selectiveActive: false,
      selectiveX: 0.5,
      selectiveY: 0.5,
      selectiveBrightness: 0,
      selectiveContrast: 0,
      selectiveSaturation: 0,
      selectiveRadius: 0.3,
      dodgeBurnActive: false,
      dodgeStrength: 0,
      dodgeY: 0.5,
      dodgeRadius: 0.3,
      burnStrength: 0,
      burnY: 0.5,
      burnRadius: 0.3,
      tiltActive: false,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.3,
      tiltMaxBlur: 0,
      lensActive: false,
      lensFocusDepth: 0,
      lensMaxRadius: 0,
      portrait: PortraitParams.zero,
      creative: CreativeParams.zero,
      brushStrokes: const [],
      sky: sky,
    );
