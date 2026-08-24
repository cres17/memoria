import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ai/ai_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('memoria-bundled-model-');
    AiManager.instance.clearLocalModelForTesting(kModelColorTransfer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    AiManager.instance.clearLocalModelForTesting(kModelColorTransfer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('bundled Direct MVP is atomically installed and SHA-256 verified',
      () async {
    final path = await AiManager.instance.require(kModelColorTransfer);
    final model = File(path);

    expect(await model.exists(), isTrue);
    expect(await model.length(), kModelColorTransfer.sizeBytes);
    expect(
      sha256.convert(await model.readAsBytes()).toString(),
      kColorTransferModelSha256,
    );
    expect(
      AiManager.instance.stateOf(kModelColorTransfer.key).status,
      ModelStatus.ready,
    );
    expect(File('$path.installing').existsSync(), isFalse);
  });
}
