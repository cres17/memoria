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
  String get l10nKey {
    switch (this) {
      case WhiteBalancePreset.asShot:
        return 'wb.as_shot';
      case WhiteBalancePreset.auto:
        return 'wb.auto';
      case WhiteBalancePreset.sunny:
        return 'wb.sunny';
      case WhiteBalancePreset.cloudy:
        return 'wb.cloudy';
      case WhiteBalancePreset.shade:
        return 'wb.shade';
      case WhiteBalancePreset.flash:
        return 'wb.flash';
      case WhiteBalancePreset.fluorescent:
        return 'wb.fluorescent';
      case WhiteBalancePreset.tungsten:
        return 'wb.tungsten';
    }
  }

  /// temperature/tint 오프셋 반환 (sunny = 기준 0/0)
  ({double temperature, double tint}) get offset {
    switch (this) {
      case WhiteBalancePreset.asShot:
        return (temperature: 0, tint: 0);
      case WhiteBalancePreset.auto:
        return (temperature: 0, tint: 0);
      case WhiteBalancePreset.sunny:
        return (temperature: 0, tint: 0);
      case WhiteBalancePreset.cloudy:
        return (temperature: 15, tint: 5);
      case WhiteBalancePreset.shade:
        return (temperature: 30, tint: 8);
      case WhiteBalancePreset.flash:
        return (temperature: 5, tint: 3);
      case WhiteBalancePreset.fluorescent:
        return (temperature: -30, tint: 25);
      case WhiteBalancePreset.tungsten:
        return (temperature: -60, tint: -15);
    }
  }

  AdjustParams applyTo(AdjustParams params) => params.copyWith(
        temperature: offset.temperature,
        tint: offset.tint,
      );
}
