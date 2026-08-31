// ─────────────────────────────────────────────────────────
//  CropRatioPreset — 크롭 비율 열거형
//  도메인 모델 레이어에 위치해 편집기와 EditOperation에서 공유됩니다.
// ─────────────────────────────────────────────────────────

enum CropRatioPreset {
  free,
  original,
  r1x1,
  r4x3,
  r3x4,
  r16x9,
  r9x16,
  r3x2,
  r2x3,
  r4x5,
  r5x4,
  r5x7,
  r7x5,
  r8x10,
  r10x8;

  String get l10nKey {
    switch (this) {
      case CropRatioPreset.free:
        return 'crop.free';
      case CropRatioPreset.original:
        return 'crop.original';
      case CropRatioPreset.r1x1:
        return '1:1';
      case CropRatioPreset.r4x3:
        return '4:3';
      case CropRatioPreset.r3x4:
        return '3:4';
      case CropRatioPreset.r16x9:
        return '16:9';
      case CropRatioPreset.r9x16:
        return '9:16';
      case CropRatioPreset.r3x2:
        return '3:2';
      case CropRatioPreset.r2x3:
        return '2:3';
      case CropRatioPreset.r4x5:
        return '4:5';
      case CropRatioPreset.r5x4:
        return '5:4';
      case CropRatioPreset.r5x7:
        return '5:7';
      case CropRatioPreset.r7x5:
        return '7:5';
      case CropRatioPreset.r8x10:
        return '8:10';
      case CropRatioPreset.r10x8:
        return '10:8';
    }
  }

  double? get ratio {
    switch (this) {
      case CropRatioPreset.free:
        return null;
      case CropRatioPreset.original:
        return -1.0; // Sentinel value for original ratio
      case CropRatioPreset.r1x1:
        return 1.0;
      case CropRatioPreset.r4x3:
        return 4 / 3;
      case CropRatioPreset.r3x4:
        return 3 / 4;
      case CropRatioPreset.r16x9:
        return 16 / 9;
      case CropRatioPreset.r9x16:
        return 9 / 16;
      case CropRatioPreset.r3x2:
        return 3 / 2;
      case CropRatioPreset.r2x3:
        return 2 / 3;
      case CropRatioPreset.r4x5:
        return 4 / 5;
      case CropRatioPreset.r5x4:
        return 5 / 4;
      case CropRatioPreset.r5x7:
        return 5 / 7;
      case CropRatioPreset.r7x5:
        return 7 / 5;
      case CropRatioPreset.r8x10:
        return 8 / 10;
      case CropRatioPreset.r10x8:
        return 10 / 8;
    }
  }
}
