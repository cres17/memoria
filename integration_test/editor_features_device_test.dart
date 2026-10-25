import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/engine/inpainting.dart';
import 'package:memoria/engine/raw_import.dart';
import 'package:memoria/engine/sky_mask.dart';
import 'package:memoria/features/batch/batch_apply_service.dart';
import 'package:memoria/features/editor/editor_media_export_coordinator.dart';
import 'package:memoria/features/editor/editor_page.dart';
import 'package:path_provider/path_provider.dart';

import 'support/dng_fixture.dart';

/// 실제 앱 프로세스(시뮬레이터·에뮬레이터·실기기)에서 새 편집 기능을 확인한다.
///
/// 사진 보관함에는 쓰지 않는다. 모든 입력·출력은 앱 임시 폴더에 만들고 지운다.
/// 처리 시간은 `DEVICE_PERF <이름>=<ms>` 줄로 출력한다.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final perf = <String, int>{};

  late Directory work;
  late File scene;

  void record(String name, Stopwatch watch) {
    perf[name] = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print('DEVICE_PERF $name=${watch.elapsedMilliseconds}');
  }

  setUpAll(() async {
    final temp = await getTemporaryDirectory();
    work = await Directory('${temp.path}/memoria_device_features')
        .create(recursive: true);
    scene = File('${work.path}/sky_scene.jpg');
    await scene.writeAsBytes(img.encodeJpg(_skyScene(1600, 1200), quality: 92));
  });

  tearDownAll(() async {
    binding.reportData = <String, dynamic>{
      'suite': 'editor-features-device',
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'perfMs': perf,
    };
    if (await work.exists()) await work.delete(recursive: true);
  });

  /// 실제 시간이 흐르게 하면서 화면을 갱신한다(미리보기 isolate 완료 대기).
  Future<void> settle(WidgetTester tester, {int ms = 1500}) async {
    for (var waited = 0; waited < ms; waited += 100) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: scene.path)),
    );
    await settle(tester, ms: 3000);
  }

  Future<void> openTool(WidgetTester tester, String label) async {
    await tester.tap(find.text('도구'));
    await settle(tester, ms: 500);
    final grid = find.byKey(const ValueKey('editor-tools-grid'));
    final scrollable =
        find.descendant(of: grid, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text(label), 120,
        scrollable: scrollable);
    final gesture = find.ancestor(
      of: find.text(label),
      matching: find.byType(GestureDetector),
    );
    tester.widget<GestureDetector>(gesture.first).onTap!();
    await settle(tester, ms: 500);
  }

  testWidgets('DEV-01 하늘 도구: 안내와 슬라이더가 보이고 값을 바꿔도 오류 없이 렌더된다',
      (tester) async {
    await pumpEditor(tester);
    await openTool(tester, '하늘');
    expect(find.textContaining('붉게 표시된 부분'), findsOneWidget);

    final sliders = find.byType(Slider);
    expect(sliders, findsWidgets);
    tester.widget<Slider>(sliders.first).onChanged!(-40);
    await tester.pump();
    await settle(tester, ms: 3000);
    expect(find.textContaining('하늘로 인식한 영역에만'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DEV-02 지우개: 사진을 누르면 지운 곳이 기록된다', (tester) async {
    await pumpEditor(tester);
    await openTool(tester, '지우개');
    final image = find.byType(Image).first;
    await tester.tapAt(tester.getCenter(image));
    await settle(tester, ms: 3000);
    expect(find.textContaining('지운 곳 1개'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DEV-03 분할 비교를 켜고 끈다', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('보정 복사·분할 비교'));
    await settle(tester, ms: 500);
    await tester.tap(find.text('원본과 분할 비교'));
    await settle(tester, ms: 3000);
    expect(find.text('원본'), findsWidgets);
    expect(find.text('보정 후'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DEV-04 RAW: 합성 DNG를 플랫폼 현상 또는 미리보기로 연다', (tester) async {
    final dng = File('${work.path}/synthetic.dng');
    await dng.writeAsBytes(buildBayerDng(width: 1200, height: 800));

    final watch = Stopwatch()..start();
    RawImportResult? result;
    Object? error;
    await tester.runAsync(() async {
      try {
        result = await RawImport.prepare(dng.path, outputDirectory: work);
      } catch (e) {
        error = e;
      }
    });
    watch.stop();

    if (Platform.isIOS) {
      // iOS 15+ 는 Core Image가 현상해야 한다.
      expect(error, isNull);
      expect(result!.source, RawImportSource.developed);
      expect(result!.width, inInclusiveRange(1100, 1200));
      final developed =
          img.decodeJpg(await File(result!.path).readAsBytes())!;
      final skyPixel = developed.getPixel(developed.width ~/ 2, 40);
      final groundPixel =
          developed.getPixel(developed.width ~/ 2, developed.height - 40);
      expect(skyPixel.b, greaterThan(skyPixel.r), reason: '하늘은 파랗게');
      expect(groundPixel.g, greaterThan(groundPixel.b), reason: '땅은 초록');
      record('raw_develop_1200x800', watch);
    } else {
      // Android는 플랫폼 현상이 없고, 이 DNG에는 내장 미리보기가 없다.
      expect(error, isA<RawImportException>());
    }

    // 내장 미리보기만 있는 RAW는 모든 플랫폼에서 미리보기로 열린다.
    final preview = img.encodeJpg(_skyScene(640, 480), quality: 90);
    final fake = File('${work.path}/preview_only.dng');
    await fake.writeAsBytes(
        Uint8List.fromList([...List.filled(512, 7), ...preview, 0, 0]));
    RawImportResult? fallback;
    await tester.runAsync(() async {
      fallback = await RawImport.prepare(fake.path, outputDirectory: work);
    });
    expect(fallback!.source, RawImportSource.embeddedPreview);
    expect(fallback!.width, 640);
  });

  testWidgets('DEV-05 일괄 적용: 실제 내보내기 경로로 2장을 처리한다', (tester) async {
    final out = await Directory('${work.path}/batch_out').create();
    final temp = await Directory('${work.path}/batch_tmp').create();
    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      final f = File('${work.path}/batch_$i.jpg');
      await f.writeAsBytes(img.encodeJpg(_skyScene(4000, 3000), quality: 90));
      paths.add(f.path);
    }
    final service = BatchApplyService(
      coordinatorFactory: () => EditorMediaExportCoordinator(
        supportsWebp: () async => false,
        temporaryDirectory: () async => temp,
        saveToGallery: (path) async {
          await File(path).copy('${out.path}/${path.split('/').last}');
        },
      ),
    );

    final watch = Stopwatch()..start();
    late List<BatchItemResult> results;
    await tester.runAsync(() async {
      results = await service.run(
        paths: paths,
        look: const EditorLook(params: AdjustParams(exposure: 0.5)),
        preset: null,
        onItem: (_, __) {},
      );
    });
    watch.stop();
    record('batch_2x12mp', watch);

    expect(results.map((r) => r.status), everyElement(BatchItemStatus.done));
    expect(out.listSync().whereType<File>().length, 2);
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('DEV-06 12MP 엔진 처리 시간(기기 CPU)', (tester) async {
    final photo = _skyScene(4000, 3000);
    await tester.runAsync(() async {
      var watch = Stopwatch()..start();
      final mask = detectSky(photo);
      watch.stop();
      record('sky_detect_12mp', watch);
      expect(mask.isEmpty, isFalse);

      watch = Stopwatch()..start();
      applySkyAdjust(photo, const SkyAdjust(brightness: -20, warmth: -20),
          mask: mask);
      watch.stop();
      record('sky_apply_12mp', watch);

      watch = Stopwatch()..start();
      applyHealSpots(photo, const [HealSpot(x: 0.5, y: 0.7, radius: 0.02)]);
      watch.stop();
      record('heal_12mp', watch);
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// 위쪽 45%는 푸른 하늘과 구름, 아래는 질감 있는 땅, 땅에 검은 잡티 하나.
img.Image _skyScene(int w, int h) {
  final image = img.Image(width: w, height: h);
  final horizon = (h * 0.45).round();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (y < horizon) {
        image.setPixelRgb(x, y, 100 + y * 40 ~/ horizon,
            150 + y * 40 ~/ horizon, 235);
      } else {
        image.setPixelRgb(x, y, 60 + (x * 7 + y * 3) % 20,
            110 + (x * 3 + y * 5) % 25, 45);
      }
    }
  }
  final cloudTop = h ~/ 10;
  for (var y = cloudTop; y < cloudTop + h ~/ 12; y++) {
    for (var x = w ~/ 4; x < w ~/ 2; x++) {
      image.setPixelRgb(x, y, 245, 245, 248);
    }
  }
  final cx = w ~/ 2;
  final cy = (h * 0.7).round();
  final r = h ~/ 60;
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
        image.setPixelRgb(x, y, 10, 10, 10);
      }
    }
  }
  return image;
}
