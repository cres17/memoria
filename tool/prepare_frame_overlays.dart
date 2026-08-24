import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:memoria/engine/frame_overlay.dart';

void main() {
  for (var index = 0; index < 13; index++) {
    final suffix = index.toString().padLeft(2, '0');
    final source = File('assets/frames/hp_frame_${suffix}_small.png');
    final decoded = img.decodeImage(source.readAsBytesSync());
    if (decoded == null) {
      throw StateError('Could not decode ${source.path}');
    }
    final overlay = buildFrameOverlay(decoded);
    final destination = File('assets/frames/hp_frame_${suffix}_overlay.png');
    destination.writeAsBytesSync(img.encodePng(overlay, level: 9));

    final center = overlay.getPixel(overlay.width ~/ 2, overlay.height ~/ 2);
    if (overlay.numChannels != 4 || center.a != 0) {
      throw StateError('${destination.path} is not a transparent RGBA frame');
    }
  }
}
