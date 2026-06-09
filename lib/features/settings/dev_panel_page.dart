import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../monetization/feature_flags_service.dart';

/// Hidden developer panel — accessible by tapping version 7× in Settings.
/// Allows toggling feature flags (ad controls etc.).
class DevPanelPage extends StatefulWidget {
  const DevPanelPage({super.key});

  @override
  State<DevPanelPage> createState() => _DevPanelPageState();
}

class _DevPanelPageState extends State<DevPanelPage> {
  FeatureFlagsService? _flags;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await FeatureFlagsService.create();
    if (mounted) setState(() => _flags = f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      appBar: AppBar(
        backgroundColor: AppColors.oceanDeep,
        leading: IconButton(
          icon: Icon(backIcon(), color: AppColors.textOnDark),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentWarning.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'DEV',
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentWarning,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '개발자 패널',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnDark,
              ),
            ),
          ],
        ),
      ),
      body: _flags == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.oceanFoam))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _warningBanner(),
                const SizedBox(height: 20),
                _sectionHeader('광고 Feature Flags'),
                _flagCard([
                  _FlagRow(
                    title: '배너 광고',
                    subtitle: '상단/하단 상시 노출 (기본: ON)',
                    value: _flags!.enableBannerAd,
                    onChanged: (v) async {
                      await _flags!.setBannerAd(v);
                      await _load();
                    },
                  ),
                  _FlagRow(
                    title: '풀스크린: 필터 생성',
                    subtitle: 'CreateFilter 시 Rewarded 광고 (기본: OFF)',
                    value: _flags!.enableFullScreenAdsForCreateFilter,
                    onChanged: (v) async {
                      await _flags!.setFullScreenAdsForCreateFilter(v);
                      await _load();
                    },
                  ),
                  _FlagRow(
                    title: '풀스크린: 적용/내보내기',
                    subtitle: 'ApplyFilter/Export 시 Interstitial (기본: OFF)',
                    value: _flags!.enableFullScreenAdsForApplyOrExport,
                    onChanged: (v) async {
                      await _flags!.setFullScreenAdsForApplyOrExport(v);
                      await _load();
                    },
                  ),
                ]),
                const SizedBox(height: 20),
                _sectionHeader('현재 Flag 상태'),
                _flagStateCard(),
              ],
            ),
    );
  }

  Widget _warningBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentWarning.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.accentWarning.withValues(alpha:0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.accentWarning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '이 패널은 개발/테스트 전용입니다. 배포 전 접근을 차단하세요.',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 13,
                color: AppColors.accentWarning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'NotoSerif',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnDarkTert,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _flagCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Column(children: children),
    );
  }

  Widget _flagStateCard() {
    final map = _flags!.toMap();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.oceanNavy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.key,
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    color: AppColors.textOnDarkTert,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: e.value
                      ? AppColors.accentSuccess.withValues(alpha:0.15)
                      : AppColors.accentError.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.value ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: e.value
                        ? AppColors.accentSuccess
                        : AppColors.accentError,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FlagRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    color: AppColors.textOnDarkTert,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.oceanFoam,
            activeTrackColor: AppColors.oceanTeal.withValues(alpha:0.4),
            inactiveThumbColor: AppColors.textOnDarkTert,
            inactiveTrackColor: AppColors.oceanNavy,
          ),
        ],
      ),
    );
  }
}
