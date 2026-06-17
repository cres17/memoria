import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ai/ai_manager.dart';
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
  ModelState _colorModelState = const ModelState(status: ModelStatus.notDownloaded);
  String _exportFormat = 'jpeg';

  @override
  void initState() {
    super.initState();
    setStatusBarForDark();
    _refreshModelState();
    _loadSettings();
    AiManager.instance.addListener(_onModelStateChanged);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _exportFormat = prefs.getString('settings_export_format') ?? 'jpeg';
      });
    }
  }

  Future<void> _setExportFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_export_format', format);
    if (mounted) {
      setState(() {
        _exportFormat = format;
      });
    }
  }

  void _refreshModelState() {
    setState(() {
      _colorModelState = AiManager.instance.stateOf(kModelColorTransfer.key);
    });
  }

  void _onModelStateChanged() => _refreshModelState();

  @override
  void dispose() {
    AiManager.instance.removeListener(_onModelStateChanged);
    setStatusBarForLight();
    super.dispose();
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.oceanMid,
        title: Text(S.get('settings.clear_cache_title'), style: const TextStyle(color: AppColors.textOnDark)),
        content: Text(S.get('settings.clear_cache_body'), style: const TextStyle(color: AppColors.textOnDarkSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.get('settings.clear_cache_cancel'), style: const TextStyle(color: AppColors.textOnDarkTert)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.get('settings.clear_cache_confirm'), style: const TextStyle(color: AppColors.oceanFoam)),
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
          SnackBar(
            content: Text(S.get('settings.clear_cache_done')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.get('settings.clear_cache_fail')}: $e'), behavior: SnackBarBehavior.floating),
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

  void _showExportFormatPicker() {
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
            _buildFormatTile('jpeg', 'JPEG (Standard)'),
            _buildFormatTile('png', 'PNG (Lossless)'),
            _buildFormatTile('webp', 'WebP (Lossy 90%)'),
            _buildFormatTile('raw', 'RAW (DNG 100% Meta Preservation)'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatTile(String formatKey, String label) {
    return ListTile(
      leading: const Icon(Icons.check_rounded, color: Colors.transparent),
      title: Text(label, style: const TextStyle(color: AppColors.textOnDark)),
      trailing: _exportFormat == formatKey
          ? const Icon(Icons.check_rounded, color: AppColors.oceanFoam)
          : const SizedBox.shrink(),
      onTap: () {
        _setExportFormat(formatKey);
        Navigator.pop(context);
      },
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
            S.get('settings.dev_hint').replaceAll('{n}', '$remaining'),
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
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, __, ___) => _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
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
          _SectionHeader(title: S.get('settings.storage')),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.folder_outlined,
                title: S.get('settings.filter_location'),
                subtitle: S.get('settings.filter_loc_sub'),
                onTap: null,
              ),
              const _Divider(),
              _SettingRow(
                icon: Icons.delete_sweep_outlined,
                title: S.get('settings.clear_cache'),
                onTap: _clearCache,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: S.get('settings.language')),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.language_rounded,
                title: S.get('settings.language'),
                subtitle: localeNotifier.value.languageCode == 'ko'
                    ? S.get('settings.lang_ko')
                    : S.get('settings.lang_en'),
                onTap: () => _showLanguagePicker(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: S.get('settings.quality')),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.high_quality_rounded,
                title: S.get('settings.export_quality'),
                subtitle: S.get('settings.export_quality_sub'),
                onTap: null,
              ),
              const _Divider(),
              _SettingRow(
                icon: Icons.image_outlined,
                title: S.get('settings.export_format'),
                subtitle: _exportFormat.toUpperCase(),
                onTap: () => _showExportFormatPicker(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: S.get('settings.ai')),
          _SettingCard(
            children: [
              _AiModelRow(
                icon: Icons.palette_outlined,
                title: S.get('settings.ai_color'),
                subtitle: S.get('settings.ai_color_sub'),
                state: _colorModelState,
                onDownload: kModelColorTransfer.url.isEmpty
                    ? null
                    : () => AiManager.instance.preload(kModelColorTransfer),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: S.get('settings.about')),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: S.get('settings.licenses'),
                onTap: _showLicenses,
              ),
              const _Divider(),
              GestureDetector(
                onTap: _onVersionTap,
                child: _SettingRow(
                  icon: Icons.apps_rounded,
                  title: S.get('settings.version'),
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

class _AiModelRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ModelState state;
  final VoidCallback? onDownload;

  const _AiModelRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                Text(title,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textOnDark,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 13,
                      color: AppColors.textOnDarkTert,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusWidget(),
        ],
      ),
    );
  }

  Widget _statusWidget() {
    switch (state.status) {
      case ModelStatus.ready:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.oceanTeal.withOpacity(0.3),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            S.get('settings.ai_ready'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.oceanFoam,
            ),
          ),
        );
      case ModelStatus.downloading:
        return SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(state.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.oceanFoam,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: AppColors.oceanNavy,
                color: AppColors.oceanFoam,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          ),
        );
      case ModelStatus.error:
        return TextButton(
          onPressed: onDownload,
          style: TextButton.styleFrom(
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
          child: Text(S.get('settings.ai_error')),
        );
      case ModelStatus.notDownloaded:
        if (onDownload == null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'N/A',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textOnDarkTert,
              ),
            ),
          );
        }
        return TextButton(
          onPressed: onDownload,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.oceanFoam,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
          child: Text(S.get('settings.ai_download')),
        );
    }
  }
}
