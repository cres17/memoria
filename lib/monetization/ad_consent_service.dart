import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../engine/engine_channel.dart';
import 'ad_config.dart';

/// 광고 초기화 전 동의를 확인한다.
///
/// 1) iOS: 앱 추적 투명성(ATT) 요청 — 광고가 켜져 있을 때만.
/// 2) 전 플랫폼: Google UMP 동의 양식(필요한 지역에서만 표시됨).
/// 3) 동의 결과가 광고 요청을 허용할 때만 `MobileAds.initialize()`.
///
/// 광고 기능이 꺼져 있으면(기본값) 아무것도 하지 않는다.
class AdConsentService {
  AdConsentService({
    ConsentGateway? consent,
    Future<void> Function()? initializeAds,
    Future<String?> Function()? requestTracking,
    bool Function()? isIos,
  })  : _consent = consent ?? const UmpConsentGateway(),
        _initializeAds = initializeAds ?? _defaultInitialize,
        _requestTracking =
            requestTracking ?? EngineChannel.requestTrackingAuthorization,
        _isIos = isIos ?? (() => defaultTargetPlatform == TargetPlatform.iOS);

  static final AdConsentService instance = AdConsentService();

  final ConsentGateway _consent;
  final Future<void> Function() _initializeAds;
  final Future<String?> Function() _requestTracking;
  final bool Function() _isIos;

  bool _initialized = false;
  bool get adsInitialized => _initialized;

  static Future<void> _defaultInitialize() async {
    await MobileAds.instance.initialize();
  }

  /// 동의를 확인하고 가능하면 광고 SDK를 초기화한다. 광고 SDK를 쓸 수 있으면 true.
  Future<bool> prepare({required bool adsEnabled}) async {
    if (_initialized) return true;
    if (!adsEnabled || !AdConfig.adsAllowed) return false;

    try {
      if (_isIos()) {
        // 사용자가 거부해도 광고는 비개인화로 나갈 수 있으므로 결과로 중단하지 않는다.
        await _requestTracking();
      }
      await _consent.gatherConsent();
      if (!await _consent.canRequestAds()) return false;
      await _initializeAds();
      _initialized = true;
      return true;
    } on Object {
      // 광고는 부가 기능이다. 동의 확인 실패가 편집을 막으면 안 된다.
      return false;
    }
  }

  /// 설정 화면의 "광고 개인정보 설정" 항목을 보여야 하는지.
  /// 동의 확인을 한 번도 하지 않았다면(광고 미사용) 항상 false.
  Future<bool> privacyOptionsRequired() async {
    if (!_initialized) return false;
    try {
      return await _consent.privacyOptionsRequired();
    } on Object {
      return false;
    }
  }

  Future<void> showPrivacyOptions() => _consent.showPrivacyOptions();
}

/// UMP SDK 접근을 감싼 인터페이스. 테스트에서 대체한다.
abstract class ConsentGateway {
  Future<void> gatherConsent();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
}

class UmpConsentGateway implements ConsentGateway {
  const UmpConsentGateway();

  @override
  Future<void> gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {
            if (!done.isCompleted) done.complete();
          });
        } on Object {
          if (!done.isCompleted) done.complete();
        }
      },
      (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
  }
}
