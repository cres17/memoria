import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/style_analyzer.dart';

void main() {
  test('selected photo produces palette colors and visible style tags', () {
    final image = img.Image(width: 64, height: 64);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, 48 + x * 2, 72 + y * 2, 118);
      }
    }

    final palette = extractPalette(image);
    final tags = deriveStyleTags(StyleAnalyzer.analyze(image));

    expect(palette, hasLength(4));
    expect(tags, isNotEmpty);
  });
}
