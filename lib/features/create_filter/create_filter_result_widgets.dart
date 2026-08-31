part of 'create_filter_page.dart';

class _ControlPanel extends StatelessWidget {
  final TextEditingController nameCtrl;
  final bool generating;
  final double progress;
  final String stageMsg;
  final List<Color> palette;
  final List<String> tags;
  final String pickLabel;
  final VoidCallback onPick;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  const _ControlPanel({
    required this.nameCtrl,
    required this.generating,
    required this.progress,
    required this.stageMsg,
    required this.palette,
    required this.tags,
    required this.pickLabel,
    required this.onPick,
    required this.onGenerate,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          key: const ValueKey('create-filter-glass-controls'),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.86),
                const Color(0xFFDDF2E4).withValues(alpha: 0.76),
                const Color(0xFFFFF5E8).withValues(alpha: 0.72),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.92)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26032111),
                blurRadius: 38,
                offset: Offset(0, -12),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.cloudVeil,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Analysis summary
                if (!generating && palette.isNotEmpty)
                  _AnalysisSummary(
                    palette: palette,
                    tags: tags,
                  ),
                if (!generating) const SizedBox(height: 18),

                // Progress block (stage label + animated bar)
                if (generating) ...[
                  _StageProgressBar(progress: progress, stageMsg: stageMsg),
                  const SizedBox(height: 18),
                ],

                // Name field
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: S.get('create.name_label'),
                    hintText: S.get('create.name_hint'),
                    prefixIcon: const Icon(Icons.edit_rounded),
                  ),
                ),
                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: generating ? onCancel : onPick,
                        icon: Icon(generating
                            ? Icons.close_rounded
                            : Icons.photo_library_outlined),
                        label: Text(generating
                            ? (localeNotifier.value.languageCode == 'en'
                                ? 'Cancel'
                                : '취소')
                            : pickLabel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.oceanFoam,
                          side: const BorderSide(color: AppColors.cloudMist),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: generating ? null : onGenerate,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(generating
                            ? '${(progress * 100).round()}%'
                            : S.get('create.btn_save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageProgressBar extends StatelessWidget {
  final double progress;
  final String stageMsg;

  const _StageProgressBar({required this.progress, required this.stageMsg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stageMsg,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.oceanFoam,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: progress),
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.cloudVeil,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.oceanFoam),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  final List<Color> palette;
  final List<String> tags;

  const _AnalysisSummary({required this.palette, required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('create-filter-analysis-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10032111),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.oceanFoam),
              const SizedBox(width: 7),
              Text(S.get('create.analysis_done'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  )),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.oceanFoam,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AnalysisGroup(
                  key: const ValueKey('create-filter-palette-group'),
                  label: S.get('create.palette'),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: palette
                        .map((color) => _ColorDot(color: color))
                        .toList(),
                  ),
                ),
              ),
              if (tags.isNotEmpty) ...[
                Container(
                  width: 1,
                  height: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.cloudVeil,
                ),
                Expanded(
                  flex: 2,
                  child: _AnalysisGroup(
                    key: const ValueKey('create-filter-style-group'),
                    label: S.get('create.detected'),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((tag) => _TagChip(tag)).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const _AnalysisGroup({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x19000000), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.oceanFoam.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.oceanFoam.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.oceanFoam,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Success Sheet — A1 + A3
// ─────────────────────────────────────────────────────────

class _SuccessSheet extends StatelessWidget {
  final FilterPreset preset;
  final String? sourcePath;
  final String? sampleAfterPath;
  final String? referenceGuidance;
  final VoidCallback? onReselect;
  final Future<void> Function() onEditNow;

  const _SuccessSheet({
    required this.preset,
    required this.sourcePath,
    required this.sampleAfterPath,
    this.referenceGuidance,
    this.onReselect,
    required this.onEditNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: AppColors.cloudWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 52,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.cloudVeil,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),

            // Before / After preview
            _BeforeAfterPreview(
              beforePath: sourcePath,
              afterPath: sampleAfterPath,
            ),
            const SizedBox(height: 20),

            // Success label
            const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.oceanFoam, size: 40),
            const SizedBox(height: 10),
            Text(
              '\'${preset.name}\' ${S.get('create.success')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Domine',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.get('create.success_sub'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            if (referenceGuidance != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cloudPure,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.oceanFoam, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        referenceGuidance!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // CTA: edit now
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEditNow,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(S.get('create.btn_edit_now')),
              ),
            ),
            if (onReselect != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onReselect,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(localeNotifier.value.languageCode == 'en'
                      ? 'Choose reference photos again'
                      : '참조 사진 다시 선택'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.oceanFoam,
                    side: const BorderSide(color: AppColors.cloudMist),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.cloudMist),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: Text(S.get('create.done')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeforeAfterPreview extends StatelessWidget {
  final String? beforePath;
  final String? afterPath;

  const _BeforeAfterPreview({
    required this.beforePath,
    required this.afterPath,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PreviewCard(
            imagePath: beforePath,
            label: S.get('create.before'),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_forward_rounded,
            color: AppColors.oceanFoam, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: _PreviewCard(
            imagePath: afterPath,
            label: S.get('create.after'),
            isAfter: true,
          ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String? imagePath;
  final String label;
  final bool isAfter;

  const _PreviewCard({
    this.imagePath,
    required this.label,
    this.isAfter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isAfter ? AppColors.oceanFoam : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: imagePath != null
                ? Image.file(File(imagePath!), fit: BoxFit.cover)
                : Container(color: AppColors.cloudVeil),
          ),
        ),
      ],
    );
  }
}
