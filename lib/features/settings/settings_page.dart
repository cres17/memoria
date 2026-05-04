import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    setStatusBarForDark();
  }

  @override
  void dispose() {
    setStatusBarForLight();
    super.dispose();
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.oceanMid,
        title: const Text('캐시 지우기', style: TextStyle(color: AppColors.textOnDark)),
        content: const Text('임시 파일을 모두 삭제합니다.', style: TextStyle(color: AppColors.textOnDarkSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textOnDarkTert)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.oceanFoam)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final temp = await getTemporaryDirectory();
      for (final e in temp.listSync()) {
        try { e.deleteSync(recursive: true); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('캐시가 삭제되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.oceanMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.check_rounded, color: Colors.transparent),
              title: const Text('한국어', style: TextStyle(color: AppColors.textOnDark)),
              trailing: ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (_, locale, __) => locale.languageCode == 'ko'
                    ? const Icon(Icons.check_rounded, color: AppColors.oceanFoam)
                    : const SizedBox.shrink(),
              ),
              onTap: () { setLocale('ko'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.check_rounded, color: Colors.transparent),
              title: const Text('English', style: TextStyle(color: AppColors.textOnDark)),
              trailing: ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (_, locale, __) => locale.languageCode == 'en'
                    ? const Icon(Icons.check_rounded, color: AppColors.oceanFoam)
                    : const SizedBox.shrink(),
              ),
              onTap: () { setLocale('en'); Navigator.pop(context); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'Memoria',
      applicationVersion: '1.0.0',
    );
  }

  void _onVersionTap() {
    if (!kDebugMode) return;
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      hapticHeavy();
      context.pushNamed('devPanel');
    } else if (_versionTapCount >= 4) {
      hapticLight();
      final remaining = 7 - _versionTapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '개발자 모드까지 $remaining번 더 탭하세요',
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
          icon: Icon(backIcon(), color: AppColors.textOnDark),
          onPressed: () => context.pop(),
        ),
        title: Text(
          S.get('settings.title'),
          style: TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textOnDark,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(title: '저장소'),
          _SettingCard(
            children: [
              const _SettingRow(
                icon: Icons.folder_outlined,
                title: '필터 저장 위치',
                subtitle: '앱 내부 저장소',
                onTap: null,
              ),
              const _Divider(),
              _SettingRow(
                icon: Icons.delete_sweep_outlined,
                title: '캐시 지우기',
                onTap: _clearCache,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: '언어'),
          _SettingCard(
            children: [
              ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (_, locale, __) => _SettingRow(
                  icon: Icons.language_rounded,
                  title: '언어',
                  subtitle: locale.languageCode == 'ko' ? '한국어' : 'English',
                  onTap: () => _showLanguagePicker(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: '화질'),
          const _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.high_quality_rounded,
                title: '내보내기 품질',
                subtitle: 'JPEG 95%',
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: '앱 정보'),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: '오픈소스 라이선스',
                onTap: _showLicenses,
              ),
              const _Divider(),
              GestureDetector(
                onTap: _onVersionTap,
                child: const _SettingRow(
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
          fontFamily: 'NotoSerif',
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
                      fontFamily: 'NotoSerif',
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
                        fontFamily: 'NotoSerif',
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
