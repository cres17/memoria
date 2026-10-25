import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 사용자가 설정에서 켠 경우에만 오류 정보를 보내는 크래시 수집기.
///
/// - 빌드에 `--dart-define=MEMORIA_SENTRY_DSN=https://<key>@<host>/<project>`가 있어야 동작한다.
///   DSN이 없으면 설정 항목도 보이지 않고 아무것도 보내지 않는다.
/// - 기본값은 꺼짐. 켜기 전에는 네트워크 요청이 없다.
/// - 보내는 것: 예외 종류, 정리한 메시지(경로·주소·이메일·긴 숫자 제거), 스택(파일 경로 제거),
///   앱 버전, 운영체제 이름. 사진, 파일 경로, 사용자 식별자, 진단 로그는 보내지 않는다.
/// - 실패는 조용히 무시한다(수집이 앱을 막아서는 안 된다).
class CrashReporter {
  CrashReporter._();

  static final CrashReporter instance = CrashReporter._();

  static const dsn = String.fromEnvironment('MEMORIA_SENTRY_DSN');
  static const release =
      String.fromEnvironment('MEMORIA_RELEASE', defaultValue: 'memoria@1.0.0+1');
  static const prefKey = 'crash_reporting_enabled_v1';

  /// 한 실행에서 보내는 최대 건수.
  static const maxPerSession = 5;
  static const requestTimeout = Duration(seconds: 5);

  CrashDsn? _dsn = CrashDsn.tryParse(dsn);
  bool _enabled = false;
  int _sent = 0;
  final Set<String> _seen = <String>{};
  http.Client? _client;
  bool _allowInDebug = false;

  /// 이 빌드에 수집 대상 서버가 설정되어 있는지.
  bool get isConfigured => _dsn != null;

  /// 사용자가 켰는지(설정된 빌드에서만 true가 될 수 있다).
  bool get enabled => _enabled && isConfigured;

  /// 앱 시작 시 저장된 동의 여부를 읽는다.
  Future<void> initialize({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      _enabled = p.getBool(prefKey) ?? false;
    } catch (_) {
      _enabled = false;
    }
  }

  Future<void> setEnabled(bool value, {SharedPreferences? prefs}) async {
    _enabled = value;
    if (!value) {
      _seen.clear();
      _sent = 0;
    }
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setBool(prefKey, value);
    } catch (_) {
      // 저장에 실패하면 이번 실행에서만 유지된다.
    }
  }

  /// 테스트에서 DSN·전송 클라이언트를 바꾼다.
  @visibleForTesting
  void configureForTest({
    String? dsnValue,
    http.Client? client,
    bool enabled = false,
    bool allowInDebug = true,
  }) {
    _dsn = dsnValue == null ? null : CrashDsn.tryParse(dsnValue);
    _client = client;
    _enabled = enabled;
    _allowInDebug = allowInDebug;
    _sent = 0;
    _seen.clear();
  }

  /// 오류를 보낸다. 꺼져 있거나 설정이 없으면 아무것도 하지 않는다. 절대 예외를 던지지 않는다.
  Future<bool> report(
    Object error,
    StackTrace? stackTrace, {
    String? source,
    DateTime Function()? now,
    String Function()? idGenerator,
  }) async {
    try {
      if (!enabled) return false;
      if (kDebugMode && !_allowInDebug) return false;
      if (_sent >= maxPerSession) return false;
      final target = _dsn;
      if (target == null) return false;

      final event = CrashSanitizer.buildEvent(
        error: error,
        stackTrace: stackTrace,
        release: release,
        source: source,
        platform: Platform.operatingSystem,
        mode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
        now: (now ?? DateTime.now)().toUtc(),
        eventId: (idGenerator ?? _randomEventId)(),
      );
      final fingerprint = (event['fingerprint'] as List<String>).single;
      if (!_seen.add(fingerprint)) return false;
      _sent++;

      final owns = _client == null;
      final client = _client ?? http.Client();
      try {
        final response = await client
            .post(
              target.envelopeUri,
              headers: {
                'Content-Type': 'application/x-sentry-envelope',
                'X-Sentry-Auth': target.authHeader,
              },
              body: CrashSanitizer.buildEnvelope(
                event: event,
                dsn: target.raw,
                sentAt: (now ?? DateTime.now)().toUtc(),
              ),
            )
            .timeout(requestTimeout);
        return response.statusCode >= 200 && response.statusCode < 300;
      } finally {
        if (owns) client.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Sentry는 하이픈 없는 32자리 hex를 요구한다.
  static String _randomEventId() => const Uuid().v4().replaceAll('-', '');
}

/// `https://<public_key>@<host>[/<prefix>]/<project_id>` 형식의 DSN.
class CrashDsn {
  final String raw;
  final String publicKey;
  final Uri envelopeUri;

  const CrashDsn._(this.raw, this.publicKey, this.envelopeUri);

  static CrashDsn? tryParse(String value) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final key = uri.userInfo.split(':').first;
    if (key.isEmpty) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final project = segments.last;
    if (!RegExp(r'^\d+$').hasMatch(project)) return null;
    final prefix = segments.sublist(0, segments.length - 1);
    final envelope = Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: [...prefix, 'api', project, 'envelope', ''],
    );
    return CrashDsn._(value, key, envelope);
  }

  String get authHeader =>
      'Sentry sentry_version=7, sentry_client=memoria-crash/1, sentry_key=$publicKey';
}

/// 보내기 전에 개인정보가 될 수 있는 부분을 제거하고 Sentry 이벤트를 만든다.
class CrashSanitizer {
  static const maxMessageLength = 300;
  static const maxFrames = 50;

  static final _url = RegExp(r'[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s)\]"]+');
  static final _email = RegExp(r'[\w.+\-]+@[\w\-]+(\.[\w\-]+)+');
  // 절대 경로(POSIX·Windows). 마지막 파일 이름만 남긴다.
  static final _path = RegExp(r'(?:[A-Za-z]:\\|/)(?:[^\s/\\:"\x27)\]]+[/\\])+([^\s/\\:"\x27)\]]*)');
  static final _longNumber = RegExp(r'\d{9,}');
  static final _frame = RegExp(r'^#\d+\s+(.*?)\s+\((.*?)(?::(\d+))?(?::(\d+))?\)\s*$');

  /// 메시지에서 URL·이메일·경로·긴 숫자를 가린다.
  static String scrub(String input) {
    var s = input.replaceAll(_url, '<url>');
    s = s.replaceAll(_email, '<email>');
    s = s.replaceAllMapped(_path, (m) {
      final name = m.group(1) ?? '';
      return name.isEmpty ? '<path>' : '<path>/$name';
    });
    s = s.replaceAll(_longNumber, '<num>');
    if (s.length > maxMessageLength) s = '${s.substring(0, maxMessageLength)}…';
    return s;
  }

  /// 파일 위치를 앱 패키지 경로 또는 파일 이름만 남긴다.
  static String scrubFilename(String file) {
    if (file.startsWith('package:') || file.startsWith('dart:')) return file;
    final cleaned = file.replaceAll('\\', '/');
    final name = cleaned.split('/').where((p) => p.isNotEmpty).lastOrNull ?? 'unknown';
    return name;
  }

  static List<Map<String, Object?>> frames(StackTrace? stack) {
    if (stack == null) return const [];
    final out = <Map<String, Object?>>[];
    for (final line in stack.toString().split('\n')) {
      final m = _frame.firstMatch(line.trim());
      if (m == null) continue;
      out.add({
        'function': scrub(m.group(1) ?? ''),
        'filename': scrubFilename(m.group(2) ?? ''),
        if (m.group(3) != null) 'lineno': int.tryParse(m.group(3)!),
        if (m.group(4) != null) 'colno': int.tryParse(m.group(4)!),
        'in_app': (m.group(2) ?? '').startsWith('package:memoria/'),
      });
      if (out.length >= maxFrames) break;
    }
    // Sentry는 오래된 호출이 앞에 오도록 기대한다.
    return out.reversed.toList(growable: false);
  }

  static Map<String, Object?> buildEvent({
    required Object error,
    required StackTrace? stackTrace,
    required String release,
    required String platform,
    required String mode,
    required DateTime now,
    required String eventId,
    String? source,
  }) {
    final type = error.runtimeType.toString();
    final value = scrub(error.toString());
    final frameList = frames(stackTrace);
    final top = frameList.isEmpty ? 'none' : '${frameList.last['filename']}:${frameList.last['lineno']}';
    return {
      'event_id': eventId,
      'timestamp': now.millisecondsSinceEpoch / 1000,
      'platform': 'other',
      'level': 'error',
      'release': release,
      'environment': mode,
      // 같은 위치의 같은 종류 오류는 한 묶음으로 본다.
      'fingerprint': ['$type@$top'],
      'tags': {
        'os': platform,
        'mode': mode,
        if (source != null) 'source': source,
      },
      'exception': {
        'values': [
          {
            'type': type,
            'value': value,
            if (frameList.isNotEmpty) 'stacktrace': {'frames': frameList},
          },
        ],
      },
    };
  }

  static String buildEnvelope({
    required Map<String, Object?> event,
    required String dsn,
    required DateTime sentAt,
  }) {
    final header = jsonEncode({
      'event_id': event['event_id'],
      'sent_at': sentAt.toIso8601String(),
      'dsn': dsn,
    });
    final payload = jsonEncode(event);
    final item = jsonEncode({'type': 'event', 'length': utf8.encode(payload).length});
    return '$header\n$item\n$payload\n';
  }
}
