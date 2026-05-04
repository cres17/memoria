import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'feature_flags_service.dart';

enum FullScreenAdTrigger { createFilter, applyOrExport }

/// Fullscreen ad service with feature-flag gating and timeout bypass.
/// Default: both flags OFF → all show() calls immediately return.
class FullScreenAdService {
  static const _timeoutMs = 3000; // 3 s timeout per spec (2500–3500 ms)

  // TODO(release): replace with real AdMob unit IDs from AdMob console
  // Current values are Google's official test IDs — using these in production violates AdMob policy
  static const _interstitialId  = 'ca-app-pub-3940256099942544/1033173712';
  static const _rewardedId      = 'ca-app-pub-3940256099942544/5224354917';

  final FeatureFlagsService _flags;
  FullScreenAdService(this._flags);

  /// Show ad for trigger. On any failure → immediately proceeds (bypass).
  Future<void> show(FullScreenAdTrigger trigger) async {
    final enabled = trigger == FullScreenAdTrigger.createFilter
        ? _flags.enableFullScreenAdsForCreateFilter
        : _flags.enableFullScreenAdsForApplyOrExport;

    if (!enabled) return; // feature flag OFF → bypass

    if (trigger == FullScreenAdTrigger.createFilter) {
      await _showRewarded();
    } else {
      await _showInterstitial();
    }
  }

  Future<void> _showRewarded() async {
    final completer = Completer<void>();

    final timer = Timer(
      const Duration(milliseconds: _timeoutMs),
      () { if (!completer.isCompleted) completer.complete(); },
    );

    RewardedAd.load(
      adUnitId: _rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          timer.cancel();
          ad.show(
            onUserEarnedReward: (_, __) {},
          );
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
          if (!completer.isCompleted) completer.complete(); // bypass
        },
      ),
    );

    return completer.future;
  }

  Future<void> _showInterstitial() async {
    final completer = Completer<void>();

    final timer = Timer(
      const Duration(milliseconds: _timeoutMs),
      () { if (!completer.isCompleted) completer.complete(); },
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
          if (!completer.isCompleted) completer.complete(); // bypass
        },
      ),
    );

    return completer.future;
  }
}
