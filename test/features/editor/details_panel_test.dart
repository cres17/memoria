import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/features/editor/widgets/details_panel.dart';

void main() {
  testWidgets('DetailsPanel renders structure, clarity, sharpen sliders',
      (tester) async {
    final changedParams = <AdjustParams>[];
    final endedParams = <AdjustParams>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailsPanel(
            params: const AdjustParams(structure: 10, clarity: 20, sharpen: 30),
            onChanged: changedParams.add,
            onChangeEnd: endedParams.add,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.grid_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.details_outlined), findsOneWidget);
    expect(find.byIcon(Icons.filter_center_focus_outlined), findsOneWidget);

    // Verify sliders exist
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(3));

    // Drag the first slider (structure)
    await tester.drag(sliders.at(0), const Offset(50, 0));
    await tester.pumpAndSettle();

    expect(changedParams, isNotEmpty);
    expect(endedParams, hasLength(1));
    expect(endedParams.first.structure, greaterThan(10.0));

    // Reset via double tap on structure row
    // The Row is inside a GestureDetector at _DetailsSlider level
    final structureRowGesture = find.byType(GestureDetector).at(0);
    await tester.tap(structureRowGesture);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(structureRowGesture);
    await tester.pumpAndSettle();

    expect(endedParams.last.structure, equals(0.0));
  });
}
