import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memoria/ai/ai_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const modelBytes = [1, 2, 3, 4];
  late Directory directory;
  late AiModelInfo model;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memoria-download-');
    model = AiModelInfo(
      key: 'download_test',
      url: 'https://example.invalid/model.tflite',
      sizeBytes: modelBytes.length,
      sha256: sha256.convert(modelBytes).toString(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<void> expectNoModelFiles(AiManager manager) async {
    expect(manager.pathOf(model.key), isNull);
    expect(manager.stateOf(model.key).status, ModelStatus.error);
    final models = Directory('${directory.path}/ai_models');
    expect(await models.list().toList(), isEmpty);
  }

  test('rejects HTTP errors, cleans up the client and permits retry', () async {
    var attempts = 0;
    final clients = <_TrackedClient>[];
    final manager = AiManager.forTesting(clientFactory: () {
      final client = _TrackedClient((_) async {
        attempts++;
        return http.Response.bytes(
          attempts == 1 ? const [4, 0, 4] : modelBytes,
          attempts == 1 ? 404 : 200,
        );
      });
      clients.add(client);
      return client;
    });
    addTearDown(manager.dispose);

    await expectLater(manager.require(model), throwsStateError);
    await expectNoModelFiles(manager);
    expect(clients.single.closed, isTrue);

    final path = await manager.require(model);
    expect(await File(path).readAsBytes(), modelBytes);
    expect(manager.stateOf(model.key).status, ModelStatus.ready);
    expect(clients.last.closed, isTrue);
    expect(File('$path.downloading').existsSync(), isFalse);
  });

  for (final bytes in [
    <int>[],
    <int>[1, 2],
    <int>[4, 3, 2, 1]
  ]) {
    test('rejects empty, truncated or corrupt model bytes: $bytes', () async {
      final manager = AiManager.forTesting(
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      addTearDown(manager.dispose);
      await expectLater(manager.require(model), throwsStateError);
      await expectNoModelFiles(manager);
    });
  }

  test('cleans partial downloads after a stream error', () async {
    final manager = AiManager.forTesting(
      clientFactory: () => MockClient.streaming((_, __) async {
        return http.StreamedResponse(
          (() async* {
            yield <int>[1, 2];
            throw const HttpException('connection interrupted');
          })(),
          200,
        );
      }),
    );
    addTearDown(manager.dispose);
    await expectLater(manager.require(model), throwsA(isA<HttpException>()));
    await expectNoModelFiles(manager);
  });

  test('closes a stalled request and allows a fresh attempt', () async {
    var first = true;
    final clients = <_TrackedClient>[];
    final manager = AiManager.forTesting(
      downloadTimeout: const Duration(milliseconds: 20),
      clientFactory: () {
        final client = _TrackedClient((_) async {
          if (first) {
            first = false;
            return Completer<http.Response>().future;
          }
          return http.Response.bytes(modelBytes, 200);
        });
        clients.add(client);
        return client;
      },
    );
    addTearDown(manager.dispose);
    await expectLater(manager.require(model), throwsA(isA<TimeoutException>()));
    await expectNoModelFiles(manager);
    expect(clients.first.closed, isTrue);
    final path = await manager.require(model);
    expect(await File(path).readAsBytes(), modelBytes);
  });

  test('shares one verified download between simultaneous callers', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final manager = AiManager.forTesting(
      clientFactory: () => MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    addTearDown(manager.dispose);
    final first = manager.require(model);
    final second = manager.require(model);
    response.complete(http.Response.bytes(modelBytes, 200));
    final paths = await Future.wait([first, second]);
    expect(paths[0], paths[1]);
    expect(requests, 1);
    expect(await File(paths.first).readAsBytes(), modelBytes);
  });

  test('removes a partial model when the response stream stalls', () async {
    final controller = StreamController<List<int>>();
    controller.add([1, 2]);
    final manager = AiManager.forTesting(
      downloadTimeout: const Duration(milliseconds: 20),
      clientFactory: () => MockClient.streaming((_, __) async =>
          http.StreamedResponse(controller.stream, 200, contentLength: 4)),
    );
    addTearDown(manager.dispose);
    addTearDown(controller.close);
    await expectLater(manager.require(model), throwsA(isA<TimeoutException>()));
    await expectNoModelFiles(manager);
  });

  test('rejects a response shorter than its declared content length', () async {
    final manager = AiManager.forTesting(
      clientFactory: () => MockClient.streaming((_, __) async =>
          http.StreamedResponse(Stream.value(modelBytes), 200,
              contentLength: 8)),
    );
    addTearDown(manager.dispose);
    await expectLater(manager.require(model), throwsStateError);
    await expectNoModelFiles(manager);
  });
}

class _TrackedClient extends MockClient {
  _TrackedClient(super.handler);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
