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

  // Test ad unit — replace with real IDs in production
  static const _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  void initState() {
    super.initState();
    if (widget.flags.enableBannerAd) _loadAd();
  }

  void _loadAd() {
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

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.flags.enableBannerAd || !_loaded || _ad == null) {
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
