import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/theme/app_colors.dart';
import 'feature_flags_service.dart';

/// Always-on banner ad widget (bottom or top).
/// Silently hides itself on load failure.
class BannerAdWidget extends StatefulWidget {
  final FeatureFlagsService flags;
  const BannerAdWidget({super.key, required this.flags});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  // TODO(release): replace with real AdMob banner unit ID from AdMob console.
  // Current value is Google's official test ID — using this in production violates AdMob policy.
  static const _adUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const _isTestAdId = true; // flip to false after replacing _adUnitId

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.flags.enableBannerAd) _loadAd();
  }

  Future<void> _loadAd() async {
    if (kIsWeb) return;
    assert(!kReleaseMode || !_isTestAdId,
        'Replace _adUnitId with a real AdMob ID before release.');
    if (!await _hasNetwork()) return;

    _ad = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          // Spec: bypass silently on failure
        },
      ),
    )..load();
  }

  Future<bool> _hasNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
    } on Object {
      // Banner availability is best-effort and never blocks app content.
      return false;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !widget.flags.enableBannerAd || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: AppColors.oceanMid,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
