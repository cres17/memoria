import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class TextRasterizer {
  static const List<String> presetFonts = [
    'Montserrat',
    'PlayfairDisplay',
    'AmaticSC',
    'Pacifico',
    'Oswald',
    'Raleway',
    'Dosis',
  ];

  static Future<Uint8List> rasterize({
    required String text,
    required String fontFamily,
    required double textSize,
    required Color color,
    required double textX,
    required double textY,
    required double rotationDegrees,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()));

    // Clear background to fully transparent
    canvas.drawColor(Colors.transparent, BlendMode.clear);

    // Calculate scale factor relative to target image resolution.
    // Standard reference height is 1080.0.
    final baseResolutionHeight = 1080.0;
    final scaleFactor = imageHeight / baseResolutionHeight;
    final finalFontSize =
        (textSize * scaleFactor).clamp(4.0, imageHeight.toDouble());

    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: finalFontSize,
      color: color,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Layout the text with a max width constraint of 80% of image width
    final maxWidth = imageWidth * 0.8;
    textPainter.layout(maxWidth: maxWidth);

    // Position the text centered at (textX, textY)
    final baseX = imageWidth * textX;
    final baseY = imageHeight * textY;
    // Paint around the text centre so the visual preview and saved/exported
    // image use the exact same position and rotation.
    canvas.save();
    canvas.translate(baseX, baseY);
    canvas.rotate(rotationDegrees * math.pi / 180);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(imageWidth, imageHeight);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }
}
