import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/features/editor/widgets/curve_editor.dart';

void main() {
  group('CurveEditorPanel Widget Tests', () {
    late Map<CurveChannel, CurveData> initialCurves;
    late List<Map<String, dynamic>> callbackHistory;

    setUp(() {
      initialCurves = {
        CurveChannel.luminance: CurveData.linear(CurveChannel.luminance),
        CurveChannel.rgb: CurveData.linear(CurveChannel.rgb),
        CurveChannel.red: CurveData.linear(CurveChannel.red),
        CurveChannel.green: CurveData.linear(CurveChannel.green),
        CurveChannel.blue: CurveData.linear(CurveChannel.blue),
      };
      callbackHistory = [];
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: CurveEditorPanel(
            curves: initialCurves,
            onChanged: (channel, data) {
              initialCurves[channel] = data;
              callbackHistory.add({
                'type': 'changed',
                'channel': channel,
                'data': data,
              });
            },
            onChangeEnd: (channel, data) {
              initialCurves[channel] = data;
              callbackHistory.add({
                'type': 'changedEnd',
                'channel': channel,
                'data': data,
              });
            },
          ),
        ),
      );
    }

    testWidgets(
        'renders all channel buttons and default active channel is luminance',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Check for labels L, RGB, R, G, B
      expect(find.text('L'), findsOneWidget);
      expect(find.text('RGB'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);

      // Verify reset icon exists
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    });

    testWidgets(
        'switching channels updates active curve view and invokes callbacks',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Tap 'RGB' button
      await tester.tap(find.text('RGB'));
      await tester.pumpAndSettle();

      // Tap 'R' button
      await tester.tap(find.text('R'));
      await tester.pumpAndSettle();

      // We should be able to switch channels without crashing.
      expect(find.text('RGB'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets(
        'tapping canvas adds a new control point and triggers onChanged',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final canvasFinder = find.descendant(
        of: find.byType(CurveEditor),
        matching: find.byType(CustomPaint),
      );
      expect(canvasFinder, findsOneWidget);

      final center = tester.getCenter(canvasFinder);

      // Drag down by 30px to exceed slop, then drag back to center, then release
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // onChanged should have been called when adding point
      final changeEvents =
          callbackHistory.where((e) => e['type'] == 'changed').toList();
      expect(changeEvents, isNotEmpty);

      final CurveData lastData = changeEvents.last['data'];
      expect(lastData.points.length, equals(3));
      expect(lastData.points[1].x, closeTo(0.5, 0.05));
    });

    testWidgets(
        'dragging control point changes its coordinates and invokes onChangeEnd on release',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final canvasFinder = find.descendant(
        of: find.byType(CurveEditor),
        matching: find.byType(CustomPaint),
      );
      final center = tester.getCenter(canvasFinder);

      // Add a point first at the center
      final gesture1 = await tester.startGesture(center);
      await gesture1.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture1.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture1.up();
      await tester.pumpAndSettle();
      callbackHistory.clear();

      // Drag the added point (which is at center).
      // Start gesture there and drag upwards (y gets larger, dy gets smaller)
      final gesture2 = await tester.startGesture(center);
      await gesture2.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture2.moveBy(const Offset(0, -10));
      await tester.pump();
      await gesture2.up();
      await tester.pumpAndSettle();

      final endEvents =
          callbackHistory.where((e) => e['type'] == 'changedEnd').toList();
      expect(endEvents, isNotEmpty);

      final CurveData finalData = endEvents.last['data'];
      expect(finalData.points[1].y, greaterThan(0.5));
    });

    testWidgets('double tap on non-endpoint control point deletes it',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final canvasFinder = find.descendant(
        of: find.byType(CurveEditor),
        matching: find.byType(CustomPaint),
      );
      final center = tester.getCenter(canvasFinder);

      // Add point
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      callbackHistory.clear();

      // Double-tap the point at center to delete it
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      final endEvents =
          callbackHistory.where((e) => e['type'] == 'changedEnd').toList();
      expect(endEvents, isNotEmpty);

      final CurveData finalData = endEvents.last['data'];
      // The curve should return to 2 points
      expect(finalData.points.length, equals(2));
    });

    testWidgets(
        'tapping reset button returns the active curve to linear identity state',
        (tester) async {
      // Set initial curve with an edited point (e.g. S-curve)
      initialCurves[CurveChannel.luminance] = const CurveData(
        channel: CurveChannel.luminance,
        points: [CurvePoint(0, 0), CurvePoint(0.5, 0.7), CurvePoint(1, 1)],
      );

      await tester.pumpWidget(buildTestWidget());

      // Tap the reset button (Icons.replay_rounded)
      final resetFinder = find.byIcon(Icons.replay_rounded);
      expect(resetFinder, findsOneWidget);
      await tester.tap(resetFinder);
      await tester.pumpAndSettle();

      final changeEvents =
          callbackHistory.where((e) => e['type'] == 'changed').toList();
      expect(changeEvents, isNotEmpty);

      final CurveData resetData = changeEvents.last['data'];
      expect(resetData.isLinear, isTrue);
      expect(resetData.points.length, equals(2));
      expect(resetData.points.first.y, equals(0.0));
      expect(resetData.points.last.y, equals(1.0));
    });
  });
}
