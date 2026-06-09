import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/custom_adjustment.dart';

void main() {
  group('CustomAdjustment serialization', () {
    final params = AdjustParams.zero.copyWith(exposure: 0.5, saturation: 30);
    final createdAt = DateTime.utc(2025, 1, 1, 12, 0, 0);

    final adj = CustomAdjustment(
      id: 'cadj_001',
      name: 'My Preset',
      params: params,
      createdAt: createdAt,
    );

    test('toJson / fromJson round-trip preserves all fields', () {
      final restored = CustomAdjustment.fromJson(adj.toJson());

      expect(restored.id, adj.id);
      expect(restored.name, adj.name);
      expect(restored.createdAt, adj.createdAt);
      expect(restored.params.exposure, adj.params.exposure);
      expect(restored.params.saturation, adj.params.saturation);
    });

    test('fromJson with zero AdjustParams', () {
      final zero = CustomAdjustment(
        id: 'cadj_zero',
        name: 'Zero',
        params: AdjustParams.zero,
        createdAt: createdAt,
      );
      final restored = CustomAdjustment.fromJson(zero.toJson());
      expect(restored.params.exposure, 0.0);
      expect(restored.params.saturation, 0.0);
    });

    test('toJsonString produces parseable JSON', () {
      final s = adj.toJsonString();
      expect(s, isNotEmpty);
      expect(s, contains('"id"'));
      expect(s, contains('cadj_001'));
    });
  });
}
