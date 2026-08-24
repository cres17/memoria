import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/repositories/filter_repository.dart';
import 'package:memoria/features/create_filter/create_filter_page.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late List<String> imagePaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory =
        await Directory.systemTemp.createTemp('memoria-recent-photos-');
    imagePaths = [];
    for (var index = 0; index < 3; index++) {
      final image = img.Image(width: 24, height: 24);
      img.fill(image, color: img.ColorRgb8(30 + index * 40, 80, 120));
      final file = File('${tempDirectory.path}/photo_$index.png');
      await file.writeAsBytes(img.encodePng(image));
      imagePaths.add(file.path);
    }
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> pumpPage(
    WidgetTester tester,
    RecentPhotoSource source,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko'), Locale('en')],
        home: CreateFilterPage(
          generator: const _UnusedGenerator(),
          recentPhotoSource: source,
          repository: _UnusedRepository(),
          previewRenderer: const _UnusedPreviewRenderer(),
          loadAdServices: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('CF-01 denied permission exposes an explicit fallback action',
      (tester) async {
    await pumpPage(
      tester,
      _SequenceRecentPhotoSource(const [
        RecentPhotoPage(state: RecentPhotoLoadState.denied),
      ]),
    );

    expect(find.text('최근 사진을 보려면 사진 접근 권한이 필요해요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-photo-state-action')),
        findsOneWidget);
    expect(find.text('사진 선택'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-filter-glass-header')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('create-filter-glass-mode-toggle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('create-filter-glass-controls')),
        findsOneWidget);
    expect(find.byType(BackdropFilter), findsAtLeastNWidgets(3));
    expect(find.text('무드 스타일'), findsOneWidget);
    expect(find.text('사진에서 색감 추출'), findsOneWidget);
    expect(find.text('보정 레시피'), findsOneWidget);
    expect(find.text('전·후 차이를 그대로'), findsOneWidget);
  });

  testWidgets('CF-01 error state retries and recovers the recent strip',
      (tester) async {
    final source = _SequenceRecentPhotoSource([
      const RecentPhotoPage(state: RecentPhotoLoadState.error),
      RecentPhotoPage(
        state: RecentPhotoLoadState.ready,
        items: _items([imagePaths.first]),
      ),
    ]);
    await pumpPage(tester, source);

    expect(find.text('최근 사진을 불러오지 못했어요.'), findsOneWidget);
    final retry = find.byKey(const ValueKey('recent-photo-state-action'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(source.calls, 2);
    expect(find.byKey(const ValueKey('recent-photo-0')), findsOneWidget);
  });

  testWidgets('CF-01 limited access is visible and selection order is stable',
      (tester) async {
    await pumpPage(
      tester,
      _SequenceRecentPhotoSource([
        RecentPhotoPage(
          state: RecentPhotoLoadState.limited,
          items: _items(imagePaths.take(2)),
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('recent-photo-limited-label')),
        findsOneWidget);
    final firstPhoto = find.byKey(const ValueKey('recent-photo-0'));
    await tester.ensureVisible(firstPhoto);
    await tester.pump();
    await tester.tap(firstPhoto);
    await tester.pump();
    final secondPhoto = find.byKey(const ValueKey('recent-photo-1'));
    await tester.tap(secondPhoto);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('recent-photo-selection-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('recent-photo-selection-2')), findsOneWidget);
  });

  testWidgets('CF-02 load more appends the next page without duplicates',
      (tester) async {
    final source = _PagedRecentPhotoSource(imagePaths);
    await pumpPage(tester, source);

    final loadMore = find.byKey(const ValueKey('recent-photo-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(source.requestedPages, [0, 1]);
    expect(find.byKey(const ValueKey('recent-photo-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-photo-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-photo-load-more')), findsNothing);
  });

  testWidgets('CF-03 unavailable original is reported and not selected',
      (tester) async {
    final source = _SequenceRecentPhotoSource(
      [
        RecentPhotoPage(
          state: RecentPhotoLoadState.ready,
          items: _items([imagePaths.first]),
        ),
      ],
      resolveOriginal: false,
    );
    await pumpPage(tester, source);

    final photo = find.byKey(const ValueKey('recent-photo-0'));
    await tester.ensureVisible(photo);
    await tester.tap(photo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('iCloud 다운로드 상태'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('recent-photo-selection-1')), findsNothing);
  });

  testWidgets('CF-05 Before and After slots select and clear independently',
      (tester) async {
    await pumpPage(
      tester,
      _SequenceRecentPhotoSource([
        RecentPhotoPage(
          state: RecentPhotoLoadState.ready,
          items: _items(imagePaths.take(2)),
        ),
      ]),
    );

    await tester.tap(find.text('보정 레시피'));
    await tester.pump();
    expect(find.text('선택'), findsOneWidget);
    expect(find.text('BEFORE · 원본'), findsOneWidget);
    expect(find.text('AFTER · 보정본'), findsOneWidget);
    final firstPhoto = find.byKey(const ValueKey('recent-photo-0'));
    await tester.ensureVisible(firstPhoto);
    await tester.tap(firstPhoto);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('recent-photo-selection-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('recent-photo-selection-2')), findsOneWidget);

    final beforeSlot = find.byKey(const ValueKey('pair-slot-before'));
    final clearBefore = find.descendant(
      of: beforeSlot,
      matching: find.byType(IconButton),
    );
    expect(clearBefore, findsOneWidget);
    await tester.tap(clearBefore);
    await tester.pump();

    expect(
      find.descendant(of: beforeSlot, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
        find.byKey(const ValueKey('recent-photo-selection-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('recent-photo-selection-2')), findsNothing);
  });
}

List<RecentPhotoItem> _items(Iterable<String> paths) => paths
    .map(
      (path) => RecentPhotoItem(
        assetId: path,
        thumbnailBytes: File(path).readAsBytesSync(),
      ),
    )
    .toList(growable: false);

class _SequenceRecentPhotoSource implements RecentPhotoSource {
  final List<RecentPhotoPage> results;
  final bool resolveOriginal;
  int calls = 0;

  _SequenceRecentPhotoSource(this.results, {this.resolveOriginal = true});

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async {
    final index = calls.clamp(0, results.length - 1);
    calls++;
    return results[index];
  }

  @override
  Future<String?> resolveOriginalPath(String assetId) async =>
      resolveOriginal ? assetId : null;
}

class _PagedRecentPhotoSource implements RecentPhotoSource {
  final List<String> paths;
  final List<int> requestedPages = [];

  _PagedRecentPhotoSource(this.paths);

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async {
    requestedPages.add(page);
    if (page == 0) {
      return RecentPhotoPage(
        state: RecentPhotoLoadState.ready,
        items: _items([paths[0]]),
        page: 0,
        hasMore: true,
      );
    }
    return RecentPhotoPage(
      state: RecentPhotoLoadState.ready,
      items: _items([paths[0], paths[1]]),
      page: 1,
    );
  }

  @override
  Future<String?> resolveOriginalPath(String assetId) async => assetId;
}

class _UnusedGenerator implements CreateFilterGenerator {
  const _UnusedGenerator();

  @override
  Future<void> cancel() async {}

  @override
  Future<Map<String, dynamic>> generatePair(
    String beforePath,
    String afterPath, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> generateStyle(
    List<String> styleImagePaths, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) =>
      throw UnimplementedError();
}

class _UnusedPreviewRenderer implements CreateFilterPreviewRenderer {
  const _UnusedPreviewRenderer();

  @override
  Future<String?> render(FilterPreset preset, String? sourcePath) =>
      throw UnimplementedError();
}

class _UnusedRepository implements FilterRepository {
  @override
  Future<void> deletePreset(String id) async {}

  @override
  Future<List<FilterPreset>> getCustomPresets() async => const [];

  @override
  Future<FilterPreset?> getPresetById(String id) async => null;

  @override
  Future<void> savePreset(FilterPreset preset) async {}

  @override
  Future<void> updatePreset(FilterPreset preset) async {}
}
