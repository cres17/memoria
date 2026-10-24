import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/adjust_slider.dart';

void main() {
  testWidgets('라벨 줄을 두 번 탭하면 초기값으로 돌아간다', (tester) async {
    var value = 40.0;
    var ended = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AdjustSlider(
              item: AdjustSliderItem(
                label: '노출',
                icon: Icons.light_mode,
                value: value,
                min: -100,
                max: 100,
                onChanged: (v) => setState(() => value = v),
                onChangeEnd: (_) => ended = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('노출'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('노출'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));
    expect(value, 0);
    expect(ended, isTrue);
  });

  testWidgets('neutral을 지정하면 그 값으로 돌아간다', (tester) async {
    var value = 5.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AdjustSlider(
              item: AdjustSliderItem(
                label: '크기',
                icon: Icons.grain,
                value: value,
                min: 0.5,
                max: 10,
                neutral: 1,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('크기'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('크기'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));
    expect(value, 1);
  });
}
