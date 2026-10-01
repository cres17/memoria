import 'dart:io';

import 'package:image/image.dart' as img;

// Procedural routing fixtures require no private calibration dataset.
Future<String> writeCoverageFixture(
  Directory directory,
  String kind,
) async {
  final image = img.Image(width: 256, height: 256);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      switch (kind) {
        case 'broad':
          image.setPixelRgb(x, y, x, y, (x + y) % 256);
        case 'narrow':
          image.setPixelRgb(x, y, 200, 80, 40);
        case 'monochrome':
          image.setPixelRgb(x, y, x, x, x);
        default:
          throw ArgumentError.value(kind, 'kind', 'Unknown coverage fixture');
      }
    }
  }
  final file = File('${directory.path}/$kind.png');
  await file.writeAsBytes(img.encodePng(image));
  return file.path;
}
