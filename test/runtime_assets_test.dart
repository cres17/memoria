import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/domain/models/filter_preset.dart';

// CI runs this gate before producing either signed or unsigned artifacts.
// Loading through rootBundle also verifies the pubspec packaging contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled release model matches the runtime size and SHA-256', () async {
    final asset = await rootBundle.load(kModelColorTransfer.assetPath);
    final bytes =
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    expect(bytes.length, kModelColorTransfer.sizeBytes);
    expect(sha256.convert(bytes).toString(), kModelColorTransfer.sha256);
  });

  test('every built-in LUT is bundled at its required fp16 dimensions',
      () async {
    for (final id in BuiltinPresets.ids.where((id) => id != 'original')) {
      final asset = await rootBundle.load('assets/luts/$id.bin');
      expect(asset.lengthInBytes, 65 * 65 * 65 * 3 * 2, reason: id);
    }
  });

  test('every built-in thumbnail is bundled with a JPEG signature', () async {
    for (final id in BuiltinPresets.ids) {
      final asset = await rootBundle.load('assets/images/${id}_thumb.jpg');
      final bytes =
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
      expect(bytes.length, greaterThan(3), reason: id);
      expect(bytes.take(3), [0xff, 0xd8, 0xff], reason: id);
    }
  });
}
