import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/error/error_handler.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/services/export_preferences.dart';
import '../../core/services/media_permission_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_index_recovery_service.dart';
import '../../data/repositories/preferences_recovery_service.dart';
import '../../engine/engine_channel.dart';
import 'settings_recovery_section.dart';

class SettingsPage extends StatefulWidget {
  final PreferencesRecoveryService? preferencesRecovery;
  final FilterIndexRecoveryService? filterIndexRecovery;
  final SettingsRecoveryController? recoveryController;

  const SettingsPage({
    super.key,
    this.preferencesRecovery,
    this.filterIndexRecovery,
    this.recoveryController,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _versionTapCount = 0;
  ExportFormat _exportFormat = ExportFormat.jpeg;
  int _exportQuality = 95;
  bool _webpSupported = false;
  late final SettingsRecoveryController _recoveryController;

  @override
  void initState() {
    super.initState();
    _recoveryController = widget.recoveryController ??
        ServiceSettingsRecoveryController(
          preferences:
              widget.preferencesRecovery ?? PreferencesRecoveryService(),
          filterIndex:
              widget.filterIndexRecovery ?? FilterIndexRecoveryService(),
        );
    setStatusBarForDark();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final webpSupported =
        Platform.isIOS && await EngineChannel.supportsWebPEncoding();
    final settings = await ExportPreferences.load(allowWebp: webpSupported);
    if (mounted) {
      setState(() {
        _exportFormat = settings.format;
        _exportQuality = settings.quality;
        _webpSupported = webpSupported;
      });
    }
  }

  Future<void> _setExportFormat(ExportFormat format) async {
    await ExportPreferences.saveFormat(format);
    if (mounted) {
      setState(() {
        _exportFormat = format;
      });
    }
  }

  Future<void> _setExportQuality(int quality) async {
    await ExportPreferences.saveQuality(quality);
    if (mounted) setState(() => _exportQuality = quality);
  }

  bool get _qualityIsAdjustable => _exportFormat.hasAdjustableQuality;

  String get _qualitySubtitle => switch (_exportFormat) {
        ExportFormat.jpeg => 'JPEG $_exportQuality%',
        ExportFormat.webp => 'WebP $_exportQuality%',
        ExportFormat.png => 'PNG · 무손실',
        ExportFormat.tiff => 'TIFF · 무손실',
      };

  Future<void> _openSystemPermissionSettings() async {
    final opened = await MediaPermissionService.openAppPermissionSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.get('permission.settings_open_failed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
        title: Text(S.get('settings.clear_cache_title'),
            style: const TextStyle(color: AppColors.textOnDark)),
        content: Text(S.get('settings.clear_cache_body'),
            style: const TextStyle(color: AppColors.textOnDarkSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.get('settings.clear_cache_cancel'),
                style: const TextStyle(color: AppColors.textOnDarkTert)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.get('settings.clear_cache_confirm'),
                style: const TextStyle(color: AppColors.oceanFoam)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final temp = await getTemporaryDirectory();
      for (final e in temp.listSync()) {
        try {
          e.deleteSync(recursive: true);
        } catch (error, stackTrace) {
          // Continue clearing independent cache entries, but retain a
          // privacy-safe diagnostic instead of reporting a silent success.
          ErrorLogger.log(
            'One cache entry could not be removed',
            error.runtimeType,
            stackTrace,
          );
        }
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
          SnackBar(
              content: Text('${S.get('settings.clear_cache_fail')}: $e'),
              behavior: SnackBarBehavior.floating),
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.check_rounded, color: Colors.transparent),
              title: const Text('한국어',
                  style: TextStyle(color: AppColors.textOnDark)),
              trailing: ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (_, locale, __) => locale.languageCode == 'ko'
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.oceanFoam)
                    : const SizedBox.shrink(),
              ),
              onTap: () {
                setLocale('ko');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.check_rounded, color: Colors.transparent),
              title: const Text('English',
                  style: TextStyle(color: AppColors.textOnDark)),
              trailing: ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (_, locale, __) => locale.languageCode == 'en'
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.oceanFoam)
                    : const SizedBox.shrink(),
              ),
              onTap: () {
                setLocale('en');
                Navigator.pop(context);
              },
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            _buildFormatTile(ExportFormat.jpeg, 'JPEG (고효율)'),
            if (_webpSupported)
              _buildFormatTile(ExportFormat.webp, 'WebP (고효율)'),
            _buildFormatTile(ExportFormat.png, 'PNG (무손실)'),
            _buildFormatTile(ExportFormat.tiff, 'TIFF (무손실 편집본)'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatTile(ExportFormat format, String label) {
    return ListTile(
      leading: const Icon(Icons.check_rounded, color: Colors.transparent),
      title: Text(label, style: const TextStyle(color: AppColors.textOnDark)),
      trailing: _exportFormat == format
          ? const Icon(Icons.check_rounded, color: AppColors.oceanFoam)
          : const SizedBox.shrink(),
      onTap: () {
        _setExportFormat(format);
        Navigator.pop(context);
      },
    );
  }

  void _showExportQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.oceanMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'JPEG 내보내기 품질',
                style: TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '높을수록 디테일은 유지되고 파일 크기는 커집니다.',
                style: TextStyle(color: AppColors.textOnDarkSub),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [70, 80, 90, 95, 100]
                    .map(
                      (quality) => ChoiceChip(
                        label: Text('$quality%'),
                        selected: _exportQuality == quality,
                        selectedColor: AppColors.oceanFoam,
                        backgroundColor: AppColors.oceanNavy,
                        labelStyle: TextStyle(
                          color: _exportQuality == quality
                              ? AppColors.oceanDeep
                              : AppColors.textOnDark,
                          fontWeight: FontWeight.w800,
                        ),
                        onSelected: (_) async {
                          await _setExportQuality(quality);
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
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
            S.get('settings.dev_hint').replaceAll('{n}', '$remaining'),
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.oceanNavy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          style: const TextStyle(
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
              SettingsRecoverySection(controller: _recoveryController),
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
                subtitle: _qualitySubtitle,
                onTap: _qualityIsAdjustable ? _showExportQualityPicker : null,
              ),
              const _Divider(),
              _SettingRow(
                icon: Icons.image_outlined,
                title: S.get('settings.export_format'),
                subtitle: _exportFormat == ExportFormat.tiff
                    ? 'TIFF'
                    : _exportFormat.name.toUpperCase(),
                onTap: () => _showExportFormatPicker(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: S.get('settings.permissions')),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.admin_panel_settings_outlined,
                title: S.get('settings.app_permissions'),
                subtitle: S.get('settings.app_permissions_sub'),
                onTap: _openSystemPermissionSettings,
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
