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
    final image = img.Image(width: 48, height: 32);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 5, y * 7, 120);
      }
    }
    imageFile = File(
      '${Directory.systemTemp.path}/memoria_editor_usability_flow.png',
    )..writeAsBytesSync(img.encodePng(image));
  });

  tearDown(() {
    if (imageFile.existsSync()) imageFile.deleteSync();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: imageFile.path)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openToolsTab(WidgetTester tester) async {
    await tester.tap(find.text('도구'));
    await tester.pump();
  }

  Future<void> openTool(WidgetTester tester, String label) async {
    final grid = find.byKey(const ValueKey('editor-tools-grid'));
    final scrollable =
        find.descendant(of: grid, matching: find.byType(Scrollable));
    await tester.drag(grid, const Offset(0, 3000));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(label),
      120,
      scrollable: scrollable,
    );
    final gesture = find.ancestor(
      of: find.text(label),
      matching: find.byType(GestureDetector),
    );
    tester.widget<GestureDetector>(gesture.first).onTap!();
    await tester.pump();
  }

  testWidgets('보정 복사 메뉴에서 복사하면 붙여넣기가 켜진다', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('보정 복사·분할 비교'));
    await tester.pumpAndSettle();
    expect(find.text('보정 붙여넣기'), findsOneWidget);
    expect(find.text('먼저 보정을 복사하세요'), findsOneWidget);

    await tester.tap(find.text('보정 복사'));
    await tester.pumpAndSettle();
    expect(find.textContaining('보정을 복사했어요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byTooltip('보정 복사·분할 비교'));
    await tester.pumpAndSettle();
    expect(find.text('복사한 보정을 이 사진에 적용'), findsOneWidget);
  });

  testWidgets('분할 비교를 켜면 원본·보정 후 라벨이 보이고 끌 수 있다', (tester) async {
    await pumpEditor(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    await tester.tap(find.byTooltip('보정 복사·분할 비교'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('원본과 분할 비교'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
    }

    expect(find.text('보정 후'), findsOneWidget);

    await tester.tap(find.byTooltip('보정 복사·분할 비교'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('분할 비교 끄기'));
    await tester.pump();
    expect(find.text('보정 후'), findsNothing);
  });

  testWidgets('도구 탭에 지우개와 5개 묶음 제목이 보인다', (tester) async {
    await pumpEditor(tester);
    await openToolsTab(tester);

    for (final group in ['보정', '구성', '부분·인물', '효과', '합성']) {
      final grid = find.byKey(const ValueKey('editor-tools-grid'));
      final scrollable =
          find.descendant(of: grid, matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text(group), 120,
          scrollable: scrollable);
      expect(find.text(group), findsWidgets);
    }
    await openTool(tester, '지우개');
    expect(find.textContaining('지울 잡티나 작은 물체'), findsOneWidget);
  });

  testWidgets('부분 보정은 사진을 눌러 지점을 만들고 지점 수를 보여 준다', (tester) async {
    await pumpEditor(tester);
    await openToolsTab(tester);
    await openTool(tester, '부분 보정');

    expect(find.text('지점 0/8'), findsOneWidget);

    final area = tester.getRect(find.byType(Scaffold).first);
    await tester.tapAt(Offset(area.center.dx, area.top + 220));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('지점 1/8'), findsOneWidget);

    await tester.tapAt(Offset(area.center.dx - 90, area.top + 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('지점 2/8'), findsOneWidget);

    await tester.tap(find.text('이 지점 삭제'));
    await tester.pump();
    expect(find.text('지점 1/8'), findsOneWidget);
  });

  testWidgets('지우개로 사진을 누르면 지운 곳 수가 늘고 되돌릴 수 있다', (tester) async {
    await pumpEditor(tester);
    await openToolsTab(tester);
    await openTool(tester, '지우개');

    final area = tester.getRect(find.byType(Scaffold).first);
    await tester.tapAt(Offset(area.center.dx, area.top + 220));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('지운 곳 1개'), findsOneWidget);

    await tester.tap(find.text('마지막 지우기 취소'));
    await tester.pump();
    expect(find.textContaining('지울 잡티나 작은 물체'), findsOneWidget);
  });

  testWidgets('하늘 도구는 안내문과 3개 슬라이더를 보여 주고 값을 바꾸면 안내가 달라진다',
      (tester) async {
    await pumpEditor(tester);
    await openToolsTab(tester);
    await openTool(tester, '하늘');

    expect(find.textContaining('붉게 표시된 부분'), findsOneWidget);
    expect(find.text('밝기'), findsOneWidget);
    expect(find.text('채도'), findsOneWidget);
    expect(find.textContaining('색감'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('좁은 화면(320dp, 글자 ${scale}배)에서 도구 타일이 넘치지 않는다',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: EditorPage(imagePath: imageFile.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await openToolsTab(tester);

      final grid = find.byKey(const ValueKey('editor-tools-grid'));
      for (var i = 0; i < 12; i++) {
        await tester.drag(grid, const Offset(0, -120));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('도구 타일과 하단 탭이 화면 낭독기용 이름·상태를 가진다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpEditor(tester);

    expect(find.bySemanticsLabel('도구'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('도구')),
      matchesSemantics(
        label: '도구',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    await openToolsTab(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('도구')),
      matchesSemantics(
        label: '도구',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    final grid = find.byKey(const ValueKey('editor-tools-grid'));
    final scrollable =
        find.descendant(of: grid, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.bySemanticsLabel('하늘'), 120,
        scrollable: scrollable);
    expect(find.bySemanticsLabel('하늘'), findsOneWidget);
    semantics.dispose();
  });
}
