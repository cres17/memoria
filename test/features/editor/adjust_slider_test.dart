import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/adjust_slider.dart';
import 'package:memoria/features/editor/widgets/filter_strip.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('AdjustSlider reports preview changes and final commit',
      (tester) async {
    final changed = <double>[];
    final ended = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdjustSlider(
            item: AdjustSliderItem(
              label: 'Exposure',
              icon: Icons.wb_sunny_outlined,
              accent: Colors.orange,
              value: 0,
              min: -2,
              max: 2,
              onChanged: changed.add,
              onChangeEnd: ended.add,
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty);
    expect(ended, hasLength(1));
    expect(ended.single, closeTo(changed.last, 0.001));
  });

  testWidgets('IntensitySlider reports final commit separately',
      (tester) async {
    final changed = <double>[];
    final ended = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntensitySlider(
            value: 0.5,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty);
    expect(ended, hasLength(1));
    expect(ended.single, closeTo(changed.last, 0.001));
  });

  test('filter thumbnails use a fixed tonal sample', () {
    final sample = fixedFilterSampleForTest();

    expect(sample.width, 72);
    expect(sample.height, 72);

    final solidCurrentPhoto = img.Image(width: 72, height: 72);
    img.fill(solidCurrentPhoto, color: img.ColorRgb8(255, 0, 0));

    var differsFromSolidPhoto = false;
    for (var y = 0; y < sample.height && !differsFromSolidPhoto; y++) {
      for (var x = 0; x < sample.width; x++) {
        final p = sample.getPixel(x, y);
        if (p.r != 255 || p.g != 0 || p.b != 0) {
          differsFromSolidPhoto = true;
          break;
        }
      }
    }

    expect(differsFromSolidPhoto, isTrue);
  });
}
