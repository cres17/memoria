import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/data/repositories/filter_index_recovery_service.dart';

void main() {
  late Directory directory;
  late FilterIndexRecoveryService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memoria_filter_index_');
    service =
        FilterIndexRecoveryService(filtersDirectory: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('recovers decodable ids without replacing the rebuilt index', () async {
    final index = File('${directory.path}/filters_index.json');
    final quarantine = File('${index.path}.corrupt.1');
    await index.writeAsString('["rebuilt"]');
    await quarantine.writeAsString('["original", "rebuilt", 12]');

    final entry = (await service.pending()).single;
    final result = await service.tryRecover(entry);

    expect(result.recovered, isTrue);
    expect(result.recoveredItemCount, 2);
    expect(await index.readAsString(), '["original","rebuilt"]');
    expect(await File('${quarantine.path}.recovery_archive').exists(), isTrue);
    expect(await service.pending(), isEmpty);
  });

  test('keeps unreadable quarantine pending until the user chooses reset',
      () async {
    final quarantine =
        File('${directory.path}/filters_index.json.corrupt.unreadable');
    await quarantine.writeAsString('{broken');

    final entry = (await service.pending()).single;
    final result = await service.tryRecover(entry);

    expect(result.recovered, isFalse);
    expect((await service.pending()).single.rawByteLength, greaterThan(0));

    await service.resetKeepingOriginal(entry);
    expect(
      await File('${quarantine.path}.recovery_archive').exists(),
      isTrue,
    );
    expect(await service.pending(), isEmpty);
  });

  test('discard removes only the quarantined original', () async {
    final index = File('${directory.path}/filters_index.json');
    final quarantine = File('${index.path}.corrupt.2');
    await index.writeAsString('["rebuilt"]');
    await quarantine.writeAsString('{broken');

    await service.discardOriginal((await service.pending()).single);

    expect(await index.readAsString(), '["rebuilt"]');
    expect(await quarantine.exists(), isFalse);
  });
}
