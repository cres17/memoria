import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memoria/ai/models/lut_predictor.dart';
import 'package:path_provider/path_provider.dart';

const _modelAssetPath = String.fromEnvironment(
  'DIRECT_MVP_DEVICE_MODEL_ASSET',
  defaultValue: 'assets/models/direct_mvp_color_transfer_fp16.tflite',
);
const _referenceAssetPath = String.fromEnvironment(
  'DIRECT_MVP_DEVICE_REFERENCE_ASSET',
  defaultValue: 'assets/images/summer_sapporo.jpg',
);
const _buildMode = String.fromEnvironment(
  'MEMORIA_PERF_BUILD_MODE',
  defaultValue: 'unknown',
);
const _deviceName = String.fromEnvironment(
  'MEMORIA_PERF_DEVICE_NAME',
  defaultValue: 'unknown device',
);
const _isPhysicalDevice = bool.fromEnvironment(
  'MEMORIA_PHYSICAL_DEVICE',
  defaultValue: false,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'G6 records Direct MVP cold/warm latency and process RSS',
    (tester) async {
      final temporaryDirectory = await getTemporaryDirectory();
      final modelFile = File('${temporaryDirectory.path}/g6_candidate.tflite');
      final referenceFile = File('${temporaryDirectory.path}/g6_reference.jpg');
      await _copyAsset(_modelAssetPath, modelFile);
      await _copyAsset(_referenceAssetPath, referenceFile);

      final rssBaseline = ProcessInfo.currentRss;
      var peakRss = rssBaseline;
      final coldLoadMs = <double>[];
      final coldGenerateMs = <double>[];

      try {
        for (var i = 0; i < 5; i++) {
          final loadWatch = Stopwatch()..start();
          final predictor = await LutPredictor.fromPath(modelFile.path);
          loadWatch.stop();
          coldLoadMs.add(loadWatch.elapsedMicroseconds / 1000);

          final generateWatch = Stopwatch()..start();
          final lut = await predictor.predict(referenceFile.path);
          generateWatch.stop();
          coldGenerateMs.add(generateWatch.elapsedMicroseconds / 1000);
          expect(lut.length, 65 * 65 * 65 * 3);
          peakRss = _max(peakRss, ProcessInfo.currentRss);
          predictor.dispose();
        }

        final predictor = await LutPredictor.fromPath(modelFile.path);
        for (var i = 0; i < 3; i++) {
          await predictor.predict(referenceFile.path);
        }

        final warmGenerateMs = <double>[];
        for (var i = 0; i < 30; i++) {
          final watch = Stopwatch()..start();
          final lut = await predictor.predict(referenceFile.path);
          watch.stop();
          warmGenerateMs.add(watch.elapsedMicroseconds / 1000);
          expect(lut.length, 65 * 65 * 65 * 3);
          peakRss = _max(peakRss, ProcessInfo.currentRss);
        }
        predictor.dispose();

        final rssAfter = ProcessInfo.currentRss;
        final result = <String, Object>{
          'schemaVersion': 1,
          'scope': _isPhysicalDevice
              ? 'physical-device/interpreter-cold-proxy'
              : 'simulator/interpreter-cold-proxy',
          'buildMode': _buildMode,
          'modelAsset': _modelAssetPath,
          'device': <String, String>{
            'name': _deviceName,
            'os': Platform.operatingSystem,
            'osVersion': Platform.operatingSystemVersion,
          },
          'sampleCounts': <String, int>{
            'cold': coldGenerateMs.length,
            'warm': warmGenerateMs.length,
          },
          'latencyMs': <String, Object>{
            'coldLoad': _summary(coldLoadMs),
            'coldGenerate': _summary(coldGenerateMs),
            'warmGenerate': _summary(warmGenerateMs),
          },
          'rssBytes': <String, int>{
            'baseline': rssBaseline,
            'peak': peakRss,
            'after': rssAfter,
            'peakDelta': peakRss - rssBaseline,
            'afterDelta': rssAfter - rssBaseline,
          },
          'limitations': <String>[
            if (!_isPhysicalDevice)
              'Simulator measurement; not a physical-device G6 result.',
            'Cold samples recreate the interpreter inside one app process.',
            'RSS is process-wide and includes the integration-test runner.',
          ],
        };
        binding.reportData = <String, Object>{'directMvpDevice': result};
        // Printed JSON is retained by flutter test even without a host driver.
        // ignore: avoid_print
        print('DIRECT_MVP_G6_RESULT=${jsonEncode(result)}');
      } finally {
        LutPredictor.resetForTesting();
        if (await modelFile.exists()) await modelFile.delete();
        if (await referenceFile.exists()) await referenceFile.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _copyAsset(String assetPath, File destination) async {
  final data = await rootBundle.load(assetPath);
  await destination.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

int _max(int left, int right) => left > right ? left : right;

Map<String, double> _summary(List<double> values) {
  final sorted = [...values]..sort();
  return <String, double>{
    'min': sorted.first,
    'mean': values.reduce((a, b) => a + b) / values.length,
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'max': sorted.last,
  };
}

double _percentile(List<double> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index];
}
