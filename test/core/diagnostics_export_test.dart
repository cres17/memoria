import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/error/diagnostics_export.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('diag'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('기록이 있으면 보고서 파일을 만들어 공유 함수에 넘긴다', () async {
    String? shared;
    final exporter = DiagnosticsExport(
      temporaryDirectory: () async => dir,
      share: (path) async => shared = path,
      readLogs: () => ['[t1] first', '[t2] second | Error: boom'],
      now: () => DateTime.utc(2026, 10, 25, 9),
    );

    expect(await exporter.exportAndShare(), isTrue);
    final text = File(shared!).readAsStringSync();
    expect(text, startsWith('Memoria diagnostics'));
    expect(text, contains('entries: 2'));
    expect(text, contains('[t2] second | Error: boom'));
    expect(shared, endsWith('.txt'));
  });

  test('기록이 없으면 파일을 만들지 않고 false', () async {
    var called = false;
    final exporter = DiagnosticsExport(
      temporaryDirectory: () async => dir,
      share: (_) async => called = true,
      readLogs: () => const [],
    );
    expect(await exporter.exportAndShare(), isFalse);
    expect(called, isFalse);
    expect(dir.listSync(), isEmpty);
  });
}
