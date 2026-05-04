import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/filter_preset.dart';
import '../../engine/lut_engine.dart';
import '../../engine/style_analyzer.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';

class CreateFilterPage extends StatefulWidget {
  const CreateFilterPage({super.key});

  @override
  State<CreateFilterPage> createState() => _CreateFilterPageState();
}

class _CreateFilterPageState extends State<CreateFilterPage> {
  String? _styleImagePath;
  bool _generating = false;
  double _progress = 0.0;
  List<Color> _palette = [];
  List<String> _tags = [];

  final _nameCtrl = TextEditingController();
  FullScreenAdService? _adService;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    final flags = await FeatureFlagsService.create();
    if (mounted) setState(() => _adService = FullScreenAdService(flags));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStyleImage() async {
    hapticMedium();
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    setState(() {
      _styleImagePath = xFile.path;
      _palette = [];
      _tags = [];
    });
    _analyzeStyle(xFile.path);
  }

  Future<void> _analyzeStyle(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null || !mounted) return;
      final profile = StyleAnalyzer.analyze(image);
      final palette = extractPalette(image);
      final tags = deriveStyleTags(profile);
      if (mounted) setState(() { _palette = palette; _tags = tags; });
    } catch (_) {
      // 분석 실패는 non-critical — UI는 빈 상태 유지
    }
  }

  Future<void> _generate() async {
    if (_styleImagePath == null) {
      _showSnack('스타일 이미지를 선택해주세요.');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('필터 이름을 입력해주세요.');
      return;
    }

    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.createFilter);
    }

    setState(() {
      _generating = true;
      _progress = 0.1;
    });
    hapticHeavy();

    try {
      setState(() => _progress = 0.35);
      final result = await generateLutFromStyle(_styleImagePath!);
      setState(() => _progress = 0.82);

      final now = DateTime.now();
      final preset = FilterPreset(
        id: result['presetId'] as String,
        name: name,
        type: FilterPresetType.custom,
        lutPath: result['lutPath'] as String,
        params: AdjustParams.zero,
        defaultIntensity: 0.8,
        thumbnailPath: result['thumbnailPath'] as String,
        createdAt: now,
        updatedAt: now,
      );

      await FilterRepositoryImpl().savePreset(preset);
      setState(() => _progress = 1.0);
      hapticMedium();

      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted) _showSuccessSheet(preset);
    } catch (e) {
      _showSnack('필터 생성 중 오류가 발생했어요. $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.oceanFoam,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSheet(FilterPreset preset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(preset: preset),
    ).then((_) {
      if (mounted) context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, __, ___) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudPure,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(onClose: () => context.pop()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Uncovering Details" heading block — matches _2 mockup
                      const SizedBox(height: 12),
                      Text(
                        S.get('create.heading'),
                        style: const TextStyle(
                          fontFamily: 'Domine',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        S.get('create.subheading'),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ImageStage(
                        imagePath: _styleImagePath,
                        generating: _generating,
                        onTap: _pickStyleImage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ControlPanel(
              nameCtrl: _nameCtrl,
              generating: _generating,
              progress: _progress,
              palette: _palette,
              tags: _tags,
              onPick: _pickStyleImage,
              onGenerate: _generate,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(
          children: [
            // Memoria wordmark
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: AppColors.oceanFoam, size: 20),
                SizedBox(width: 8),
                Text(
                  'Memoria',
                  style: TextStyle(
                    fontFamily: 'Domine',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oceanFoam,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cloudVeil,
                foregroundColor: AppColors.textPrimary,
              ),
              icon: const Icon(Icons.person_outline_rounded),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageStage extends StatelessWidget {
  final String? imagePath;
  final bool generating;
  final VoidCallback onTap;

  const _ImageStage({
    required this.imagePath,
    required this.generating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cloudVeil,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F032111),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagePath != null)
                  Image.file(File(imagePath!), fit: BoxFit.cover)
                else
                  Image.asset(
                    'assets/frames/hp_frame_08_large.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.cloudVeil,
                      child: const Icon(Icons.add_photo_alternate_outlined,
                          size: 56, color: AppColors.textTertiary),
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x55000000)],
                    ),
                  ),
                ),
                // Bottom pill — "Analyzing" when generating, else "SELECT IMAGE"
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: generating
                            ? AppColors.cloudWhite.withValues(alpha: 0.96)
                            : AppColors.cloudWhite.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.cloudMist),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (generating) ...[
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.oceanFoam,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              S.get('create.analyzing'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              imagePath == null
                                  ? Icons.add_photo_alternate_outlined
                                  : Icons.compare_rounded,
                              color: AppColors.oceanFoam,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              imagePath == null ? S.get('create.select') : S.get('create.ready'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final TextEditingController nameCtrl;
  final bool generating;
  final double progress;
  final List<Color> palette;
  final List<String> tags;
  final VoidCallback onPick;
  final VoidCallback onGenerate;

  const _ControlPanel({
    required this.nameCtrl,
    required this.generating,
    required this.progress,
    required this.palette,
    required this.tags,
    required this.onPick,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.cloudWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 32,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
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
            // Palette + Detected row (visible when image selected and analyzed)
            if (!generating && palette.isNotEmpty)
              Row(
                children: [
                  _InfoSection(
                    icon: Icons.palette_outlined,
                    label: S.get('create.palette'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: palette.map((c) => _ColorDot(color: c)).toList(),
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(width: 20),
                    _InfoSection(
                      icon: Icons.local_offer_outlined,
                      label: S.get('create.detected'),
                      child: Wrap(
                        spacing: 6,
                        children: tags.map((t) => _TagChip(t)).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            if (!generating) const SizedBox(height: 18),
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
                    onPressed: generating ? null : onPick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(S.get('create.btn_image')),
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
            if (generating) ...[
              const SizedBox(height: 14),
              // Cancel upload button — matches _2 mockup
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(S.get('create.btn_cancel')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.cloudMist),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _InfoSection({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cloudVeil, width: 1.5),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cloudSilk,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}


class _SuccessSheet extends StatelessWidget {
  final FilterPreset preset;
  const _SuccessSheet({required this.preset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: AppColors.cloudWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.oceanFoam, size: 54),
            const SizedBox(height: 16),
            Text(
              '\'${preset.name}\' 필터 생성 완료',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Domine',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.get('create.done')),
            ),
          ],
        ),
      ),
    );
  }
}
