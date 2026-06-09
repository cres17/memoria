import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/features/editor/widgets/crop_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_crop_ratios': ['1.43', '1.67'],
      'custom_crop_ratios': ['1.43', '1.67'],
    });
  });

  group('CropPanel Widget Tests', () {
    testWidgets('Renders all standard presets and custom presets', (WidgetTester tester) async {
      CropRatioPreset selectedPreset = CropRatioPreset.free;
      double? selectedCustomRatio;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CropPanel(
              activePreset: selectedPreset,
              currentCustomRatio: 1.5,
              lockedCustomRatio: selectedCustomRatio,
              onPresetSelected: (p) => selectedPreset = p,
              onCustomRatioSelected: (r) => selectedCustomRatio = r,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('자유'), findsOneWidget);
      expect(find.text('원본'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
      expect(find.text('4:3'), findsOneWidget);

      // Scroll to the custom presets step-by-step
      for (int i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }

      expect(find.text('1.43:1'), findsOneWidget);
      expect(find.text('1.67:1'), findsOneWidget);

      expect(find.text('현재 비율 저장 (1.50:1)'), findsOneWidget);
    });

    testWidgets('Selects standard preset and triggers callback', (WidgetTester tester) async {
      CropRatioPreset selectedPreset = CropRatioPreset.free;
      double? selectedCustomRatio;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CropPanel(
              activePreset: selectedPreset,
              currentCustomRatio: 1.5,
              lockedCustomRatio: selectedCustomRatio,
              onPresetSelected: (p) => selectedPreset = p,
              onCustomRatioSelected: (r) => selectedCustomRatio = r,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('1:1'));
      await tester.pumpAndSettle();

      expect(selectedPreset, CropRatioPreset.r1x1);
      expect(selectedCustomRatio, isNull);
    });

    testWidgets('Saves current custom ratio and updates UI', (WidgetTester tester) async {
      CropRatioPreset selectedPreset = CropRatioPreset.free;
      double? selectedCustomRatio;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CropPanel(
              activePreset: selectedPreset,
              currentCustomRatio: 1.85,
              lockedCustomRatio: selectedCustomRatio,
              onPresetSelected: (p) => selectedPreset = p,
              onCustomRatioSelected: (r) => selectedCustomRatio = r,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('현재 비율 저장 (1.85:1)'));
      
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Scroll to the custom presets step-by-step
      for (int i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }

      expect(find.text('1.85:1'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('custom_crop_ratios');
      expect(list, contains('1.85'));
    });
  });
}
