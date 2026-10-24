import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/features/editor/editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 손상되었거나 알 수 없는 초안이 저장되어 있어도 편집 화면이 정상적으로 열려야 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File imageFile;

  String draftKey(String path) =>
      'editor.draft.${base64Url.encode(utf8.encode(path))}';

  setUp(() {
    final image = img.Image(width: 48, height: 32);
    for (final p in image) {
      p.setRgb(120, 130, 140);
    }
    imageFile = File('${Directory.systemTemp.path}/memoria_draft_corruption.png')
      ..writeAsBytesSync(img.encodePng(image));
  });

  tearDown(() {
    if (imageFile.existsSync()) imageFile.deleteSync();
  });

  Future<void> openWithDraft(WidgetTester tester, Object draft) async {
    SharedPreferences.setMockInitialValues({
      draftKey(imageFile.path): draft is String ? draft : jsonEncode(draft),
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: imageFile.path)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('JSON이 아닌 초안은 무시하고 편집 화면을 연다', (tester) async {
    await openWithDraft(tester, '{not json');
    expect(tester.takeException(), isNull);
    expect(find.text('도구'), findsOneWidget);
  });

  testWidgets('값 타입이 깨진 초안은 무시하고 편집 화면을 연다', (tester) async {
    await openWithDraft(tester, {
      'imagePath': imageFile.path,
      'initialPresetId': null,
      'snapshot': {
        'effects': {'skyBrightness': 'bright', 'selectiveExtras': 5},
        'adjust': 'oops',
      },
    });
    expect(tester.takeException(), isNull);
    expect(find.text('도구'), findsOneWidget);
  });

  testWidgets('다른 사진의 초안(경로 불일치)은 적용하지 않는다', (tester) async {
    await openWithDraft(tester, {
      'imagePath': '/some/other/photo.jpg',
      'initialPresetId': null,
      'snapshot': <String, dynamic>{},
    });
    expect(tester.takeException(), isNull);
    expect(find.text('도구'), findsOneWidget);
  });
}
