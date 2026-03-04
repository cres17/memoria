import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../monetization/feature_flags_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  FeatureFlagsService? _flags;
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await FeatureFlagsService.create();
    if (mounted) setState(() => _flags = f);
  }

  void _onVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      HapticFeedback.heavyImpact();
      context.pushNamed('devPanel');
    } else if (_versionTapCount >= 4) {
      HapticFeedback.selectionClick();
      final remaining = 7 - _versionTapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '개발자 모드까지 $remaining번 더 탭하세요',
            style: const TextStyle(fontFamily: 'Pretendard'),
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.oceanNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      appBar: AppBar(
        backgroundColor: AppColors.oceanDeep,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textOnDark),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '설정',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textOnDark,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(title: '저장소'),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.folder_outlined,
                title: '필터 저장 위치',
                subtitle: '앱 내부 저장소',
                onTap: () {},
              ),
              const _Divider(),
              _SettingRow(
                icon: Icons.delete_sweep_outlined,
                title: '캐시 지우기',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '화질'),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.high_quality_rounded,
                title: '내보내기 품질',
                subtitle: 'JPEG 90%',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '앱 정보'),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: '오픈소스 라이선스',
                onTap: () {},
              ),
              const _Divider(),
              GestureDetector(
                onTap: _onVersionTap,
                child: _SettingRow(
                  icon: Icons.apps_rounded,
                  title: '버전',
                  subtitle: '1.0.0 (1)',
                  onTap: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnDarkTert,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.textOnDarkSub, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textOnDark,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        color: AppColors.textOnDarkTert,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textOnDarkTert, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: AppColors.oceanNavy),
    );
  }
}
