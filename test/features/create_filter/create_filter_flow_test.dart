import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/repositories/filter_repository.dart';
import 'package:memoria/features/create_filter/create_filter_page.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;
  late File sourceImage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory =
        await Directory.systemTemp.createTemp('memoria-create-filter-flow-');
    sourceImage = File('${tempDirectory.path}/source.png');
    final image = img.Image(width: 32, height: 24);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 7, y * 9, 120);
      }
    }
    await sourceImage.writeAsBytes(img.encodePng(image));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required CreateFilterGenerator generator,
    required FilterRepository repository,
    required CreateFilterPreviewRenderer previewRenderer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateFilterPage(
          generator: generator,
          recentPhotoSource: _FixedRecentPhotoSource([sourceImage.path]),
          repository: repository,
          previewRenderer: previewRenderer,
          loadAdServices: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final recentImage = find.byKey(const ValueKey('recent-photo-0'));
    expect(recentImage, findsOneWidget);
    await tester.ensureVisible(recentImage);
    await tester.pump();
    await tester.tap(recentImage);
    await tester.pump();

    final nameField = find.byType(TextField);
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, '화이트박스 필터');
    await tester.pump();
  }

  Future<void> startGeneration(WidgetTester tester) async {
    final generate = find.text('필터 생성');
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pump();
  }

  testWidgets('CF-14 user cancel returns to idle without saving a preset',
      (tester) async {
    final generator = _PendingGenerator();
    final repository = _MemoryRepository();
    await pumpPage(
      tester,
      generator: generator,
      repository: repository,
      previewRenderer: const _NullPreviewRenderer(),
    );

    await startGeneration(tester);
    expect(find.text('취소'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(generator.cancelCount, 1);
    expect(repository.savedIds, isEmpty);
    expect(find.text('필터 생성을 취소했어요.'), findsOneWidget);
    expect(find.text('필터 생성'), findsOneWidget);
  });
}

class _FixedRecentPhotoSource implements RecentPhotoSource {
  final List<String> paths;

  const _FixedRecentPhotoSource(this.paths);

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async {
    final items = <RecentPhotoItem>[];
    for (final path in paths) {
      items.add(
        RecentPhotoItem(
          assetId: path,
          thumbnailBytes: File(path).readAsBytesSync(),
        ),
      );
    }
    return RecentPhotoPage(
      state: items.isEmpty
          ? RecentPhotoLoadState.empty
          : RecentPhotoLoadState.ready,
      items: items,
      page: page,
    );
  }

  @override
  Future<String?> resolveOriginalPath(String assetId) async => assetId;
}

class _PendingGenerator implements CreateFilterGenerator {
  Completer<Map<String, dynamic>>? _completer;
  int cancelCount = 0;

  @override
  Future<Map<String, dynamic>> generateStyle(
    List<String> styleImagePaths, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) {
    onProgress('style_analyze', 0.2);
    _completer = Completer<Map<String, dynamic>>();
    return _completer!.future;
  }

  @override
  Future<Map<String, dynamic>> generatePair(
    String beforePath,
    String afterPath, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> cancel() async {
    cancelCount++;
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const CreateFilterCancelledException());
    }
  }
}

class _NullPreviewRenderer implements CreateFilterPreviewRenderer {
  const _NullPreviewRenderer();

  @override
  Future<String?> render(FilterPreset preset, String? sourcePath) async => null;
}

class _MemoryRepository implements FilterRepository {
  final List<String> savedIds = [];

  @override
  Future<void> savePreset(FilterPreset preset) async {
    savedIds.add(preset.id);
  }

  @override
  Future<void> deletePreset(String id) async {
    savedIds.remove(id);
  }

  @override
  Future<List<FilterPreset>> getCustomPresets() async => const [];

  @override
  Future<FilterPreset?> getPresetById(String id) async => null;

  @override
  Future<void> updatePreset(FilterPreset preset) async {}
}
