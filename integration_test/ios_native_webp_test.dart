import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/engine/engine_channel.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS reports WebP capability and never publishes a fake WebP',
      (tester) async {
    final directory = await getTemporaryDirectory();
    final input = File('${directory.path}/webp-native-input.png');
    final output = File('${directory.path}/webp-native-output.webp');
    final source = img.Image(width: 96, height: 64, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x * 2, y * 3, 140, 255);
      }
    }
    await input.writeAsBytes(img.encodePng(source), flush: true);
    if (await output.exists()) await output.delete();

    final supported = await EngineChannel.supportsWebPEncoding();
    final converted = await EngineChannel.encodeWebP(
      inputPath: input.path,
      outputPath: output.path,
      quality: 91,
    );

    if (!supported) {
      expect(converted, isFalse);
      expect(await output.exists(), isFalse);
      return;
    }

    expect(converted, isTrue);
    expect(await output.exists(), isTrue);
    final bytes = await output.readAsBytes();
    expect(ExportEncoder.matchesSignature(ExportFormat.webp, bytes), isTrue);
    final decoded = img.decodeImage(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, source.width);
    expect(decoded.height, source.height);
  });
}
