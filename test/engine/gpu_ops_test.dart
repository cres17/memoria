import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/core/remote_config/remote_config.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/fast_blur.dart';
import 'package:memoria/engine/gpu_ops.dart';
import 'package:memoria/engine/image_operation.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/gpu_recipe.dart';

img.Image pattern() {
  final image = img.Image(width: 64, height: 48, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(
          x, y, x * 4, y * 5, (x * 31 + y * 17) % 256, (x + y) % 256);
    }
  }
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(GpuOps.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('GPU config is opt-in and rejects non-boolean values', () {
    expect(RemoteConfig.defaults.gpuOpsIosEnabled, isFalse);
    expect(RemoteConfig.parse('{"schema":1,"disabled":{}}')!.gpuOpsIosEnabled,
        isFalse);
    expect(
        RemoteConfig.parse(
                '{"schema":1,"disabled":{},"enabled":{"gpu_ops_ios":true}}')!
            .gpuOpsIosEnabled,
        isTrue);
    expect(
        RemoteConfig.parse(
            '{"schema":1,"disabled":{},"enabled":{"gpu_ops_ios":1}}'),
        isNull);
  });

  test('GPU enablement expires at render boundaries in a long-running app',
      () async {
    final fetched = DateTime.now().subtract(const Duration(days: 15));
    SharedPreferences.setMockInitialValues({
      RemoteConfigService.cacheKey:
          '{"schema":1,"disabled":{},"enabled":{"gpu_ops_ios":true}}',
      RemoteConfigService.fetchedAtKey: fetched.millisecondsSinceEpoch,
    });
    final service = RemoteConfigService.instance;
    // Load as if the app had started while this cache was fresh. The effective
    // policy must still expire when the wall clock advances beyond its TTL.
    await service.loadCached(now: () => fetched.add(const Duration(hours: 1)));
    expect(service.current.gpuOpsIosEnabled, isTrue);
    expect(service.gpuOpsIosEnabled, isFalse);
    service.resetForTest();
  });

  test('disabled and Android issue zero native calls', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(GpuOps.channel, (_) async {
      calls++;
      return null;
    });
    for (final enabled in [false, true]) {
      debugDefaultTargetPlatformOverride =
          enabled ? TargetPlatform.android : TargetPlatform.iOS;
      final input = pattern();
      final expected = fastGaussianBlur(img.Image.from(input), radius: 5);
      final op = ImageOperation.blur(input, 5);
      await GpuOps(enabled: enabled).resolve(op);
      expect(op.result!.getBytes(), expected.getBytes());
    }
    expect(calls, 0);
  });

  test('valid native blur preserves in-place semantics and alpha', () async {
    final input = pattern();
    final expected = fastGaussianBlur(img.Image.from(input), radius: 5);
    messenger.setMockMethodCallHandler(GpuOps.channel, (call) async {
      expect(call.method, 'gpuOp');
      expect((call.arguments as Map)['channels'], 4);
      return {'bytes': Uint8List.fromList(expected.toUint8List())};
    });
    final op = ImageOperation.blur(input, 5);
    await const GpuOps(enabled: true).resolve(op);
    expect(identical(input, op.result), isTrue);
    expect(input.getBytes(), expected.getBytes());
  });

  test('malformed output and channel errors preserve CPU results', () async {
    for (final fail in [false, true]) {
      messenger.setMockMethodCallHandler(GpuOps.channel, (_) async {
        if (fail) throw PlatformException(code: 'GPU_FAILED');
        return {'bytes': Uint8List(1)};
      });
      final input = pattern();
      final expected = fastGaussianBlur(img.Image.from(input), radius: 5);
      final op = ImageOperation.blur(input, 5);
      await const GpuOps(enabled: true).resolve(op);
      expect(op.result!.getBytes(), expected.getBytes());
    }
  });

  test('late GPU failure reruns the complete recipe on CPU', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(GpuOps.channel, (call) async {
      calls++;
      if (calls > 1) throw PlatformException(code: 'GPU_FAILED');
      final bytes = (call.arguments as Map)['bytes'] as Uint8List;
      return {
        'bytes': Uint8List(bytes.length)..fillRange(0, bytes.length, 100)
      };
    });
    final recipe = gpuRecipe(
        const AdjustParams(
            luminanceNR: 25, colourNR: 25, sharpen: 30, glowStrength: 20),
        tools: true);
    final expected = await EditorRenderer.applyVisual(
        pattern(), recipe, const EditorRenderResources());
    final actual = await EditorRenderer.applyVisual(
        pattern(), recipe, const EditorRenderResources(),
        gpu: const GpuOps(enabled: true));
    expect(calls, greaterThan(1));
    expect(actual.getBytes(), expected.getBytes());
  });

  test('asynchronous CPU driver is byte identical for composed effects',
      () async {
    const params = AdjustParams(
        luminanceNR: 25,
        colourNR: 75,
        nrDetail: 60,
        hdrStrength: 40,
        glowStrength: 30,
        halationStrength: 20,
        sharpen: 20,
        structure: 10,
        clarity: 15);
    final expected = applyImagePipeline(image: pattern(), params: params);
    final actual =
        await applyImagePipelineAsync(image: pattern(), params: params);
    expect(actual.getBytes(), expected.getBytes());
  });
}
