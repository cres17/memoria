import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../error/error_handler.dart';

/// 원격으로 끌 수 있는 기능(킬 스위치).
///
/// 값이 `true`면 해당 기능을 끈다. 어떤 실패(네트워크, 형식 오류, 오래된 캐시)에서도
/// 기본값(모두 켜짐)으로 동작한다(fail-open). 사용자 정보는 서버로 보내지 않는다.
class RemoteConfig {
  final bool skyDisabled;
  final bool rawDisabled;
  final bool batchDisabled;
  final bool adsDisabled;
  // GPU is an opt-in experiment; absent/invalid/expired config keeps CPU.
  final bool gpuOpsIosEnabled;

  const RemoteConfig({
    this.skyDisabled = false,
    this.rawDisabled = false,
    this.batchDisabled = false,
    this.adsDisabled = false,
    this.gpuOpsIosEnabled = false,
  });

  static const RemoteConfig defaults = RemoteConfig();

  /// 서버가 쓸 수 있는 키. 목록에 없는 키는 무시한다.
  static const knownKeys = ['sky', 'raw', 'batch', 'ads'];

  /// 지원하는 스키마 버전.
  static const supportedSchema = 1;

  /// 응답 본문 상한(바이트). 이보다 크면 버린다.
  static const maxBodyBytes = 16 * 1024;

  /// 형식이 맞지 않으면 null. 알 수 없는 키는 무시하고, bool이 아닌 값이 있으면 전체를 거부한다.
  static RemoteConfig? parse(String body) {
    if (body.length > maxBodyBytes) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['schema'] != supportedSchema) return null;
    final disabled = decoded['disabled'];
    if (disabled is! Map<String, dynamic>) return null;
    final enabled = decoded['enabled'];
    if (enabled != null && enabled is! Map<String, dynamic>) return null;
    final gpu = enabled is Map ? enabled['gpu_ops_ios'] : null;
    if (gpu != null && gpu is! bool) return null;
    final flags = <String, bool>{};
    for (final key in knownKeys) {
      final value = disabled[key];
      if (value == null) continue;
      if (value is! bool) return null;
      flags[key] = value;
    }
    return RemoteConfig(
      skyDisabled: flags['sky'] ?? false,
      rawDisabled: flags['raw'] ?? false,
      batchDisabled: flags['batch'] ?? false,
      adsDisabled: flags['ads'] ?? false,
      gpuOpsIosEnabled: gpu == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteConfig &&
      other.skyDisabled == skyDisabled &&
      other.rawDisabled == rawDisabled &&
      other.batchDisabled == batchDisabled &&
      other.adsDisabled == adsDisabled &&
      other.gpuOpsIosEnabled == gpuOpsIosEnabled;

  @override
  int get hashCode => Object.hash(
      skyDisabled, rawDisabled, batchDisabled, adsDisabled, gpuOpsIosEnabled);

  @override
  String toString() =>
      'RemoteConfig(sky:$skyDisabled raw:$rawDisabled batch:$batchDisabled ads:$adsDisabled)';
}

/// 원격 설정을 내려받아 마지막으로 검증된 값을 캐시하고, 앱 전역에 알린다.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  /// 빌드 시 `--dart-define=MEMORIA_REMOTE_CONFIG_URL=...`로 바꾼다. 빈 문자열이면 비활성.
  static const defaultUrl = String.fromEnvironment(
    'MEMORIA_REMOTE_CONFIG_URL',
    defaultValue:
        'https://raw.githubusercontent.com/cres17/memoria/main/config/remote_flags.json',
  );

  static const cacheKey = 'remote_config_cache_v1';
  static const fetchedAtKey = 'remote_config_fetched_at_v1';

  /// 이 시간 안에 이미 받았다면 다시 받지 않는다.
  static const minFetchInterval = Duration(hours: 6);

  /// 캐시가 이보다 오래되면 무시한다(서버가 사라져도 기능이 영구히 꺼지지 않도록).
  static const maxCacheAge = Duration(days: 14);

  static const requestTimeout = Duration(seconds: 5);

  RemoteConfig _current = RemoteConfig.defaults;
  DateTime? _gpuExpiresAt;
  final StreamController<RemoteConfig> _changes =
      StreamController<RemoteConfig>.broadcast();

  RemoteConfig get current => _current;

  /// Evaluate at each render boundary, including in a long-running app.
  bool get gpuOpsIosEnabled =>
      _current.gpuOpsIosEnabled &&
      _gpuExpiresAt != null &&
      DateTime.now().isBefore(_gpuExpiresAt!);
  Stream<RemoteConfig> get changes => _changes.stream;

  void _set(RemoteConfig value) {
    if (value == _current) return;
    _current = value;
    _changes.add(value);
  }

  /// 테스트용 초기화.
  void resetForTest([RemoteConfig value = RemoteConfig.defaults]) {
    _current = value;
    _gpuExpiresAt = DateTime.now().add(maxCacheAge);
  }

  /// 캐시된 값만 읽는다(네트워크 없음). 앱 시작 직후 호출한다.
  Future<void> loadCached({
    SharedPreferences? prefs,
    DateTime Function()? now,
  }) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final cached = _readCache(p, (now ?? DateTime.now)());
      final fetched = p.getInt(fetchedAtKey);
      _gpuExpiresAt = fetched == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(fetched).add(maxCacheAge);
      _set(cached ?? RemoteConfig.defaults);
    } catch (error, stack) {
      ErrorLogger.log('Remote config cache unreadable', error, stack);
      _gpuExpiresAt = null;
      _set(RemoteConfig.defaults);
    }
  }

  /// 원격에서 받아 검증하고 캐시한다. 실패하면 기존 값을 유지한다. 반환값은 갱신 여부.
  Future<bool> refresh({
    SharedPreferences? prefs,
    http.Client? client,
    String url = defaultUrl,
    DateTime Function()? now,
    bool force = false,
  }) async {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      ErrorLogger.log('Remote config URL rejected (https required)');
      return false;
    }
    final clock = now ?? DateTime.now;
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final lastMs = p.getInt(fetchedAtKey);
      if (!force && lastMs != null) {
        final age =
            clock().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
        if (!age.isNegative && age < minFetchInterval) return false;
      }
      final response = await httpClient.get(uri, headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      }).timeout(requestTimeout);
      if (response.statusCode != 200) {
        ErrorLogger.log('Remote config HTTP ${response.statusCode}');
        return false;
      }
      if (response.bodyBytes.length > RemoteConfig.maxBodyBytes) {
        ErrorLogger.log('Remote config body too large');
        return false;
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: false);
      final parsed = RemoteConfig.parse(body);
      if (parsed == null) {
        ErrorLogger.log('Remote config rejected: invalid format');
        return false;
      }
      await p.setString(cacheKey, body);
      await p.setInt(fetchedAtKey, clock().millisecondsSinceEpoch);
      _gpuExpiresAt = clock().add(maxCacheAge);
      _set(parsed);
      return true;
    } on Object catch (error, stack) {
      // 네트워크·형식 오류는 모두 무시하고 기존 값을 유지한다.
      ErrorLogger.log('Remote config refresh failed', error, stack);
      return false;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  RemoteConfig? _readCache(SharedPreferences p, DateTime now) {
    final body = p.getString(cacheKey);
    final fetchedMs = p.getInt(fetchedAtKey);
    if (body == null || fetchedMs == null) return null;
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(fetchedMs));
    if (age > maxCacheAge) return null;
    return RemoteConfig.parse(body);
  }
}
