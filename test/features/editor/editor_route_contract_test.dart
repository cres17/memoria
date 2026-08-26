import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/features/editor/editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File imageFile;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final image = img.Image(width: 24, height: 16);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 10, y * 12, 120);
      }
    }
    imageFile = File(
      '${Directory.systemTemp.path}/memoria_editor_route_contract.png',
    )..writeAsBytesSync(img.encodePng(image));
  });

  tearDown(() {
    if (imageFile.existsSync()) imageFile.deleteSync();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: imageFile.path)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('active tool exposes top apply and bottom reset actions',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();

    expect(find.byTooltip('적용'), findsOneWidget);
    expect(find.byTooltip('초기화'), findsOneWidget);
    expect(find.text('기본 보정'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('적용'));
    await tester.pump();
    expect(find.byTooltip('적용'), findsNothing);
    expect(find.byTooltip('초기화'), findsNothing);
  });

  testWidgets('system back cancels an active tool before asking to leave',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();
    expect(find.byTooltip('적용'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byTooltip('적용'), findsNothing);
    expect(find.text('편집을 취소할까요?'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('편집을 취소할까요?'), findsOneWidget);
    expect(find.text('계속 편집'), findsOneWidget);
    expect(find.text('편집 취소'), findsOneWidget);
    expect(find.textContaining('저장되지 않고 사라집니다'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('편집을 취소할까요?'),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reset restores the active adjustment to its neutral value',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();

    final exposure = find.byType(Slider).first;
    final initialSlider = tester.widget<Slider>(exposure);
    expect(initialSlider.value, 0);

    initialSlider.onChanged!(initialSlider.max);
    await tester.pump();
    expect(tester.widget<Slider>(exposure).value, initialSlider.max);

    await tester.tap(find.byTooltip('초기화'));
    await tester.pump();
    expect(tester.widget<Slider>(exposure).value, 0);
  });

  testWidgets('lens blur state follows production apply, undo, and redo path',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();
    final exposure = find.byType(Slider).first;
    final exposureWidget = tester.widget<Slider>(exposure);
    exposureWidget.onChanged!(exposureWidget.max);
    await tester.pump();
    await tester.tap(find.byTooltip('적용'));
    await tester.pump();

    await tester.tap(find.text('도구'));
    await tester.pump();
    final toolsGrid = find.byType(GridView);
    final toolsScrollable = find.descendant(
      of: toolsGrid,
      matching: find.byType(Scrollable),
    );
    final lensTool = find.text('원형 초점 흐림');
    await tester.scrollUntilVisible(
      lensTool,
      180,
      scrollable: toolsScrollable,
    );
    final lensGesture = find.ancestor(
      of: lensTool,
      matching: find.byType(GestureDetector),
    );
    final openLens = tester.widget<GestureDetector>(lensGesture.first).onTap!;
    openLens();
    await tester.pump();
    final lensRadius = find.byType(Slider).at(1);
    tester.widget<Slider>(lensRadius).onChanged!(14);
    await tester.pump();
    expect(tester.widget<Slider>(lensRadius).value, 14);
    await tester.tap(find.byTooltip('적용'));
    await tester.pump(const Duration(milliseconds: 700));

    final preferences = await SharedPreferences.getInstance();
    final draftKey = preferences
        .getKeys()
        .singleWhere((key) => key.startsWith('editor.draft.'));
    final draft =
        jsonDecode(preferences.getString(draftKey)!) as Map<String, dynamic>;
    expect(draft['version'], 3);
    final snapshot = draft['snapshot'] as Map<String, dynamic>;
    final effects = snapshot['effects'] as Map<String, dynamic>;
    expect(effects['lensActive'], isTrue);
    expect(effects['lensMaxRadius'], 14);
    expect(effects['brushStrokes'], isA<List<dynamic>>());
    final persistedSession = draft['editSession'] as Map<String, dynamic>;
    final persistedOps = persistedSession['ops'] as List<dynamic>;
    expect(persistedOps, hasLength(2));
    expect(
      (persistedOps.last as Map<String, dynamic>)['effects'],
      isA<Map<String, dynamic>>(),
    );

    await tester.tap(find.byTooltip('실행 취소'));
    await tester.pump();
    openLens();
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider).at(1)).value, 8);
    await tester.binding.handlePopRoute();
    await tester.pump();

    await tester.tap(find.byTooltip('다시 실행'));
    await tester.pump();
    openLens();
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider).at(1)).value, 14);
  });
}
