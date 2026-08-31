import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/core/l10n/strings.dart';
import 'package:memoria/data/repositories/filter_repository_impl.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/repositories/filter_repository.dart';
import 'package:memoria/features/create_filter/create_filter_page.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';
import 'package:path_provider/path_provider.dart';

const _expectedCandidateSha =
    'a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6';
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
    'physical black-box blocks low coverage and creates with G5 candidate',
    (tester) async {
      expect(_isPhysicalDevice, isTrue,
          reason: 'This evidence must come from a physical device.');
      localeNotifier.value = const Locale('ko');

      final temp = await getTemporaryDirectory();
      final lowReference = File('${temp.path}/blackbox_low_coverage.png');
      final highReference = File('${temp.path}/blackbox_high_coverage.jpg');
      await lowReference.writeAsBytes(img.encodePng(_grayscaleFixture()));
      await _copyAsset('assets/images/summer_sapporo.jpg', highReference);

      final modelBytes = await rootBundle.load(
        'assets/models/direct_mvp_color_transfer_fp16.tflite',
      );
      final modelSha = sha256
          .convert(modelBytes.buffer.asUint8List(
            modelBytes.offsetInBytes,
            modelBytes.lengthInBytes,
          ))
          .toString();
      expect(modelSha, _expectedCandidateSha);

      final repository = _RecordingRepository(FilterRepositoryImpl());
      final rssBaseline = ProcessInfo.currentRss;
      final totalWatch = Stopwatch()..start();
      double? lowBlockMs;
      double? highCreateMs;

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: CreateFilterPage(
              recentPhotoSource: _FixtureRecentPhotoSource([
                lowReference,
                highReference,
              ]),
              repository: repository,
              loadAdServices: false,
            ),
          ),
        );
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey('recent-photo-1')),
          timeout: const Duration(seconds: 10),
        );

        await _selectRecent(tester, 0);
        await _enterName(tester, '실기기 저색상 차단');
        final lowWatch = Stopwatch()..start();
        await _tapGenerate(tester);
        await _pumpUntil(
          tester,
          find.text(S.get('create.low_coverage')),
          timeout: const Duration(seconds: 20),
        );
        lowWatch.stop();
        lowBlockMs = lowWatch.elapsedMicroseconds / 1000;

        expect(find.text(S.get('create.choose_another')), findsOneWidget);
        expect(repository.saved, isEmpty);
        expect(find.text(S.get('create.btn_save')), findsOneWidget);

        // Remove the blocked fixture, then select one normal color photograph.
        await _selectRecent(tester, 0);
        await _selectRecent(tester, 1);
        await _enterName(tester, '실기기 G5 블랙박스');
        final highWatch = Stopwatch()..start();
        await _tapGenerate(tester);
        await _pumpUntil(
          tester,
          find.textContaining(S.get('create.success')),
          timeout: const Duration(minutes: 2),
        );
        highWatch.stop();
        highCreateMs = highWatch.elapsedMicroseconds / 1000;

        expect(repository.saved, hasLength(1));
        final preset = repository.saved.single;
        expect(await File(preset.lutPath).exists(), isTrue);
        expect(await File(preset.thumbnailPath).exists(), isTrue);
        expect(preset.name.trim(), isNotEmpty);

        totalWatch.stop();
        final rssAfter = ProcessInfo.currentRss;
        final report = <String, Object>{
          'schemaVersion': 1,
          'scope': 'physical-device/create-filter-ui-black-box',
          'device': <String, String>{
            'name': _deviceName,
            'os': Platform.operatingSystem,
            'osVersion': Platform.operatingSystemVersion,
          },
          'candidate': <String, Object>{
            'sha256': modelSha,
            'coverageThreshold': 0.03,
          },
          'lowCoverage': <String, Object>{
            'blocked': true,
            'guidanceVisible': true,
            'chooseAnotherVisible': true,
            'savedPresetCount': 0,
            'elapsedMs': lowBlockMs,
          },
          'highCoverage': <String, Object>{
            'successSheetVisible': true,
            'savedPresetCount': 1,
            'lutExists': true,
            'previewExists': true,
            'savedName': preset.name,
            'elapsedMs': highCreateMs,
          },
          'rssBytes': <String, int>{
            'baseline': rssBaseline,
            'after': rssAfter,
            'delta': rssAfter - rssBaseline,
          },
          'totalElapsedMs': totalWatch.elapsedMicroseconds / 1000,
          'limitations': <String>[
            'The photo-source boundary is replaced with deterministic fixtures.',
            'The production page, coverage policy, model, worker, preview, and repository transaction are used.',
            'System photo-picker interaction and photo permissions are outside this test.',
          ],
        };
        binding.reportData = <String, Object>{
          'createFilterBlackBox': report,
        };
        // ignore: avoid_print
        print('CREATE_FILTER_BLACKBOX_RESULT=${jsonEncode(report)}');
      } finally {
        for (final preset in repository.saved.reversed) {
          await repository.deletePreset(preset.id);
        }
        if (await lowReference.exists()) await lowReference.delete();
        if (await highReference.exists()) await highReference.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

img.Image _grayscaleFixture() {
  final image = img.Image(width: 256, height: 256);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final value = ((x + y) / 2).round().clamp(0, 255);
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

Future<void> _copyAsset(String path, File destination) async {
  final data = await rootBundle.load(path);
  await destination.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

Future<void> _selectRecent(WidgetTester tester, int index) async {
  final finder = find.byKey(ValueKey('recent-photo-$index'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _enterName(WidgetTester tester, String name) async {
  final field = find.byType(TextField);
  expect(field, findsOneWidget);
  await tester.enterText(field, name);
  tester.testTextInput.hide();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapGenerate(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, S.get('create.btn_save'));
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump(const Duration(milliseconds: 100));
  final semanticsButton = find.semantics.byLabel(S.get('create.btn_save'));
  expect(semanticsButton, findsOneWidget);
  tester.semantics.tap(semanticsButton);
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

class _FixtureRecentPhotoSource implements RecentPhotoSource {
  final List<File> files;

  const _FixtureRecentPhotoSource(this.files);

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async {
    return RecentPhotoPage(
      state: RecentPhotoLoadState.ready,
      items: [
        for (final file in files)
          RecentPhotoItem(
            assetId: file.path,
            thumbnailBytes: await file.readAsBytes(),
          ),
      ],
      page: page,
    );
  }

  @override
  Future<String?> resolveOriginalPath(String assetId) async => assetId;
}

class _RecordingRepository implements FilterRepository {
  final FilterRepository delegate;
  final List<FilterPreset> saved = [];

  _RecordingRepository(this.delegate);

  @override
  Future<void> deletePreset(String id) => delegate.deletePreset(id);

  @override
  Future<List<FilterPreset>> getCustomPresets() =>
      delegate.getCustomPresets();

  @override
  Future<FilterPreset?> getPresetById(String id) =>
      delegate.getPresetById(id);

  @override
  Future<void> savePreset(FilterPreset preset) async {
    await delegate.savePreset(preset);
    saved.add(preset);
  }

  @override
  Future<void> updatePreset(FilterPreset preset) =>
      delegate.updatePreset(preset);
}
