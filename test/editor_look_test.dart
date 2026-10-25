import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/custom_adjustment.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';

void main() {
  test('보정 룩은 JSON으로 저장했다가 그대로 복원된다', () {
    final look = EditorLook(
      params: AdjustParams.zero.copyWith(exposure: 12),
      presetId: 'preset_a',
      intensity: 0.6,
      artisticEffect: 'none',
      grainVariant: 2,
      portrait: const PortraitParams(smooth: 30),
    );
    final restored = EditorLook.fromJson(look.toJson());
    expect(restored.params.exposure, 12);
    expect(restored.presetId, 'preset_a');
    expect(restored.intensity, 0.6);
    expect(restored.grainVariant, 2);
    expect(restored.portrait.smooth, 30);
  });

  test('look 없는 기존 조정 프리셋도 읽힌다', () {
    final json = CustomAdjustment(
      id: 'a',
      name: 'old',
      params: AdjustParams.zero.copyWith(exposure: 5),
      createdAt: DateTime(2026, 1, 1),
    ).toJson();
    expect(json.containsKey('look'), isFalse);
    final restored = CustomAdjustment.fromJson(json);
    expect(restored.look, isNull);
    expect(restored.params.exposure, 5);
  });

  test('붙여넣기는 크롭·부분 보정·텍스트를 건드리지 않는다', () {
    final source = EditorEditState()
      ..params = AdjustParams.zero.copyWith(exposure: 20)
      ..intensity = 0.5;
    final look = source.captureLook();

    final target = EditorEditState()
      ..cropLeft = 0.1
      ..rotation = 5
      ..selectiveActive = true
      ..selectiveX = 0.2
      ..overlayText = 'keep';
    target.applyLook(look, resolvedPreset: null);

    expect(target.params.exposure, 20);
    expect(target.intensity, 0.5);
    expect(target.cropLeft, 0.1);
    expect(target.rotation, 5);
    expect(target.selectiveActive, isTrue);
    expect(target.selectiveX, 0.2);
    expect(target.overlayText, 'keep');
  });
}
