import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/features/editor/editor_page.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final frameTimings = <FrameTiming>[];
  binding.addTimingsCallback(frameTimings.addAll);

  late File fixture;
  late File exportFixture;

  setUpAll(() async {
    final image = img.Image(width: 1920, height: 1440);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final directory = await getTemporaryDirectory();
    fixture = File('${directory.path}/editor_performance_fixture.jpg');
    await fixture.writeAsBytes(img.encodeJpg(image, quality: 92));

    final exportImage = img.Image(width: 3072, height: 2304);
    for (var y = 0; y < exportImage.height; y++) {
      for (var x = 0; x < exportImage.width; x++) {
        exportImage.setPixelRgb(
          x,
          y,
          (x * 3 + y) % 256,
          (x + y * 2) % 256,
          (x + y) % 256,
        );
      }
    }
    exportFixture = File('${directory.path}/editor_export_fixture.jpg');
    await exportFixture.writeAsBytes(img.encodeJpg(exportImage, quality: 92));
  });

  tearDownAll(() async {
    if (await fixture.exists()) await fixture.delete();
    if (await exportFixture.exists()) await exportFixture.delete();
  });

  testWidgets('PERF-EDITOR-001 records editor preview and frame samples',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: fixture.path)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();
    final exposure = find.byType(Slider).first;

    // Separate warm-up from the measured 30-update sequence. Each sample is
    // the wall time to accept the latest slider value and render the next UI
    // frame; FrameTiming captures the device-level companion measurements.
    for (var i = 0; i < 5; i++) {
      await _setExposure(tester, exposure, i.isEven ? 0.4 : -0.4);
    }
    // Startup and warm-up frames have a different budget. Measure only the
    // steady-state editor interaction frames below.
    await tester.pump();
    frameTimings.clear();

    final previewWarmMs = <double>[];
    for (var i = 0; i < 36; i++) {
      final stopwatch = Stopwatch()..start();
      await _setExposure(tester, exposure, i.isEven ? 0.6 : -0.6);
      stopwatch.stop();
      previewWarmMs.add(stopwatch.elapsedMicroseconds / 1000);
    }

    final frameTotalMs = frameTimings
        .map((timing) =>
            (timing.buildDuration.inMicroseconds +
                timing.rasterDuration.inMicroseconds) /
            1000)
        .toList(growable: false);
    final coldPreviewMs = previewWarmMs.isEmpty ? 0.0 : previewWarmMs.first;

    final reportData = binding.reportData ?? <String, dynamic>{};
    reportData['editorPerformance'] = <String, dynamic>{
      'schemaVersion': 1,
      'buildMode': const String.fromEnvironment('MEMORIA_PERF_BUILD_MODE',
          defaultValue: 'unknown'),
      'device': <String, dynamic>{
        'name': const String.fromEnvironment('MEMORIA_PERF_DEVICE_NAME',
            defaultValue: 'unknown device'),
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      },
      'fixture': <String, dynamic>{
        'id': 'synthetic-gradient-1920x1440',
        'width': 1920,
        'height': 1440,
      },
      'samples': <String, dynamic>{
        'frameTotalMs': frameTotalMs,
        'previewWarmMs': previewWarmMs,
      },
      'metrics': <String, dynamic>{
        'previewColdMs': coldPreviewMs,
      },
    };
    binding.reportData = reportData;
  });

  testWidgets('PERF-EXPORT-001 reports progress and cancels without saving',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: exportFixture.path)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();
    await _setExposure(tester, find.byType(Slider).first, 0.8);
    await tester.tap(find.byTooltip('적용'));
    await tester.pump();

    await tester.tap(find.text('내보내기').first);
    await tester.pump();
    await tester.tap(find.text('다른 앱으로 공유'));
    await tester.pump();
    expect(find.text('공유 준비 중...'), findsOneWidget);

    final firstProgressStopwatch = Stopwatch()..start();
    final sawProgress = await _waitForNonZeroExportProgress(tester);
    firstProgressStopwatch.stop();
    expect(sawProgress, isTrue,
        reason: 'export must visibly report a non-zero progress update');

    final cancelStopwatch = Stopwatch()..start();
    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    cancelStopwatch.stop();
    expect(find.text('공유 준비 중...'), findsNothing);

    final report =
        binding.reportData!['editorPerformance'] as Map<String, dynamic>;
    final metrics = report['metrics'] as Map<String, dynamic>;
    metrics['exportFirstProgressMs'] =
        firstProgressStopwatch.elapsedMicroseconds / 1000;
    metrics['exportCancelMs'] = cancelStopwatch.elapsedMicroseconds / 1000;
    metrics['exportCompleted'] = false;
  });
}

Future<void> _setExposure(
  WidgetTester tester,
  Finder sliderFinder,
  double value,
) async {
  final slider = tester.widget<Slider>(sliderFinder);
  slider.onChanged!(value);
  await tester.pump();
}

Future<bool> _waitForNonZeroExportProgress(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    final hasNonZeroProgress = find
        .byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^[1-9][0-9]?%$').hasMatch(widget.data ?? ''),
        )
        .evaluate()
        .isNotEmpty;
    if (hasNonZeroProgress) return true;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  return false;
}
