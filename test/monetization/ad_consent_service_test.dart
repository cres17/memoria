import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/monetization/ad_config.dart';
import 'package:memoria/monetization/ad_consent_service.dart';

class _FakeConsent implements ConsentGateway {
  _FakeConsent({this.canRequest = true, this.optionsRequired = false});

  final bool canRequest;
  final bool optionsRequired;
  final calls = <String>[];

  @override
  Future<void> gatherConsent() async => calls.add('gather');

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequestAds');
    return canRequest;
  }

  @override
  Future<bool> privacyOptionsRequired() async => optionsRequired;

  @override
  Future<void> showPrivacyOptions() async => calls.add('options');
}

void main() {
  AdConsentService build(
    _FakeConsent consent,
    List<String> log, {
    bool ios = false,
    Future<void> Function()? init,
  }) =>
      AdConsentService(
        consent: consent,
        isIos: () => ios,
        requestTracking: () async {
          log.add('att');
          return 'denied';
        },
        initializeAds: init ?? () async => log.add('init'),
      );

  test('광고가 꺼져 있으면 동의 확인도 SDK 초기화도 하지 않는다', () async {
    final consent = _FakeConsent();
    final log = <String>[];
    final service = build(consent, log);
    expect(await service.prepare(adsEnabled: false), isFalse);
    expect(consent.calls, isEmpty);
    expect(log, isEmpty);
  });

  test('동의가 허용되면 동의 확인 뒤에 SDK를 한 번만 초기화한다', () async {
    final consent = _FakeConsent();
    final log = <String>[];
    final service = build(consent, log);
    expect(await service.prepare(adsEnabled: true), isTrue);
    expect(await service.prepare(adsEnabled: true), isTrue);
    expect(consent.calls, ['gather', 'canRequestAds']);
    expect(log, ['init']);
  });

  test('동의가 광고 요청을 허용하지 않으면 SDK를 시작하지 않는다', () async {
    final consent = _FakeConsent(canRequest: false);
    final log = <String>[];
    final service = build(consent, log);
    expect(await service.prepare(adsEnabled: true), isFalse);
    expect(log, isEmpty);
    expect(service.adsInitialized, isFalse);
  });

  test('iOS는 동의 양식 전에 ATT를 요청하고 거부해도 계속 진행한다', () async {
    final consent = _FakeConsent();
    final log = <String>[];
    final service = build(consent, log, ios: true);
    expect(await service.prepare(adsEnabled: true), isTrue);
    expect(log, ['att', 'init']);
  });

  test('동의 확인이 예외를 던져도 앱은 계속 동작한다', () async {
    final log = <String>[];
    final service =
        build(_FakeConsent(), log, init: () async => throw StateError('sdk'));
    expect(await service.prepare(adsEnabled: true), isFalse);
  });

  test('개인정보 옵션 항목은 광고를 한 번도 쓰지 않았으면 숨긴다', () async {
    final log = <String>[];
    final service = build(_FakeConsent(optionsRequired: true), log);
    expect(await service.privacyOptionsRequired(), isFalse);
    await service.prepare(adsEnabled: true);
    expect(await service.privacyOptionsRequired(), isTrue);
  });

  test('플랫폼별 샘플 ID와 릴리스 차단 규칙', () {
    expect(
        AdConfig.isSampleId('ca-app-pub-3940256099942544/6300978111'), isTrue);
    expect(
        AdConfig.isSampleId('ca-app-pub-1234567890123456/1111111111'), isFalse);
    // 테스트 모드(디버그)에서는 샘플 ID여도 광고를 막지 않는다.
    expect(AdConfig.adsAllowed, isTrue);
  });
}
