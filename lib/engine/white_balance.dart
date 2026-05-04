import '../domain/models/adjust_params.dart';

enum WhiteBalancePreset {
  asShot,
  auto,
  sunny,
  cloudy,
  shade,
  flash,
  fluorescent,
  tungsten,
}

extension WhiteBalancePresetX on WhiteBalancePreset {
  String get label {
    switch (this) {
      case WhiteBalancePreset.asShot:      return '촬영 시';
      case WhiteBalancePreset.auto:        return '자동';
      case WhiteBalancePreset.sunny:       return '맑음';
      case WhiteBalancePreset.cloudy:      return '흐림';
      case WhiteBalancePreset.shade:       return '그늘';
      case WhiteBalancePreset.flash:       return '플래시';
      case WhiteBalancePreset.fluorescent: return '형광등';
      case WhiteBalancePreset.tungsten:    return '백열등';
    }
  }

  /// temperature/tint 오프셋 반환 (sunny = 기준 0/0)
  ({double temperature, double tint}) get offset {
    switch (this) {
      case WhiteBalancePreset.asShot:      return (temperature: 0,   tint: 0);
      case WhiteBalancePreset.auto:        return (temperature: 0,   tint: 0);
      case WhiteBalancePreset.sunny:       return (temperature: 0,   tint: 0);
      case WhiteBalancePreset.cloudy:      return (temperature: 15,  tint: 5);
      case WhiteBalancePreset.shade:       return (temperature: 30,  tint: 8);
      case WhiteBalancePreset.flash:       return (temperature: 5,   tint: 3);
      case WhiteBalancePreset.fluorescent: return (temperature: -30, tint: 25);
      case WhiteBalancePreset.tungsten:    return (temperature: -60, tint: -15);
    }
  }

  AdjustParams applyTo(AdjustParams params) => params.copyWith(
    temperature: offset.temperature,
    tint:        offset.tint,
  );
}
