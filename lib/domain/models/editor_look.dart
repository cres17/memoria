import 'adjust_params.dart';
import 'edit_operation.dart';

/// 사진마다 달라지는 값(크롭, 부분 보정 위치, 브러시 획, 텍스트, 초점)을
/// 뺀 "보정 룩". 보정 복사·붙여넣기와 조정 프리셋이 같은 범위를 쓴다.
class EditorLook {
  final AdjustParams params;
  final String? presetId;
  final double intensity;
  final String artisticEffect;
  final double effectStrength;
  final int grainVariant;
  final PortraitParams portrait;

  const EditorLook({
    required this.params,
    this.presetId,
    this.intensity = 1,
    this.artisticEffect = 'none',
    this.effectStrength = 1,
    this.grainVariant = 3,
    this.portrait = PortraitParams.zero,
  });

  Map<String, dynamic> toJson() => {
        'params': params.toJson(),
        'presetId': presetId,
        'intensity': intensity,
        'artisticEffect': artisticEffect,
        'effectStrength': effectStrength,
        'grainVariant': grainVariant,
        'portrait': portrait.toJson(),
      };

  factory EditorLook.fromJson(Map<String, dynamic> json) => EditorLook(
        params: AdjustParams.fromJson(json['params'] as Map<String, dynamic>),
        presetId: json['presetId'] as String?,
        intensity: (json['intensity'] as num? ?? 1).toDouble(),
        artisticEffect: json['artisticEffect'] as String? ?? 'none',
        effectStrength: (json['effectStrength'] as num? ?? 1).toDouble(),
        grainVariant: (json['grainVariant'] as num? ?? 3).toInt(),
        portrait: json['portrait'] is Map<String, dynamic>
            ? PortraitParams.fromJson(json['portrait'] as Map<String, dynamic>)
            : PortraitParams.zero,
      );
}
