import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/features/editor/widgets/hsl_panel.dart';
import 'package:memoria/features/editor/widgets/noise_panel.dart';
import 'package:memoria/features/editor/widgets/details_panel.dart';


void main() {
  testWidgets('HslPanel separates preview changes from final commit',
      (tester) async {
    final changed = <AdjustParams>[];
    final ended = <AdjustParams>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HslPanel(
            params: AdjustParams.zero,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty);
    expect(ended, hasLength(1));
    expect(ended.single.hsl[HslBand.red]!.hue,
        closeTo(changed.last.hsl[HslBand.red]!.hue, 0.001));
  });

  testWidgets('NoisePanel separates preview changes from final commit',
      (tester) async {
    final changed = <AdjustParams>[];
    final ended = <AdjustParams>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoisePanel(
            params: AdjustParams.zero,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty);
    expect(ended, hasLength(1));
    expect(ended.single.luminanceNR, closeTo(changed.last.luminanceNR, 0.001));
  });

  testWidgets('DetailsPanel separates preview changes from final commit',
      (tester) async {
    final changed = <AdjustParams>[];
    final ended = <AdjustParams>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailsPanel(
            params: AdjustParams.zero,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    );

    // Drag the first slider (Structure)
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty);
    expect(ended, hasLength(1));
    expect(ended.single.structure, closeTo(changed.last.structure, 0.001));
  });
}
