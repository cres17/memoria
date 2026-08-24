import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/features/editor/widgets/filter_strip.dart';

void main() {
  testWidgets('shows presets and selecting a preset invokes onSelect',
      (tester) async {
    FilterPreset? selected;
    final preset1 = BuiltinPresets.fujiProvia;
    final preset2 = BuiltinPresets.leicaM8;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.black,
          child: FilterStrip(
            presets: [preset1, preset2],
            selectedId: preset1.id,
            favoriteIds: const {},
            onSelect: (preset) => selected = preset,
            onFavoriteToggle: (_) {},
          ),
        ),
      ),
    );

    // Verify both presets are displayed by name
    expect(find.text('Provia'), findsOneWidget);
    expect(find.text('M8'), findsOneWidget);
    expect(find.text('FUJIFILM'), findsOneWidget);
    expect(find.text('LEICA'), findsOneWidget);

    // Tap the second preset (Smooth)
    await tester.tap(find.text('M8'));
    await tester.pumpAndSettle();

    // Verify callback was triggered with the Smooth preset
    expect(selected, isNotNull);
    expect(selected!.id, equals(preset2.id));
  });

  testWidgets('tapping selected preset again triggers onSelect(null)',
      (tester) async {
    FilterPreset? selected = BuiltinPresets.fujiProvia;
    final preset1 = BuiltinPresets.fujiProvia;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.black,
          child: FilterStrip(
            presets: [preset1],
            selectedId: preset1.id,
            favoriteIds: const {},
            onSelect: (preset) => selected = preset,
            onFavoriteToggle: (_) {},
          ),
        ),
      ),
    );

    // Tap the selected preset
    await tester.tap(find.text('Provia'));
    await tester.pumpAndSettle();

    // Verify it was deselected (callback parameter is null)
    expect(selected, isNull);
  });

  testWidgets('favorite toggle is exposed via long press', (tester) async {
    final toggled = <String>[];
    final preset1 = BuiltinPresets.fujiProvia;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.black,
          child: FilterStrip(
            presets: [preset1],
            selectedId: null,
            favoriteIds: const {'fuji_provia'},
            onSelect: (_) {},
            onFavoriteToggle: toggled.add,
          ),
        ),
      ),
    );

    // Verify the brand catalog entry can also be favorited.
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    // Long press the preset to toggle favorite
    await tester.longPress(find.text('Provia'));
    await tester.pumpAndSettle();

    expect(toggled, ['fuji_provia']);
  });
}
