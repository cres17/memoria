import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:path_provider/path_provider.dart';

const _buildMode = String.fromEnvironment(
  'MEMORIA_PERF_BUILD_MODE',
  defaultValue: 'unknown',
);
const _deviceName = String.fromEnvironment(
  'MEMORIA_PERF_DEVICE_NAME',
  defaultValue: 'unknown device',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('G6 completes and validates a 4K JPEG export', (tester) async {
    final directory = await getTemporaryDirectory();
    final input = File('${directory.path}/g6_export_4k_input.jpg');
    final output = File('${directory.path}/g6_export_4k_output.jpg');
    await _create4kFixture(input.path);

    final progress = <double>[];
    final progressElapsedMs = <double>[];
    final stopwatch = Stopwatch()..start();
    final rssBaseline = ProcessInfo.currentRss;
    var peakRss = rssBaseline;
    final rssSampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final current = ProcessInfo.currentRss;
      if (current > peakRss) peakRss = current;
    });

    try {
      final result = await EditorExportService().render(
        EditorExportRequest(
          imagePath: input.path,
          outputPath: output.path,
          format: ExportFormat.jpeg,
          quality: 95,
          recipe: _neutralRecipe(),
        ),
        onProgress: (value) {
          progress.add(value);
          progressElapsedMs.add(stopwatch.elapsedMicroseconds / 1000);
        },
      );
      stopwatch.stop();
      rssSampler.cancel();
      peakRss = _max(peakRss, ProcessInfo.currentRss);

      final validation = await _validate4kOutput(output);
      expect(result, EditorExportJobResult.completed);
      expect(validation.signatureValid, isTrue);
      expect(validation.width, 3840);
      expect(validation.height, 2160);
      expect(progress, isNotEmpty);
      expect(progress.last, 0.95);

      await output.delete();
      await Future<void>.delayed(const Duration(seconds: 2));
      final rssAfter = ProcessInfo.currentRss;
      final resultData = <String, Object>{
        'schemaVersion': 1,
        'scope': 'physical-device/4k-temp-export',
        'buildMode': _buildMode,
        'device': <String, String>{
          'name': _deviceName,
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
        },
        'fixture': <String, Object>{
          'id': 'synthetic-gradient-3840x2160',
          'width': 3840,
          'height': 2160,
        },
        'output': <String, Object>{
          'format': 'jpeg',
          'width': validation.width,
          'height': validation.height,
          'bytes': validation.bytes,
          'signatureValid': validation.signatureValid,
          'photoLibraryWrite': false,
        },
        'durationMs': stopwatch.elapsedMicroseconds / 1000,
        'progress': <String, Object>{
          'samples': progress,
          'elapsedMs': progressElapsedMs,
          'maxIntervalMs': _maxInterval(progressElapsedMs),
        },
        'rssBytes': <String, int>{
          'baseline': rssBaseline,
          'peak': peakRss,
          'after': rssAfter,
          'peakDelta': peakRss - rssBaseline,
          'afterDelta': rssAfter - rssBaseline,
        },
        'limitations': <String>[
          'The output is validated in app temporary storage, not PhotoKit.',
          'RSS is process-wide and includes the integration-test runner.',
        ],
      };
      binding.reportData = <String, Object>{'editor4kExport': resultData};
      // ignore: avoid_print
      print('EDITOR_4K_G6_RESULT=${jsonEncode(resultData)}');
    } finally {
      rssSampler.cancel();
      if (await input.exists()) await input.delete();
      if (await output.exists()) await output.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _OutputValidation {
  final int width;
  final int height;
  final int bytes;
  final bool signatureValid;

  const _OutputValidation({
    required this.width,
    required this.height,
    required this.bytes,
    required this.signatureValid,
  });
}

Future<_OutputValidation> _validate4kOutput(File output) async {
  final bytes = await output.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('Could not decode 4K export output.');
  return _OutputValidation(
    width: decoded.width,
    height: decoded.height,
    bytes: bytes.length,
    signatureValid: ExportEncoder.matchesSignature(ExportFormat.jpeg, bytes),
  );
}

Future<void> _create4kFixture(String path) async {
  final completionPort = ReceivePort();
  await Isolate.spawn<String>(
    _write4kFixture,
    path,
    onExit: completionPort.sendPort,
    onError: completionPort.sendPort,
    errorsAreFatal: true,
  );
  try {
    final message = await completionPort.first;
    if (message is List && message.isNotEmpty) {
      throw StateError('4K fixture worker failed: ${message.first}');
    }
  } finally {
    completionPort.close();
  }
}

void _write4kFixture(String path) {
  final image = img.Image(width: 3840, height: 2160);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 3 + y) % 256,
        (x + y * 2) % 256,
        (x + y) % 256,
      );
    }
  }
  File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95), flush: true);
}

EditorRenderRecipe _neutralRecipe() => EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: CropState.identity,
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
    );

int _max(int left, int right) => left > right ? left : right;

double _maxInterval(List<double> elapsedMs) {
  if (elapsedMs.length < 2) return 0;
  var maximum = 0.0;
  for (var i = 1; i < elapsedMs.length; i++) {
    final interval = elapsedMs[i] - elapsedMs[i - 1];
    if (interval > maximum) maximum = interval;
  }
  return maximum;
}
