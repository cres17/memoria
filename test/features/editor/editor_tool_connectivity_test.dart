import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/features/editor/editor_page.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tool catalog has unique ids and a history classification', () {
    final ids = editorToolCatalog.map((tool) => tool.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(editorToolCatalog, isNotEmpty);
    for (final tool in editorToolCatalog) {
      expect(tool.id, isNotEmpty);
      expect(tool.label, isNotEmpty);
      expect(editorHistoryToolFor(tool.id), tool.historyTool);
    }
  });

  testWidgets('every catalog tool opens production controls and can cancel',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final image = img.Image(width: 32, height: 24);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 7, y * 9, 120);
      }
    }
    final fixture = File(
      '${Directory.systemTemp.path}/memoria-tool-connectivity.png',
    )..writeAsBytesSync(img.encodePng(image));
    addTearDown(() {
      if (fixture.existsSync()) fixture.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(home: EditorPage(imagePath: fixture.path)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('도구'));
    await tester.pump();

    for (final tool in editorToolCatalog) {
      final toolGrid = find.byType(GridView);
      expect(toolGrid, findsOneWidget, reason: 'tool grid missing: ${tool.id}');
      final scrollable = find.descendant(
        of: toolGrid,
        matching: find.byType(Scrollable),
      );
      final toolButton = find.byKey(ValueKey('editor-tool-${tool.id}'));
      await tester.scrollUntilVisible(
        toolButton,
        160,
        scrollable: scrollable,
      );
      final gesture = find.ancestor(
        of: toolButton,
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(gesture.first).onTap!();
      await tester.pump();

      expect(
        find.byTooltip('적용'),
        findsOneWidget,
        reason: 'apply action is disconnected: ${tool.id}',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.refresh_rounded),
        findsOneWidget,
        reason: 'reset action is disconnected: ${tool.id}',
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byTooltip('적용'), findsNothing);
    }
  });
}
