import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memoria/core/remote_config/remote_config.dart';
import 'package:memoria/monetization/feature_flags_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _body({bool sky = false, bool raw = false, bool batch = false, bool ads = false}) =>
    jsonEncode({
      'schema': 1,
      'disabled': {'sky': sky, 'raw': raw, 'batch': batch, 'ads': ads},
    });

void main() {
  late RemoteConfigService service;
  final t0 = DateTime(2026, 10, 1, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = RemoteConfigService.instance..resetForTest();
  });

  group('parse', () {
    test('정상 응답', () {
      final c = RemoteConfig.parse(_body(sky: true, ads: true))!;
      expect(c.skyDisabled, isTrue);
      expect(c.adsDisabled, isTrue);
      expect(c.rawDisabled, isFalse);
      expect(c.batchDisabled, isFalse);
    });

    test('빠진 키는 켜짐, 알 수 없는 키는 무시', () {
      final c = RemoteConfig.parse(
          '{"schema":1,"disabled":{"sky":true,"future":true}}')!;
      expect(c.skyDisabled, isTrue);
      expect(c.rawDisabled, isFalse);
    });

    test('형식 오류는 모두 거부', () {
      expect(RemoteConfig.parse('not json'), isNull);
      expect(RemoteConfig.parse('[]'), isNull);
      expect(RemoteConfig.parse('{"schema":2,"disabled":{}}'), isNull);
      expect(RemoteConfig.parse('{"schema":1}'), isNull);
      expect(RemoteConfig.parse('{"schema":1,"disabled":[]}'), isNull);
      expect(RemoteConfig.parse('{"schema":1,"disabled":{"sky":"yes"}}'), isNull);
      expect(RemoteConfig.parse('{"schema":1,"disabled":{"sky":1}}'), isNull);
    });

    test('상한을 넘는 본문은 거부', () {
      final big = '{"schema":1,"disabled":{},"pad":"${'a' * 20000}"}';
      expect(RemoteConfig.parse(big), isNull);
    });
  });

  group('refresh', () {
    test('성공하면 적용하고 캐시한다', () async {
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient((_) async => http.Response(_body(sky: true), 200));
      final ok = await service.refresh(
          prefs: prefs, client: client, url: 'https://example.com/f.json', now: () => t0);
      expect(ok, isTrue);
      expect(service.current.skyDisabled, isTrue);
      expect(prefs.getString(RemoteConfigService.cacheKey), isNotNull);
    });

    test('실패(네트워크 오류·404·잘못된 JSON)는 기존 값을 유지한다', () async {
      final prefs = await SharedPreferences.getInstance();
      service.resetForTest(const RemoteConfig(rawDisabled: true));
      for (final client in [
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient((_) async => http.Response('nope', 404)),
        MockClient((_) async => http.Response('{broken', 200)),
        MockClient((_) async => http.Response('{"schema":1,"disabled":{"sky":"x"}}', 200)),
      ]) {
        final ok = await service.refresh(
            prefs: prefs,
            client: client,
            url: 'https://example.com/f.json',
            now: () => t0,
            force: true);
        expect(ok, isFalse);
        expect(service.current.rawDisabled, isTrue);
        expect(prefs.getString(RemoteConfigService.cacheKey), isNull);
      }
    });

    test('https가 아니면 요청하지 않는다', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(_body(), 200);
      });
      expect(
          await service.refresh(
              client: client, url: 'http://example.com/f.json', now: () => t0),
          isFalse);
      expect(await service.refresh(client: client, url: '', now: () => t0), isFalse);
      expect(called, isFalse);
    });

    test('최소 간격 안에서는 다시 받지 않는다', () async {
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(_body(), 200);
      });
      Future<bool> go(DateTime at, {bool force = false}) => service.refresh(
          prefs: prefs,
          client: client,
          url: 'https://example.com/f.json',
          now: () => at,
          force: force);
      expect(await go(t0), isTrue);
      expect(await go(t0.add(const Duration(hours: 1))), isFalse);
      expect(calls, 1);
      expect(await go(t0.add(const Duration(hours: 7))), isTrue);
      expect(calls, 2);
    });

    test('본문이 상한을 넘으면 거부', () async {
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient((_) async =>
          http.Response('{"schema":1,"disabled":{},"pad":"${'a' * 20000}"}', 200));
      expect(
          await service.refresh(
              prefs: prefs,
              client: client,
              url: 'https://example.com/f.json',
              now: () => t0),
          isFalse);
    });
  });

  group('loadCached', () {
    test('유효한 캐시를 읽는다', () async {
      SharedPreferences.setMockInitialValues({
        RemoteConfigService.cacheKey: _body(batch: true),
        RemoteConfigService.fetchedAtKey: t0.millisecondsSinceEpoch,
      });
      await service.loadCached(now: () => t0.add(const Duration(days: 1)));
      expect(service.current.batchDisabled, isTrue);
    });

    test('14일이 지난 캐시는 무시한다(fail-open)', () async {
      SharedPreferences.setMockInitialValues({
        RemoteConfigService.cacheKey: _body(batch: true),
        RemoteConfigService.fetchedAtKey: t0.millisecondsSinceEpoch,
      });
      await service.loadCached(now: () => t0.add(const Duration(days: 15)));
      expect(service.current, RemoteConfig.defaults);
    });

    test('손상된 캐시는 기본값', () async {
      SharedPreferences.setMockInitialValues({
        RemoteConfigService.cacheKey: '{oops',
        RemoteConfigService.fetchedAtKey: t0.millisecondsSinceEpoch,
      });
      await service.loadCached(now: () => t0);
      expect(service.current, RemoteConfig.defaults);
    });
  });

  test('ads 킬 스위치는 저장된 광고 설정을 무시하고 끈다', () async {
    SharedPreferences.setMockInitialValues({
      'flag_banner_ad': true,
      'flag_fullscreen_create': true,
      'flag_fullscreen_apply_export': true,
    });
    final flags = FeatureFlagsService(await SharedPreferences.getInstance());
    expect(flags.enableFullScreenAdsForCreateFilter, isTrue);
    service.resetForTest(const RemoteConfig(adsDisabled: true));
    expect(flags.enableBannerAd, isFalse);
    expect(flags.enableFullScreenAdsForCreateFilter, isFalse);
    expect(flags.enableFullScreenAdsForApplyOrExport, isFalse);
  });

  test('저장소의 config/remote_flags.json은 유효하고 모두 켜짐 상태', () {
    // 이 테스트는 파일을 읽어 앱이 실제로 받을 형식과 맞는지 확인한다.
    final text = _readRepoFlags();
    final c = RemoteConfig.parse(text);
    expect(c, isNotNull);
    expect(c, RemoteConfig.defaults);
  });
}

String _readRepoFlags() => File('config/remote_flags.json').readAsStringSync();
