import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_consent_service.dart';
import 'feature_flags_service.dart';

enum FullScreenAdTrigger { createFilter, applyOrExport }

/// Fullscreen ad service with feature-flag gating and timeout bypass.
/// Default: both fullscreen flags are off, so show() calls return immediately.
class FullScreenAdService {
  static const _timeoutMs = 3000;

  final FeatureFlagsService _flags;
  FullScreenAdService(this._flags);

  /// Show ad for trigger. On any failure, immediately proceeds.
  Future<void> show(FullScreenAdTrigger trigger) async {
    final enabled = trigger == FullScreenAdTrigger.createFilter
        ? _flags.enableFullScreenAdsForCreateFilter
        : _flags.enableFullScreenAdsForApplyOrExport;

    if (kIsWeb) return;
    if (!enabled) return;
    if (!await _hasNetwork()) return;
    if (!await AdConsentService.instance.prepare(adsEnabled: true)) return;

    if (trigger == FullScreenAdTrigger.createFilter) {
      await _showRewarded();
    } else {
      await _showInterstitial();
    }
  }

  Future<bool> _hasNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
    } on Object {
      // Ads are optional; connectivity plugin failures must never block editing.
      return false;
    }
  }

  Future<void> _showRewarded() async {
    final completer = Completer<void>();

    final timer = Timer(
      const Duration(milliseconds: _timeoutMs),
      () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    RewardedAd.load(
      adUnitId: AdConfig.rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          timer.cancel();
          ad.show(onUserEarnedReward: (_, __) {});
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
          );
        },
        onAdFailedToLoad: (_) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    return completer.future;
  }

  Future<void> _showInterstitial() async {
    final completer = Completer<void>();

    final timer = Timer(
      const Duration(milliseconds: _timeoutMs),
      () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    InterstitialAd.load(
      adUnitId: AdConfig.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          timer.cancel();
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (_) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    return completer.future;
  }
}
