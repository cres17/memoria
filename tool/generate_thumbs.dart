/// Generates product filter thumbnails from one fixed scene.
///
/// Run from the project root:
///   dart run tool/generate_thumbs.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/engine/custom_lut_core.dart';

const _sourcePath = 'assets/images/summer_sapporo.jpg';
const _outputSize = 320;

void main() {
  final sourceFile = File(_sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Fixed thumbnail source is missing: $_sourcePath');
    exitCode = 66;
    return;
  }

  final decoded = img.decodeImage(sourceFile.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode fixed thumbnail source: $_sourcePath');
    exitCode = 65;
    return;
  }

  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final source = img.copyResize(
    square,
    width: _outputSize,
    height: _outputSize,
    interpolation: img.Interpolation.linear,
  );

  Directory('assets/images').createSync(recursive: true);
  _writeThumbnail(BuiltinPresets.original, source, null);

  for (final preset in BuiltinPresets.all.skip(1)) {
    final lutFile = File(preset.lutPath);
    if (!lutFile.existsSync()) {
      stderr.writeln('LUT is missing for ${preset.id}: ${preset.lutPath}');
      exitCode = 66;
      return;
    }
    final lutBytes = Uint8List.fromList(lutFile.readAsBytesSync());
    _writeThumbnail(preset, source, decodeCustomLut(lutBytes));
  }

  stdout.writeln(
    'Generated ${BuiltinPresets.all.length} fixed-scene filter thumbnails.',
  );
}

void _writeThumbnail(
  FilterPreset preset,
  img.Image source,
  DecodedLut? lut,
) {
  final output = img.Image(width: source.width, height: source.height);
  final mix = preset.defaultIntensity.clamp(0.0, 1.0);

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final r = pixel.r.toDouble() / 255.0;
      final g = pixel.g.toDouble() / 255.0;
      final b = pixel.b.toDouble() / 255.0;
      final filtered =
          lut == null ? (r, g, b) : applyDecodedCustomLutFlat(lut, r, g, b);
      output.setPixelRgb(
        x,
        y,
        ((r * (1 - mix) + filtered.$1 * mix) * 255).round().clamp(0, 255),
        ((g * (1 - mix) + filtered.$2 * mix) * 255).round().clamp(0, 255),
        ((b * (1 - mix) + filtered.$3 * mix) * 255).round().clamp(0, 255),
      );
    }
  }

  File(preset.thumbnailPath)
      .writeAsBytesSync(img.encodeJpg(output, quality: 88));
  stdout.writeln('  ${preset.id} -> ${preset.thumbnailPath}');
}
