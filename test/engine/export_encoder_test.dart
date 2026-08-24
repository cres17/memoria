import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/engine/export_encoder.dart';

img.Image _fixture() {
  final image = img.Image(width: 192, height: 128);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255 / (image.width - 1)).round(),
        (y * 255 / (image.height - 1)).round(),
        (x * 13 + y * 7) % 256,
      );
    }
  }
  return image;
}

void main() {
  group('ExportEncoder contracts', () {
    test('JPEG, PNG, and TIFF bytes match their advertised format', () {
      final source = _fixture();
      for (final format in const [
        ExportFormat.jpeg,
        ExportFormat.png,
        ExportFormat.tiff,
      ]) {
        final bytes = ExportEncoder.encode(
          source,
          format: format,
          quality: 95,
        );
        expect(ExportEncoder.matchesSignature(format, bytes), isTrue);
        expect(img.decodeImage(bytes), isNotNull);
      }
    });

    test('JPEG quality is connected to the actual encoder', () {
      final source = _fixture();
      final low = ExportEncoder.encode(
        source,
        format: ExportFormat.jpeg,
        quality: 70,
      );
      final high = ExportEncoder.encode(
        source,
        format: ExportFormat.jpeg,
        quality: 95,
      );
      expect(high.length, greaterThan(low.length));
      expect(ExportEncoder.matchesSignature(ExportFormat.jpeg, low), isTrue);
      expect(ExportEncoder.matchesSignature(ExportFormat.jpeg, high), isTrue);
    });

    test('WebP validator rejects disguised JPEG and accepts RIFF/WEBP', () {
      final jpeg = ExportEncoder.encode(
        _fixture(),
        format: ExportFormat.jpeg,
        quality: 90,
      );
      final webpHeader = <int>[
        0x52,
        0x49,
        0x46,
        0x46,
        0x04,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ];
      expect(ExportEncoder.matchesSignature(ExportFormat.webp, jpeg), isFalse);
      expect(ExportEncoder.matchesSignature(ExportFormat.webp, webpHeader),
          isTrue);
    });

    test('format metadata uses matching extension and MIME', () {
      expect(ExportFormat.jpeg.extension, 'jpg');
      expect(ExportFormat.jpeg.mimeType, 'image/jpeg');
      expect(ExportFormat.png.extension, 'png');
      expect(ExportFormat.png.mimeType, 'image/png');
      expect(ExportFormat.webp.extension, 'webp');
      expect(ExportFormat.webp.mimeType, 'image/webp');
      expect(ExportFormat.tiff.extension, 'tif');
      expect(ExportFormat.tiff.mimeType, 'image/tiff');
    });
  });
}
