import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/core/services/export_preferences.dart';

class ExportEncoder {
  const ExportEncoder._();

  static Uint8List encode(
    img.Image image, {
    required ExportFormat format,
    required int quality,
  }) {
    final encoded = switch (format) {
      ExportFormat.jpeg =>
        img.encodeJpg(image, quality: quality.clamp(70, 100)),
      ExportFormat.png => img.encodePng(image),
      ExportFormat.tiff => img.encodeTiff(image),
      ExportFormat.webp => throw UnsupportedError(
          'WebP is encoded by the native ImageIO bridge.',
        ),
    };
    return Uint8List.fromList(encoded);
  }

  static bool matchesSignature(ExportFormat format, List<int> bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    return switch (format) {
      ExportFormat.jpeg => startsWith(const [0xFF, 0xD8, 0xFF]),
      ExportFormat.png =>
        startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ExportFormat.webp => bytes.length >= 12 &&
          startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50,
      ExportFormat.tiff => startsWith(const [0x49, 0x49, 0x2A, 0x00]) ||
          startsWith(const [0x4D, 0x4D, 0x00, 0x2A]),
    };
  }
}
