import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';

const memoriaSupportUrl = 'https://github.com/cres17/memoria/issues';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, _, __) => _InfoPage(
        title: S.get('privacy.title'),
        children: [
          _Lead(text: S.get('privacy.summary')),
          _InfoSection(
            icon: Icons.photo_library_outlined,
            title: S.get('privacy.photos_title'),
            body: S.get('privacy.photos_body'),
          ),
          _InfoSection(
            icon: Icons.storage_outlined,
            title: S.get('privacy.storage_title'),
            body: S.get('privacy.storage_body'),
          ),
          _InfoSection(
            icon: Icons.memory_rounded,
            title: S.get('privacy.ai_title'),
            body: S.get('privacy.ai_body'),
          ),
          _InfoSection(
            icon: Icons.monitor_heart_outlined,
            title: S.get('privacy.diagnostics_title'),
            body: S.get('privacy.diagnostics_body'),
          ),
          _Notice(text: S.get('privacy.release_note')),
        ],
      ),
    );
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _copySupportAddress(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: memoriaSupportUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.get('common.copied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, _, __) => _InfoPage(
        title: S.get('support.title'),
        children: [
          _Lead(text: S.get('support.intro')),
          _InfoSection(
            icon: Icons.checklist_rounded,
            title: S.get('support.title'),
            body: S.get('support.steps'),
          ),
          _InfoSection(
            icon: Icons.bug_report_outlined,
            title: S.get('support.channel_title'),
            body: S.get('support.channel_body'),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.oceanMid,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.oceanNavy),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SelectableText(
                  memoriaSupportUrl,
                  style: TextStyle(
                    color: AppColors.oceanFoam,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _copySupportAddress(context),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(S.get('support.copy_address')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      appBar: AppBar(
        backgroundColor: AppColors.oceanDeep,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(backIcon(), color: AppColors.textOnDark),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textOnDark,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: children
              .expand((child) => [child, const SizedBox(height: 16)])
              .toList()
            ..removeLast(),
        ),
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  final String text;

  const _Lead({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'NotoSerif',
        fontSize: 19,
        height: 1.55,
        fontWeight: FontWeight.w700,
        color: AppColors.textOnDark,
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.oceanFoam, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textOnDarkSub,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.oceanNavy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.textOnDarkTert,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textOnDarkTert,
                height: 1.5,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
