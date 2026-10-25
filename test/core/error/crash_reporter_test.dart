import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memoria/core/error/crash_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dsn = 'https://abc123@o1.ingest.example.io/4500';

StackTrace _trace() => StackTrace.fromString('''
#0      Foo.bar (package:memoria/engine/foo.dart:12:5)
#1      _run (file:///data/user/0/com.example.memoria/app_flutter/secret_user/x.dart:7:3)
#2      main (package:memoria/main.dart:30:3)
''');

void main() {
  late CrashReporter reporter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reporter = CrashReporter.instance;
  });

  group('DSN', () {
    test('정상 DSN에서 envelope 주소와 키를 만든다', () {
      final d = CrashDsn.tryParse(_dsn)!;
      expect(d.publicKey, 'abc123');
      expect(d.envelopeUri.toString(), 'https://o1.ingest.example.io/api/4500/envelope/');
      expect(d.authHeader, contains('sentry_key=abc123'));
    });

    test('경로 접두사를 유지한다', () {
      final d = CrashDsn.tryParse('https://k@host.example/sentry/12')!;
      expect(d.envelopeUri.toString(), 'https://host.example/sentry/api/12/envelope/');
    });

    test('https가 아니거나 형식이 틀리면 null', () {
      expect(CrashDsn.tryParse(''), isNull);
      expect(CrashDsn.tryParse('http://k@h/1'), isNull);
      expect(CrashDsn.tryParse('https://h/1'), isNull);
      expect(CrashDsn.tryParse('https://k@h/'), isNull);
      expect(CrashDsn.tryParse('https://k@h/abc'), isNull);
    });
  });

  group('개인정보 제거', () {
    test('메시지에서 경로·주소·이메일·긴 숫자를 가린다', () {
      final out = CrashSanitizer.scrub(
          'Cannot open /var/mobile/Containers/Data/Application/ABC/Documents/내사진.jpg '
          'from https://example.com/a?token=secret mail kim@test.co.kr id 123456789012');
      expect(out, isNot(contains('/var/mobile')));
      expect(out, isNot(contains('token=secret')));
      expect(out, isNot(contains('kim@')));
      expect(out, isNot(contains('123456789012')));
      expect(out, contains('<url>'));
      expect(out, contains('<email>'));
    });

    test('Windows 경로도 파일 이름만 남긴다', () {
      final out = CrashSanitizer.scrub(r'failed C:\Users\hong\Pictures\a.png now');
      expect(out, isNot(contains('hong')));
      expect(out, contains('a.png'));
    });

    test('긴 메시지는 자른다', () {
      expect(CrashSanitizer.scrub('x' * 1000).length, lessThanOrEqualTo(301));
    });

    test('스택의 file:// 경로는 파일 이름만 남기고 package 경로는 유지한다', () {
      final frames = CrashSanitizer.frames(_trace());
      final names = frames.map((f) => f['filename']).toList();
      expect(names, contains('package:memoria/engine/foo.dart'));
      expect(names, contains('x.dart'));
      expect(jsonEncode(frames), isNot(contains('secret_user')));
      expect(jsonEncode(frames), isNot(contains('/data/user')));
      // 오래된 호출이 앞
      expect(frames.first['filename'], 'package:memoria/main.dart');
    });

    test('이벤트에 사용자 식별 항목이 없다', () {
      final e = CrashSanitizer.buildEvent(
        error: StateError('bad /home/me/photo.jpg'),
        stackTrace: _trace(),
        release: 'memoria@1.0.0+1',
        platform: 'ios',
        mode: 'release',
        now: DateTime.utc(2026, 10, 1),
        eventId: 'a' * 32,
      );
      final text = jsonEncode(e);
      expect(text, isNot(contains('/home/me')));
      expect(e.containsKey('user'), isFalse);
      expect(e.containsKey('server_name'), isFalse);
      expect(e['fingerprint'], isA<List<String>>());
    });
  });

  group('전송', () {
    test('설정에서 켜기 전에는 요청하지 않는다', () async {
      var called = false;
      reporter.configureForTest(
          dsnValue: _dsn,
          enabled: false,
          client: MockClient((_) async {
            called = true;
            return http.Response('', 200);
          }));
      expect(await reporter.report(StateError('x'), _trace()), isFalse);
      expect(called, isFalse);
    });

    test('DSN이 없으면 켜도 보내지 않는다', () async {
      reporter.configureForTest(dsnValue: null, enabled: true);
      expect(reporter.isConfigured, isFalse);
      expect(reporter.enabled, isFalse);
      expect(await reporter.report(StateError('x'), _trace()), isFalse);
    });

    test('켠 뒤에는 envelope 형식으로 보낸다', () async {
      late http.Request seen;
      reporter.configureForTest(
          dsnValue: _dsn,
          enabled: true,
          client: MockClient((r) async {
            seen = r;
            return http.Response('{}', 200);
          }));
      final ok = await reporter.report(
        StateError('open /Users/me/a.jpg'),
        _trace(),
        source: 'flutter',
        now: () => DateTime.utc(2026, 10, 1),
        idGenerator: () => 'b' * 32,
      );
      expect(ok, isTrue);
      expect(seen.url.toString(), 'https://o1.ingest.example.io/api/4500/envelope/');
      expect(seen.headers['X-Sentry-Auth'], contains('sentry_key=abc123'));
      final lines = seen.body.trim().split('\n');
      expect(lines.length, 3);
      expect(jsonDecode(lines[0])['event_id'], 'b' * 32);
      final item = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(item['type'], 'event');
      expect(item['length'], utf8.encode(lines[2]).length);
      expect(seen.body, isNot(contains('/Users/me')));
    });

    test('같은 오류는 한 번만, 한 실행에 최대 5건', () async {
      var calls = 0;
      reporter.configureForTest(
          dsnValue: _dsn,
          enabled: true,
          client: MockClient((_) async {
            calls++;
            return http.Response('', 200);
          }));
      await reporter.report(StateError('a'), _trace());
      await reporter.report(StateError('a'), _trace());
      expect(calls, 1);
      for (var i = 0; i < 10; i++) {
        await reporter.report(
          ArgumentError('x'),
          StackTrace.fromString('#0 f (package:memoria/m$i.dart:1:1)'),
        );
      }
      expect(calls, CrashReporter.maxPerSession);
    });

    test('전송 실패·시간 초과도 예외를 던지지 않는다', () async {
      reporter.configureForTest(
          dsnValue: _dsn,
          enabled: true,
          client: MockClient((_) async => throw http.ClientException('down')));
      expect(await reporter.report(StateError('a'), _trace()), isFalse);

      reporter.configureForTest(
          dsnValue: _dsn,
          enabled: true,
          client: MockClient((_) async => http.Response('no', 500)));
      expect(await reporter.report(StateError('b'), _trace()), isFalse);
    });
  });

  group('동의 저장', () {
    test('기본은 꺼짐이고 켜기·끄기가 저장된다', () async {
      final prefs = await SharedPreferences.getInstance();
      reporter.configureForTest(dsnValue: _dsn);
      await reporter.initialize(prefs: prefs);
      expect(reporter.enabled, isFalse);
      await reporter.setEnabled(true, prefs: prefs);
      expect(prefs.getBool(CrashReporter.prefKey), isTrue);
      expect(reporter.enabled, isTrue);
      await reporter.setEnabled(false, prefs: prefs);
      expect(prefs.getBool(CrashReporter.prefKey), isFalse);
      expect(reporter.enabled, isFalse);
    });

    test('빌드에 DSN이 없을 때 기본 상수는 비어 있다(공개 빌드는 아무것도 보내지 않음)', () {
      expect(CrashReporter.dsn, isEmpty);
    });
  });
}
