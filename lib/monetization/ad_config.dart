import 'package:flutter/foundation.dart';

/// 광고 단위 ID. 빌드 시 `--dart-define`으로 바꾼다. 값이 없으면 Google 공식 샘플 ID를 쓴다.
///
/// 플랫폼마다 ID가 다르다(AdMob 콘솔에서 Android/iOS 앱을 따로 등록).
///   --dart-define=ADMOB_BANNER_ID_ANDROID=ca-app-pub-xxx/yyy
///   --dart-define=ADMOB_BANNER_ID_IOS=ca-app-pub-xxx/yyy
///   (INTERSTITIAL, REWARDED 도 동일)
/// 앱 ID는 Android는 `ADMOB_ANDROID_APP_ID` 환경변수(Gradle), iOS는 `ADMOB_IOS_APP_ID`
/// 빌드 설정(`ios/Flutter/AdMob.xcconfig`)으로 넣는다.
class AdConfig {
  AdConfig._();

  // Google 공식 샘플 광고 단위 ID (출처: developers.google.com/admob 의 Flutter/iOS 테스트 광고 문서).
  static const _sampleBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _sampleBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _sampleInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _sampleInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';
  static const _sampleRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const _sampleRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static const _bannerAndroid = String.fromEnvironment(
      'ADMOB_BANNER_ID_ANDROID',
      defaultValue: _sampleBannerAndroid);
  static const _bannerIos = String.fromEnvironment('ADMOB_BANNER_ID_IOS',
      defaultValue: _sampleBannerIos);
  static const _interstitialAndroid = String.fromEnvironment(
      'ADMOB_INTERSTITIAL_ID_ANDROID',
      defaultValue: _sampleInterstitialAndroid);
  static const _interstitialIos = String.fromEnvironment(
      'ADMOB_INTERSTITIAL_ID_IOS',
      defaultValue: _sampleInterstitialIos);
  static const _rewardedAndroid = String.fromEnvironment(
      'ADMOB_REWARDED_ID_ANDROID',
      defaultValue: _sampleRewardedAndroid);
  static const _rewardedIos = String.fromEnvironment('ADMOB_REWARDED_ID_IOS',
      defaultValue: _sampleRewardedIos);

  static bool get _ios =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String get bannerId => _ios ? _bannerIos : _bannerAndroid;
  static String get interstitialId =>
      _ios ? _interstitialIos : _interstitialAndroid;
  static String get rewardedId => _ios ? _rewardedIos : _rewardedAndroid;

  static bool isSampleId(String id) =>
      id.startsWith('ca-app-pub-3940256099942544/');

  /// 현재 플랫폼에서 하나라도 샘플 ID를 쓰고 있으면 true.
  static bool get usesSampleIds =>
      isSampleId(bannerId) ||
      isSampleId(interstitialId) ||
      isSampleId(rewardedId);

  /// 릴리스 빌드에서 샘플 ID가 남아 있으면 광고를 요청하지 않는다.
  /// (샘플 ID로 실제 사용자에게 광고를 내보내면 AdMob 정책 위반이다.)
  static bool get adsAllowed => !(kReleaseMode && usesSampleIds);
}
