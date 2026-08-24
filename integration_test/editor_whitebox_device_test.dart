import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/features/editor/editor_page.dart';
import 'package:path_provider/path_provider.dart';

/// Device-level contract tests for the editor's highest-risk state changes.
///
/// These deliberately use a real image file and the production [EditorPage]
/// rather than a mocked engine.  They are still safe to run on a personal
/// phone: the fixture is created in the app temporary directory and no photo
/// library write or share completion is performed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final completed = <String>[];

  late File fixture;

  setUpAll(() async {
    final image = img.Image(width: 640, height: 480);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, (x * 2) % 256, (y * 2) % 256, (x + y) % 256);
      }
    }
    final directory = await getTemporaryDirectory();
    fixture = File('${directory.path}/editor_whitebox_fixture.jpg');
    await fixture.writeAsBytes(img.encodeJpg(image, quality: 92));
  });

  tearDownAll(() async {
    if (await fixture.exists()) await fixture.delete();
    binding.reportData = <String, dynamic>{
      'schemaVersion': 1,
      'suite': 'editor-whitebox-device',
      'device': <String, String>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      },
      'fixture': <String, dynamic>{
        'id': 'synthetic-gradient-640x480',
        'width': 640,
        'height': 480,
        'photoLibraryWrite': false,
      },
      'passed': completed,
    };
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: fixture.path)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  testWidgets('WB-ED-02/06: reset is neutral and apply closes the transaction',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('기본 보정').first);
    await tester.pump();
    expect(find.byTooltip('적용'), findsOneWidget);
    expect(find.byTooltip('초기화'), findsOneWidget);

    final exposure = find.byType(Slider).first;
    final initial = tester.widget<Slider>(exposure);
    expect(initial.value, 0);
    initial.onChanged!(initial.max);
    await tester.pump();
    expect(tester.widget<Slider>(exposure).value, initial.max);

    await tester.tap(find.byTooltip('초기화'));
    await tester.pump();
    expect(tester.widget<Slider>(exposure).value, 0);

    await tester.tap(find.byTooltip('적용'));
    await tester.pump();
    expect(find.byTooltip('적용'), findsNothing);
    completed.add('WB-ED-02');
    completed.add('WB-ED-06');
  });

  testWidgets('WB-ED-01: first back cancels a tool before exit confirmation',
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
    await tester.tap(find.text('계속 편집'));
    await tester.pump();
    completed.add('WB-ED-01');
  });

  testWidgets('WB-CR-01: crop ratio is selectable and reset returns to free',
      (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('크롭').first);
    await tester.pump();
    expect(find.text('자유'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);

    await tester.tap(find.text('1:1'));
    await tester.pump();
    await tester.tap(find.byTooltip('초기화'));
    await tester.pump();
    expect(find.text('자유'), findsOneWidget);
    completed.add('WB-CR-01');
  });
}
