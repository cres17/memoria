import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/rotate_flip_panel.dart';

void main() {
  group('RotateFlipPanel Widget Tests', () {
    testWidgets('Renders all controls and slider', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RotateFlipPanel(
              rotation: 5.0,
              flipH: false,
              flipV: true,
              onRotationChanged: (_) {},
              onRotationEnd: (_) {},
              onFlipH: () {},
              onFlipV: () {},
              onRotate90: () {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Verify buttons exist
      expect(find.byKey(const Key('rotate_fine_dec')), findsOneWidget);
      expect(find.byKey(const Key('rotate_fine_inc')), findsOneWidget);
      expect(find.byKey(const Key('rotate_fine_slider')), findsOneWidget);
      expect(find.byKey(const Key('rotate_fine_reset_text')), findsOneWidget);
      expect(find.byKey(const Key('rotate_90_btn')), findsOneWidget);
      expect(find.byKey(const Key('rotate_flip_h_btn')), findsOneWidget);
      expect(find.byKey(const Key('rotate_flip_v_btn')), findsOneWidget);
      expect(find.byKey(const Key('rotate_reset_all_btn')), findsOneWidget);

      // Verify angle display is correct
      expect(find.text('5°'), findsOneWidget);
    });

    testWidgets('Tapping flip H, flip V, and rotate 90 triggers callbacks',
        (WidgetTester tester) async {
      bool flipHTapped = false;
      bool flipVTapped = false;
      bool rotate90Tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RotateFlipPanel(
              rotation: 0.0,
              flipH: false,
              flipV: false,
              onRotationChanged: (_) {},
              onRotationEnd: (_) {},
              onFlipH: () => flipHTapped = true,
              onFlipV: () => flipVTapped = true,
              onRotate90: () => rotate90Tapped = true,
              onReset: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('rotate_flip_h_btn')));
      await tester.pump();
      expect(flipHTapped, isTrue);

      await tester.tap(find.byKey(const Key('rotate_flip_v_btn')));
      await tester.pump();
      expect(flipVTapped, isTrue);

      await tester.tap(find.byKey(const Key('rotate_90_btn')));
      await tester.pump();
      expect(rotate90Tapped, isTrue);
    });

    testWidgets('Slider drag triggers onRotationChanged',
        (WidgetTester tester) async {
      double changedRotation = 0.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RotateFlipPanel(
              rotation: 0.0,
              flipH: false,
              flipV: false,
              onRotationChanged: (v) => changedRotation = v,
              onRotationEnd: (_) {},
              onFlipH: () {},
              onFlipV: () {},
              onRotate90: () {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Drag the slider
      await tester.drag(
          find.byKey(const Key('rotate_fine_slider')), const Offset(50, 0));
      await tester.pump();

      expect(changedRotation, isNot(0.0));
      // End drag is handled by gesture ending
    });

    testWidgets('Tapping inc/dec/reset text adjustments work',
        (WidgetTester tester) async {
      double updatedRotation = 0.0;
      bool resetTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RotateFlipPanel(
              rotation: 10.0,
              flipH: false,
              flipV: false,
              onRotationChanged: (v) => updatedRotation = v,
              onRotationEnd: (v) => updatedRotation = v,
              onFlipH: () {},
              onFlipV: () {},
              onRotate90: () {},
              onReset: () => resetTapped = true,
            ),
          ),
        ),
      );

      // Dec by 1 degree (from 10 to 9)
      await tester.tap(find.byKey(const Key('rotate_fine_dec')));
      await tester.pump();
      expect(updatedRotation, 9.0);

      // Inc by 1 degree (from 10 to 11)
      await tester.tap(find.byKey(const Key('rotate_fine_inc')));
      await tester.pump();
      expect(updatedRotation, 11.0);

      // Tap Reset text
      await tester.tap(find.byKey(const Key('rotate_fine_reset_text')));
      await tester.pump();
      expect(updatedRotation, 0.0);

      // Tap Reset all button
      await tester.tap(find.byKey(const Key('rotate_reset_all_btn')));
      await tester.pump();
      expect(resetTapped, isTrue);
    });
  });
}
