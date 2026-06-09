import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Feature flags stored locally via SharedPreferences.
/// All fullscreen-ad flags default to OFF per spec.
/// Banner ad is always disabled on web (kIsWeb) regardless of the stored flag.
class FeatureFlagsService {
  static const _keyBanner         = 'flag_banner_ad';
  static const _keyFullCreateFilter = 'flag_fullscreen_create';
  static const _keyFullApplyExport  = 'flag_fullscreen_apply_export';

  final SharedPreferences _prefs;
  FeatureFlagsService(this._prefs);

  static Future<FeatureFlagsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FeatureFlagsService(prefs);
  }

  // ── Getters ──────────────────────────────────────────────────
  bool get enableBannerAd =>
      !kIsWeb && (_prefs.getBool(_keyBanner) ?? true); // web always OFF

  bool get enableFullScreenAdsForCreateFilter =>
      _prefs.getBool(_keyFullCreateFilter) ?? false; // default OFF

  bool get enableFullScreenAdsForApplyOrExport =>
      _prefs.getBool(_keyFullApplyExport) ?? false;  // default OFF

  // ── Setters ──────────────────────────────────────────────────
  Future<void> setBannerAd(bool value) =>
      _prefs.setBool(_keyBanner, value);

  Future<void> setFullScreenAdsForCreateFilter(bool value) =>
      _prefs.setBool(_keyFullCreateFilter, value);

  Future<void> setFullScreenAdsForApplyOrExport(bool value) =>
      _prefs.setBool(_keyFullApplyExport, value);

  Map<String, bool> toMap() => {
    'enableBannerAd':                       enableBannerAd,
    'enableFullScreenAdsForCreateFilter':   enableFullScreenAdsForCreateFilter,
    'enableFullScreenAdsForApplyOrExport':  enableFullScreenAdsForApplyOrExport,
  };
}
