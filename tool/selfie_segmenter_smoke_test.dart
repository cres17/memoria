import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/ai/models/segmenter.dart';

// Run explicitly after downloading the pinned model and making the platform's
// MediaPipe custom-op library available. This is a native model smoke check;
// it does not download fixtures or change the ordinary unit-test suite.
void main() {
  test('pinned selfie model preserves background probabilities', () async {
    const path = String.fromEnvironment('SELFIE_SEGMENTER_TFLITE_PATH');
    expect(path, isNotEmpty, reason: 'Set SELFIE_SEGMENTER_TFLITE_PATH');
    final file = File(path);
    expect(await file.length(), kModelSelfie.sizeBytes);
    expect(sha256.convert(await file.readAsBytes()).toString(),
        kModelSelfie.sha256);
    final segmenter = await SelfieSegmenter.load(path);
    try {
      final mask = segmenter.segment(img.Image(width: 32, height: 24));
      expect(mask.width, 32);
      expect(mask.height, 24);
      expect(mask.data.length, 32 * 24);
      expect(mask.data.every((value) => value.isFinite), isTrue);
      // Applying sigmoid again would incorrectly raise this empty background
      // from near zero to roughly 0.5.
      expect(mask.data.reduce((a, b) => a > b ? a : b), lessThan(0.1));
    } finally {
      segmenter.dispose();
    }
  });
}
