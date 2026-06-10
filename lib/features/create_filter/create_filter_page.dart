import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/filter_preset.dart';
import '../../engine/lut_engine.dart';
import '../../engine/style_analyzer.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';

const bool kPhotoFilterGenerationEnabled = true;

// ── Isolate message types ─────────────────────────────────

class _IsolateArgs {
  final String styleImagePath;
  final String basePath;
  final SendPort sendPort;
  const _IsolateArgs(this.styleImagePath, this.basePath, this.sendPort);
}

class _ProgressMsg {
  final String stage;
  final double progress;
  const _ProgressMsg(this.stage, this.progress);
}

void _generateLutEntry(_IsolateArgs args) async {
  final result = await generateLutFromStyle(
    args.styleImagePath,
    basePath: args.basePath,
    onProgress: (stage, progress) =>
        args.sendPort.send(_ProgressMsg(stage, progress)),
  );
  args.sendPort.send(result);
}

// ── Stage label helper ────────────────────────────────────

String _stageLabel(String stage, String lang) {
  const cleanKo = {
    'style_loading': '이미지를 불러오는 중...',
    'style_analyze': '스타일을 분석하는 중...',
    'lab_analyze': '색 공간을 분석하는 중...',
    'lut_build': 'LUT를 생성하는 중...',
    'model_inference': 'AI 모델을 실행하는 중...',
    'lut_encode': 'LUT를 인코딩하는 중...',
    'thumbnail': '썸네일을 생성하는 중...',
    'saving': '저장하는 중...',
  };
  const cleanEn = {
    'style_loading': 'Loading image...',
    'style_analyze': 'Analyzing style...',
    'lab_analyze': 'Analyzing colors...',
    'lut_build': 'Building LUT...',
    'model_inference': 'Running AI model...',
    'lut_encode': 'Encoding LUT...',
    'thumbnail': 'Generating thumbnail...',
    'saving': 'Saving...',
  };
  final clean = lang == 'en' ? cleanEn[stage] : cleanKo[stage];
  if (clean != null) return clean;

  const ko = {
    'style_loading': '이미지 불러오는 중...',
    'style_analyze': '스타일 분석 중...',
    'lab_analyze': '색공간 분석 중...',
    'lut_build': 'LUT 생성 중...',
    'model_inference': 'AI 추론 중...',
    'lut_encode': 'LUT 인코딩 중...',
    'thumbnail': '썸네일 생성 중...',
    'saving': '저장 중...',
  };
  const en = {
    'style_loading': 'Loading image...',
    'style_analyze': 'Analyzing style...',
    'lab_analyze': 'Analyzing colors...',
    'lut_build': 'Building LUT...',
    'model_inference': 'Running AI model...',
    'lut_encode': 'Encoding LUT...',
    'thumbnail': 'Generating thumbnail...',
    'saving': 'Saving...',
  };
  return (lang == 'en' ? en[stage] : ko[stage]) ?? stage;
}

// ── Style-tag → suggested name ────────────────────────────

String _suggestName(List<String> tags, String lang) {
  if (tags.isEmpty) return '';
  final key = tags.take(2).join(' ');
  const cleanKo = {
    'Dark': '딥 무드',
    'Bright': '라이트 톤',
    'Natural': '내추럴 톤',
    'Warm': '웜 필름',
    'Cool': '쿨 브리즈',
    'Ocean': '오션 블루',
    'Blue': '블루 톤',
    'Green': '그린 무드',
    'Vintage': '빈티지 필름',
    'Moody': '무디 톤',
    'Dark Moody': '다크 무드',
    'Dark Cool': '딥 블루',
    'Dark Warm': '앤틱 브라운',
    'Dark Ocean': '딥 오션',
    'Bright Warm': '선셋 골드',
    'Bright Cool': '클리어 스카이',
    'Bright Ocean': '서머 시안',
    'Warm Vintage': '필름 빈티지',
    'Warm Moody': '트와일라잇',
    'Cool Ocean': '아쿠아 드림',
    'Ocean Green': '포레스트 톤',
    'Vintage Warm': '레트로 앰버',
  };
  const cleanEn = {
    'Dark': 'Deep Mood',
    'Bright': 'Light Tone',
    'Natural': 'Natural Tone',
    'Warm': 'Warm Film',
    'Cool': 'Cool Breeze',
    'Ocean': 'Ocean Blue',
    'Blue': 'Blue Tone',
    'Green': 'Green Mood',
    'Vintage': 'Vintage Film',
    'Moody': 'Moody Tone',
    'Dark Moody': 'Dark Mood',
    'Dark Cool': 'Deep Blue',
    'Dark Warm': 'Antique Brown',
    'Dark Ocean': 'Deep Ocean',
    'Bright Warm': 'Sunset Gold',
    'Bright Cool': 'Clear Sky',
    'Bright Ocean': 'Summer Cyan',
    'Warm Vintage': 'Film Vignette',
    'Warm Moody': 'Twilight',
    'Cool Ocean': 'Aqua Dream',
    'Ocean Green': 'Forest Tone',
    'Vintage Warm': 'Retro Amber',
  };
  final cleanMap = lang == 'en' ? cleanEn : cleanKo;
  final cleanName = cleanMap[key] ?? cleanMap[tags.first];
  if (cleanName != null) return cleanName;

  const ko = {
    'Dark Moody': '다크 무드',
    'Dark Cool': '딥 블루',
    'Dark Warm': '앤틱 브라운',
    'Dark Ocean': '딥 오션',
    'Bright Warm': '선셋 골드',
    'Bright Cool': '클리어 스카이',
    'Bright Ocean': '서머 시안',
    'Warm Vintage': '필름 비네트',
    'Warm Moody': '황혼의 빛',
    'Cool Ocean': '아쿠아 드림',
    'Ocean Green': '포레스트 토닝',
    'Vintage Warm': '레트로 앰버',
  };
  const en = {
    'Dark Moody': 'Dark Mood',
    'Dark Cool': 'Deep Blue',
    'Dark Warm': 'Antique Brown',
    'Dark Ocean': 'Deep Ocean',
    'Bright Warm': 'Sunset Gold',
    'Bright Cool': 'Clear Sky',
    'Bright Ocean': 'Summer Cyan',
    'Warm Vintage': 'Film Vignette',
    'Warm Moody': 'Twilight',
    'Cool Ocean': 'Aqua Dream',
    'Ocean Green': 'Forest Tone',
    'Vintage Warm': 'Retro Amber',
  };
  final map = lang == 'en' ? en : ko;
  return map[key] ?? map[tags.first] ?? '';
}

// ─────────────────────────────────────────────────────────

class CreateFilterPage extends StatefulWidget {
  const CreateFilterPage({super.key});

  @override
  State<CreateFilterPage> createState() => _CreateFilterPageState();
}

class _CreateFilterPageState extends State<CreateFilterPage> {
  String? _styleImagePath;
  bool _generating = false;
  double _progress = 0.0;
  String _stageMsg = '';
  List<Color> _palette = [];
  List<String> _tags = [];

  final _nameCtrl = TextEditingController();
  FullScreenAdService? _adService;

  // Isolate teardown
  Isolate? _isolate;
  ReceivePort? _receivePort;

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
    _cancelIsolate();
    super.dispose();
  }

  void _cancelIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
  }

  Future<void> _pickStyleImage() async {
    hapticMedium();
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      _showSnack(S.get('permission.photos_denied'));
      return;
    }
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
      if (mounted) {
        setState(() {
          _palette = palette;
          _tags = tags;
        });
        // Auto-suggest name if field is empty
        if (_nameCtrl.text.isEmpty) {
          final lang = localeNotifier.value.languageCode;
          final suggestion = _suggestName(tags, lang);
          if (suggestion.isNotEmpty) {
            _nameCtrl.text = suggestion;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _generate() async {
    if (_styleImagePath == null) {
      _showSnack(S.get('create.need_image'));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack(S.get('create.need_name'));
      return;
    }
    if (!kPhotoFilterGenerationEnabled) {
      _showSnack(S.get('create.deferred'));
      return;
    }

    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.createFilter);
    }

    setState(() {
      _generating = true;
      _progress = 0.05;
      _stageMsg = _stageLabel(
          'style_loading', localeNotifier.value.languageCode);
    });
    hapticHeavy();

    try {
      final styleImagePath = _styleImagePath!;
      final base = await getApplicationDocumentsDirectory();

      final receivePort = ReceivePort();
      _receivePort = receivePort;

      final completer = Completer<Map<String, dynamic>>();

      receivePort.listen((msg) {
        if (msg is _ProgressMsg) {
          if (mounted) {
            setState(() {
              _progress = msg.progress;
              _stageMsg = _stageLabel(
                  msg.stage, localeNotifier.value.languageCode);
            });
          }
        } else if (msg is Map<String, dynamic>) {
          completer.complete(msg);
        }
      });

      final isolate = await Isolate.spawn(
        _generateLutEntry,
        _IsolateArgs(styleImagePath, base.path, receivePort.sendPort),
        errorsAreFatal: true,
      );
      _isolate = isolate;

      final result = await completer.future;
      _cancelIsolate();

      setState(() => _progress = 1.0);

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
      hapticMedium();

      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _showSuccessSheet(preset, styleImagePath);
    } catch (e) {
      _cancelIsolate();
      _showSnack(S.get('create.error'));
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

  void _showSuccessSheet(FilterPreset preset, String styleImagePath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(
        preset: preset,
        styleImagePath: styleImagePath,
        onEditNow: () {
          Navigator.of(context).pop(); // close sheet
          if (mounted) context.pop(); // back to filters
          // Then navigate to editor with this preset pre-loaded
          context.pushNamed('editor', extra: styleImagePath);
        },
      ),
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
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        style: const TextStyle(
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
              stageMsg: _stageMsg,
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

// ─────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────

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
              icon: const Icon(Icons.close_rounded),
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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: generating
                            ? AppColors.cloudWhite.withOpacity(0.96)
                            : AppColors.cloudWhite.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.cloudMist),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (generating) ...[
                            const SizedBox(
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
                              style: const TextStyle(
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
                              imagePath == null
                                  ? S.get('create.select')
                                  : S.get('create.ready'),
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
  final String stageMsg;
  final List<Color> palette;
  final List<String> tags;
  final VoidCallback onPick;
  final VoidCallback onGenerate;

  const _ControlPanel({
    required this.nameCtrl,
    required this.generating,
    required this.progress,
    required this.stageMsg,
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

            // Palette + Tags row
            if (!generating && palette.isNotEmpty)
              Row(
                children: [
                  _InfoSection(
                    icon: Icons.palette_outlined,
                    label: S.get('create.palette'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children:
                          palette.map((c) => _ColorDot(color: c)).toList(),
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
          ],
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

// ─────────────────────────────────────────────────────────
//  Success Sheet — A1 + A3
// ─────────────────────────────────────────────────────────

class _SuccessSheet extends StatelessWidget {
  final FilterPreset preset;
  final String styleImagePath;
  final VoidCallback onEditNow;

  const _SuccessSheet({
    required this.preset,
    required this.styleImagePath,
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
              styleImagePath: styleImagePath,
              thumbnailPath: preset.thumbnailPath,
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
            const SizedBox(height: 24),

            // CTA: edit now
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEditNow,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(S.get('create.btn_edit_now')),
              ),
            ),
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
  final String styleImagePath;
  final String? thumbnailPath;

  const _BeforeAfterPreview({
    required this.styleImagePath,
    required this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PreviewCard(
            imagePath: styleImagePath,
            label: S.get('create.before'),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_forward_rounded,
            color: AppColors.oceanFoam, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: _PreviewCard(
            imagePath: thumbnailPath,
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
    required this.imagePath,
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
