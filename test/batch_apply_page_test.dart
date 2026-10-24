import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/features/batch/batch_apply_page.dart';
import 'package:memoria/features/editor/editor_look_clipboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditorLookClipboard.value = null;
  });

  testWidgets('복사한 보정이 없으면 안내를 보여 주고 시작 버튼이 꺼져 있다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BatchApplyPage()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('편집 화면에서 보정을 복사하거나'), findsOneWidget);
    final start = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(start.onPressed, isNull);
  });

  testWidgets('복사한 보정과 사진을 고르면 시작할 수 있다', (tester) async {
    EditorLookClipboard.value =
        const EditorLook(params: AdjustParams(exposure: 0.5));
    await tester.pumpWidget(MaterialApp(
      home: BatchApplyPage(
        pickPhotos: () async => ['/tmp/a.jpg', '/tmp/b.jpg'],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('방금 복사한 보정'), findsOneWidget);
    await tester.tap(find.textContaining('사진 여러 장 고르기'));
    await tester.pump();

    expect(find.textContaining('2장 선택됨'), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    final start = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(start.onPressed, isNotNull);
  });
}
