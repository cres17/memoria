import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/core/l10n/strings.dart';
import 'package:memoria/features/create_filter/create_filter_page.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';
import 'package:memoria/features/editor/editor_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    localeNotifier.value = const Locale('ko');
  });

  Future<void> useCompactLargeTextViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget largeTextApp(Widget home) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: home,
      );

  testWidgets('editor empty state remains usable at 200% text scale',
      (tester) async {
    await useCompactLargeTextViewport(tester);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(largeTextApp(const EditorPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final backNode = tester.getSemantics(
      find.bySemanticsLabel(S.get('editor.go_back')),
    );
    final selectNode = tester.getSemantics(
      find.widgetWithText(FilledButton, S.get('editor.select_photo')),
    );
    expect(backNode.label, contains(S.get('editor.go_back')));
    expect(selectNode.label, contains(S.get('editor.select_photo')));
    semantics.dispose();
  });

  testWidgets('create-filter modes expose button and selected semantics',
      (tester) async {
    await useCompactLargeTextViewport(tester);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      largeTextApp(
        const CreateFilterPage(
          recentPhotoSource: _EmptyRecentPhotoSource(),
          loadAdServices: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final styleNode =
        tester.getSemantics(find.bySemanticsLabel(S.get('create.mode_style')));
    final pairNode =
        tester.getSemantics(find.bySemanticsLabel(S.get('create.mode_pair')));
    expect(styleNode.flagsCollection.isButton, isTrue);
    expect(styleNode.flagsCollection.isSelected, Tristate.isTrue);
    expect(pairNode.flagsCollection.isButton, isTrue);
    expect(pairNode.flagsCollection.isSelected, Tristate.isFalse);
    final backNode = tester.getSemantics(
      find.bySemanticsLabel(S.get('editor.go_back')),
    );
    expect(backNode.label, contains(S.get('editor.go_back')));
    semantics.dispose();
  });
}

class _EmptyRecentPhotoSource implements RecentPhotoSource {
  const _EmptyRecentPhotoSource();

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async =>
      RecentPhotoPage(
        state: RecentPhotoLoadState.empty,
        items: const [],
        page: page,
      );

  @override
  Future<String?> resolveOriginalPath(String assetId) async => null;
}
