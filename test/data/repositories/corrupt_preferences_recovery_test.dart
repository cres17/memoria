import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/data/repositories/custom_adjustment_repository.dart';
import 'package:memoria/data/repositories/favorites_repository.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/custom_adjustment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saving after corrupt adjustments preserves the raw backup', () async {
    const raw = '{not json';
    SharedPreferences.setMockInitialValues({'custom_adjustments_v1': raw});
    final repository = CustomAdjustmentRepository();

    await repository.save(
      CustomAdjustment(
        id: 'restored',
        name: 'Restored',
        params: AdjustParams.zero,
        createdAt: DateTime.utc(2026, 8, 25),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_adjustments_v1_corrupt_backup'), raw);
    expect((await repository.getAll()).single.id, 'restored');
  });

  test('saving after corrupt favorites preserves the raw backup', () async {
    const raw = '[broken';
    SharedPreferences.setMockInitialValues({'filter_favorites_v1': raw});
    final repository = FavoritesRepository();

    await repository.add('preset-1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('filter_favorites_v1_corrupt_backup'), raw);
    expect(await repository.getFavoriteIds(), {'preset-1'});
  });
}
