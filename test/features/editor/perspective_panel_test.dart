import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/widgets/perspective_panel.dart';

void main() {
  group('PerspectivePanel Widget Tests', () {
    testWidgets('Renders controls, labels, and sliders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PerspectivePanel(
              perspH: 0.0,
              perspV: 5.0,
              onPerspHChanged: (_) {},
              onPerspHEnd: (_) {},
              onPerspVChanged: (_) {},
              onPerspVEnd: (_) {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Verify that labels and elements exist
      expect(find.text('수평'), findsOneWidget);
      expect(find.text('수직'), findsOneWidget);

      expect(find.byKey(const Key('persp_h_slider')), findsOneWidget);
      expect(find.byKey(const Key('persp_v_slider')), findsOneWidget);
      
      expect(find.byKey(const Key('persp_h_dec')), findsOneWidget);
      expect(find.byKey(const Key('persp_h_inc')), findsOneWidget);
      expect(find.byKey(const Key('persp_v_dec')), findsOneWidget);
      expect(find.byKey(const Key('persp_v_inc')), findsOneWidget);

      expect(find.byKey(const Key('persp_h_reset_text')), findsOneWidget);
      expect(find.byKey(const Key('persp_v_reset_text')), findsOneWidget);

      // Zero value should show 0°
      expect(find.text('0°'), findsOneWidget);
      // Non-zero value (5.0) should show 5°
      expect(find.text('5°'), findsOneWidget);

      // Since perspV != 0, reset all button should be visible
      expect(find.byKey(const Key('persp_reset_all_btn')), findsOneWidget);
    });

    testWidgets('Tapping inc/dec on horizontal perspective triggers callbacks', (WidgetTester tester) async {
      double changedVal = -999.0;
      double endedVal = -999.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PerspectivePanel(
              perspH: 10.0,
              perspV: 0.0,
              onPerspHChanged: (v) => changedVal = v,
              onPerspHEnd: (v) => endedVal = v,
              onPerspVChanged: (_) {},
              onPerspVEnd: (_) {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Tap decrement button (-1°)
      await tester.tap(find.byKey(const Key('persp_h_dec')));
      await tester.pump();
      expect(changedVal, 9.0);
      expect(endedVal, 9.0);

      // Tap increment button (+1°)
      await tester.tap(find.byKey(const Key('persp_h_inc')));
      await tester.pump();
      expect(changedVal, 11.0);
      expect(endedVal, 11.0);

      // Tap reset text (resets to 0°)
      await tester.tap(find.byKey(const Key('persp_h_reset_text')));
      await tester.pump();
      expect(changedVal, 0.0);
      expect(endedVal, 0.0);
    });

    testWidgets('Tapping reset all button triggers callback', (WidgetTester tester) async {
      bool resetTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PerspectivePanel(
              perspH: 10.0,
              perspV: -5.0,
              onPerspHChanged: (_) {},
              onPerspHEnd: (_) {},
              onPerspVChanged: (_) {},
              onPerspVEnd: (_) {},
              onReset: () => resetTriggered = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('persp_reset_all_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('persp_reset_all_btn')));
      await tester.pump();

      expect(resetTriggered, isTrue);
    });

    testWidgets('Slider drag triggers onPerspHChanged', (WidgetTester tester) async {
      double changedVal = 0.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PerspectivePanel(
              perspH: 0.0,
              perspV: 0.0,
              onPerspHChanged: (v) => changedVal = v,
              onPerspHEnd: (_) {},
              onPerspVChanged: (_) {},
              onPerspVEnd: (_) {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Drag horizontal slider to the right
      await tester.drag(find.byKey(const Key('persp_h_slider')), const Offset(40, 0));
      await tester.pump();

      expect(changedVal, greaterThan(0.0));
    });
  });
}
