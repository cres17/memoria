import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/brush_toolbar.dart';

void main() {
  group('BrushToolbar Widget Tests', () {
    testWidgets('Renders all tool buttons, sliders, and stroke counter',
        (tester) async {
      String changedTool = '';
      double changedSize = 0.0;
      double changedHardness = -1.0;
      bool cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushToolbar(
              selectedTool: 'exposure+',
              brushSize: 80.0,
              hardness: 0.5,
              strokeCount: 4,
              onToolChanged: (t) => changedTool = t,
              onBrushSizeChanged: (s) => changedSize = s,
              onHardnessChanged: (h) => changedHardness = h,
              onClear: () => cleared = true,
            ),
          ),
        ),
      );

      // Verify that the stroke counter renders "4 strokes"
      expect(find.text('4 strokes'), findsOneWidget);

      // Verify that all 8 tools are present in the list (Dodge, Burn, Sat+, Sat-, Warm, Cool, Clarity, Eraser)
      // Since it's a horizontal ListView, they might be scrolled or off-screen, but we can verify the specs are rendered
      expect(find.byTooltip('Dodge'), findsOneWidget);
      expect(find.byTooltip('Burn'), findsOneWidget);
      expect(find.byTooltip('Sat+'), findsOneWidget);
      expect(find.byTooltip('Sat-'), findsOneWidget);
      expect(find.byTooltip('Warm'), findsOneWidget);
      expect(find.byTooltip('Cool'), findsOneWidget);
      expect(find.byTooltip('Clarity'), findsOneWidget);
      expect(find.byTooltip('Eraser'), findsOneWidget);

      // Tap on the Burn tool to verify onToolChanged works
      await tester.tap(find.byTooltip('Burn'));
      await tester.pumpAndSettle();
      expect(changedTool, equals('exposure-'));

      // Tap on the Eraser tool to verify onToolChanged works for eraser
      await tester.tap(find.byTooltip('Eraser'));
      await tester.pumpAndSettle();
      expect(changedTool, equals('eraser'));

      // Verify that sliders exist
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(2)); // Size and Hardness

      // Drag Size slider
      await tester.drag(sliders.at(0), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(changedSize, greaterThan(80.0));

      // Drag Hardness slider
      await tester.drag(sliders.at(1), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(changedHardness, lessThan(0.5));

      // Tap on clear/delete button
      final clearButton = find.byTooltip('Clear brush');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
    });
  });
}
