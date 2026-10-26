import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/remote_config/remote_config.dart';

/// Feature flags stored locally via SharedPreferences.
/// All ad flags default to OFF and are disabled in release builds.
/// v1 ships ad-free; the flags exist only for debug integration testing.
class FeatureFlagsService {
  static const _keyBanner = 'flag_banner_ad';
  static const _keyFullCreateFilter = 'flag_fullscreen_create';
  static const _keyFullApplyExport = 'flag_fullscreen_apply_export';

  final SharedPreferences _prefs;
  FeatureFlagsService(this._prefs);

  static Future<FeatureFlagsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FeatureFlagsService(prefs);
  }

  // ── Getters ──────────────────────────────────────────────────
  // 원격 킬 스위치(ads)가 켜지면 저장된 값과 관계없이 모든 광고를 끈다.
  bool get _adsKilled => RemoteConfigService.instance.current.adsDisabled;

  bool get enableBannerAd =>
      !kIsWeb &&
      !kReleaseMode &&
      !_adsKilled &&
      (_prefs.getBool(_keyBanner) ?? false);

  bool get enableFullScreenAdsForCreateFilter =>
      !kReleaseMode &&
      !_adsKilled &&
      (_prefs.getBool(_keyFullCreateFilter) ?? false);

  bool get enableFullScreenAdsForApplyOrExport =>
      !kReleaseMode &&
      !_adsKilled &&
      (_prefs.getBool(_keyFullApplyExport) ?? false);

  // ── Setters ──────────────────────────────────────────────────
  Future<void> setBannerAd(bool value) => _prefs.setBool(_keyBanner, value);

  Future<void> setFullScreenAdsForCreateFilter(bool value) =>
      _prefs.setBool(_keyFullCreateFilter, value);

  Future<void> setFullScreenAdsForApplyOrExport(bool value) =>
      _prefs.setBool(_keyFullApplyExport, value);

  Map<String, bool> toMap() => {
    'enableBannerAd': enableBannerAd,
    'enableFullScreenAdsForCreateFilter': enableFullScreenAdsForCreateFilter,
    'enableFullScreenAdsForApplyOrExport': enableFullScreenAdsForApplyOrExport,
  };
}
