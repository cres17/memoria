import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/focus_overlay_widget.dart';

void main() {
  testWidgets('one-finger scale recognizer moves the focus without asserting',
      (tester) async {
    var center = 0.5;
    var ended = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: FocusOverlayWidget(
              imageSize: const Size(200, 200),
              focusCenter: center,
              bandWidth: 0.2,
              onFocusCenterChanged: (value) => center = value,
              onDragEnd: () => ended = true,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(FocusOverlayWidget), const Offset(0, 40));
    await tester.pump();

    expect(center, greaterThan(0.5));
    expect(ended, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch width is based on the gesture start value',
      (tester) async {
    var width = 0.2;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: FocusOverlayWidget(
              imageSize: const Size(200, 200),
              focusCenter: 0.5,
              bandWidth: width,
              onBandWidthChanged: (value) => width = value,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(FocusOverlayWidget));
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(center + const Offset(-20, 0));
    await second.down(center + const Offset(20, 0));
    await tester.pump();
    await first.moveTo(center + const Offset(-40, 0));
    await second.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await first.up();
    await second.up();

    expect(width, greaterThan(0.2));
    expect(width, lessThanOrEqualTo(0.41));
    expect(tester.takeException(), isNull);
  });
}
