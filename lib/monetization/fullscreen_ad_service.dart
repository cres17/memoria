import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'feature_flags_service.dart';

enum FullScreenAdTrigger { createFilter, applyOrExport }

/// Fullscreen ad service with feature-flag gating and timeout bypass.
/// Default: both fullscreen flags are off, so show() calls return immediately.
class FullScreenAdService {
  static const _timeoutMs = 3000;

  // TODO(release): replace with real AdMob unit IDs from AdMob console.
  static const _interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const _rewardedId = 'ca-app-pub-3940256099942544/5224354917';

  final FeatureFlagsService _flags;
  FullScreenAdService(this._flags);

  /// Show ad for trigger. On any failure, immediately proceeds.
  Future<void> show(FullScreenAdTrigger trigger) async {
    final enabled = trigger == FullScreenAdTrigger.createFilter
        ? _flags.enableFullScreenAdsForCreateFilter
        : _flags.enableFullScreenAdsForApplyOrExport;

    if (!enabled) return;
    if (!await _hasNetwork()) return;

    if (trigger == FullScreenAdTrigger.createFilter) {
      await _showRewarded();
    } else {
      await _showInterstitial();
    }
  }

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(milliseconds: 800));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
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
      adUnitId: _rewardedId,
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
      adUnitId: _interstitialId,
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
