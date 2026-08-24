import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/engine/edit_operation_player.dart';

img.Image _solidImage(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

EditSession _creativeSession(CreativeParams creative) =>
    EditSession.forImage('memory://creative').pushOp(
      EditOperation(
        id: 'creative',
        tool: EditToolType.creative,
        appliedAt: DateTime.utc(2026, 8, 18),
        creative: creative,
      ),
    );

void main() {
  group('Creative rendering contracts', () {
    test('opaque frame paints its border without hiding the photo centre', () {
      final original = _solidImage(100, 100, 20, 90, 160);
      final frame = _solidImage(100, 100, 220, 40, 30);
      final output = const EditOperationPlayer().play(
        EditOperationPlayerArgs(
          original: original,
          session: _creativeSession(const CreativeParams(frameIndex: 0)),
          frameBytes: img.encodePng(frame),
        ),
      );

      final center = output.getPixel(50, 50);
      final edge = output.getPixel(0, 0);
      expect([center.r, center.g, center.b], [20, 90, 160]);
      expect([edge.r, edge.g, edge.b], [220, 40, 30]);
    });

    test('every bundled frame preserves the central photo area', () {
      const framePaths = [
        'assets/frames/hp_frame_00_overlay.png',
        'assets/frames/hp_frame_01_overlay.png',
        'assets/frames/hp_frame_02_overlay.png',
        'assets/frames/hp_frame_03_overlay.png',
        'assets/frames/hp_frame_04_overlay.png',
        'assets/frames/hp_frame_05_overlay.png',
        'assets/frames/hp_frame_06_overlay.png',
        'assets/frames/hp_frame_07_overlay.png',
        'assets/frames/hp_frame_08_overlay.png',
        'assets/frames/hp_frame_09_overlay.png',
        'assets/frames/hp_frame_10_overlay.png',
        'assets/frames/hp_frame_11_overlay.png',
        'assets/frames/hp_frame_12_overlay.png',
      ];
      const sourceColor = [19, 101, 173];
      final original = _solidImage(
        256,
        256,
        sourceColor[0],
        sourceColor[1],
        sourceColor[2],
      );

      for (final path in framePaths) {
        final decoded = img.decodeImage(File(path).readAsBytesSync())!;
        expect(decoded.numChannels, 4, reason: '$path must be an RGBA asset');
        expect(decoded.getPixel(128, 128).a, 0,
            reason: '$path must have a transparent centre');
        final output = const EditOperationPlayer().play(
          EditOperationPlayerArgs(
            original: original,
            session: _creativeSession(const CreativeParams(frameIndex: 0)),
            frameBytes: File(path).readAsBytesSync(),
          ),
        );

        for (final point in const [(64, 64), (128, 128), (192, 192)]) {
          final pixel = output.getPixel(point.$1, point.$2);
          expect(
            [pixel.r, pixel.g, pixel.b],
            sourceColor,
            reason: '$path must not cover the photo centre at $point',
          );
        }
      }
    });

    test('fallback text renderer visibly composites text into the image', () {
      final original = _solidImage(160, 120, 0, 0, 0);
      final output = const EditOperationPlayer().play(
        EditOperationPlayerArgs(
          original: original,
          session: _creativeSession(const CreativeParams(
            overlayText: 'MEM',
            textSize: 48,
            textX: 0.5,
            textY: 0.5,
            textColorValue: 0xFFFFFFFF,
          )),
        ),
      );

      var changedPixels = 0;
      for (var y = 0; y < output.height; y++) {
        for (var x = 0; x < output.width; x++) {
          if (output.getPixel(x, y).r > 0) changedPixels++;
        }
      }
      expect(changedPixels, greaterThan(0));
    });
  });
}
