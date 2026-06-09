import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/features/editor/widgets/filter_strip.dart';

void main() {
  testWidgets('shows presets and selecting a preset invokes onSelect',
      (tester) async {
    FilterPreset? selected;
    final preset1 = BuiltinPresets.portrait;
    final preset2 = BuiltinPresets.smooth;

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
    expect(find.text('Portrait'), findsOneWidget);
    expect(find.text('Smooth'), findsOneWidget);

    // Tap the second preset (Smooth)
    await tester.tap(find.text('Smooth'));
    await tester.pumpAndSettle();

    // Verify callback was triggered with the Smooth preset
    expect(selected, isNotNull);
    expect(selected!.id, equals(preset2.id));
  });

  testWidgets('tapping selected preset again triggers onSelect(null)',
      (tester) async {
    FilterPreset? selected = BuiltinPresets.portrait;
    final preset1 = BuiltinPresets.portrait;

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
    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();

    // Verify it was deselected (callback parameter is null)
    expect(selected, isNull);
  });

  testWidgets('favorite toggle is exposed via long press',
      (tester) async {
    final toggled = <String>[];
    final preset1 = BuiltinPresets.portrait;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.black,
          child: FilterStrip(
            presets: [preset1],
            selectedId: null,
            favoriteIds: const { 'portrait' },
            onSelect: (_) {},
            onFavoriteToggle: toggled.add,
          ),
        ),
      ),
    );

    // Verify favorite star icon is displayed since favoriteIds contains 'portrait'
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    // Long press the preset to toggle favorite
    await tester.longPress(find.text('Portrait'));
    await tester.pumpAndSettle();

    expect(toggled, ['portrait']);
  });
}
