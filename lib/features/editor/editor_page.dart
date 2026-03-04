import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import '../../core/theme/app_colors.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/edit_ops.dart';
import '../../domain/models/filter_preset.dart';
import '../../engine/lut_engine.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';
import 'widgets/adjust_slider.dart';
import 'widgets/filter_strip.dart';

enum _EditorTab { filters, adjust }

class EditorPage extends StatefulWidget {
  final String? imagePath;
  const EditorPage({super.key, this.imagePath});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  _EditorTab _tab = _EditorTab.filters;
  AdjustParams _params = AdjustParams.zero;
  FilterPreset? _selectedPreset;
  double _intensity = 1.0;
  int _adjustIndex = 0;
  bool _exporting = false;
  double _exportProgress = 0.0;

  Uint8List? _lutBytes;
  Uint8List? _previewBytes;
  bool _processingPreview = false;

  late List<FilterPreset> _allPresets;
  FeatureFlagsService? _flags;
  FullScreenAdService? _adService;

  @override
  void initState() {
    super.initState();
    _allPresets = BuiltinPresets.all;
    _loadServices();
    if (widget.imagePath != null) _renderPreview();
  }

  Future<void> _loadServices() async {
    final f = await FeatureFlagsService.create();
    final s = FullScreenAdService(f);
    if (mounted) setState(() { _flags = f; _adService = s; });
  }

  Future<void> _selectPreset(FilterPreset? preset) async {
    setState(() => _selectedPreset = preset);
    _lutBytes = preset == null
        ? null
        : await loadLutBytes(preset.lutPath);
    await _renderPreview();
  }

  Future<void> _renderPreview() async {
    if (widget.imagePath == null || _processingPreview) return;
    setState(() => _processingPreview = true);

    try {
      final bytes  = File(widget.imagePath!).readAsBytesSync();
      final image  = img.decodeImage(bytes)!;

      // Downscale to max 1080
      final maxDim = image.width > image.height ? image.width : image.height;
      final scale  = maxDim > 1080 ? 1080.0 / maxDim : 1.0;
      final preview = scale < 1.0
          ? img.copyResize(image,
              width:  (image.width  * scale).round(),
              height: (image.height * scale).round())
          : image;

      // Apply pipeline
      final out = img.Image(width: preview.width, height: preview.height);
      for (int y = 0; y < preview.height; y++) {
        for (int x = 0; x < preview.width; x++) {
          final px = preview.getPixel(x, y);
          final orig = RgbColor(px.rNormalized, px.gNormalized, px.bNormalized);
          final result = applyPipeline(
            original: orig,
            params: _params,
            lutBytes: _lutBytes,
            intensity: _intensity,
          );
          out.setPixelRgb(x, y,
            (result.r * 255).round(),
            (result.g * 255).round(),
            (result.b * 255).round(),
          );
        }
      }

      final encoded = img.encodeJpg(out, quality: 85);
      if (mounted) setState(() => _previewBytes = Uint8List.fromList(encoded));
    } finally {
      if (mounted) setState(() => _processingPreview = false);
    }
  }

  Future<void> _export() async {
    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.applyOrExport);
    }

    setState(() { _exporting = true; _exportProgress = 0; });

    try {
      final bytes  = File(widget.imagePath!).readAsBytesSync();
      final image  = img.decodeImage(bytes)!;
      final total  = image.width * image.height;
      int   done   = 0;

      final out = img.Image(width: image.width, height: image.height);

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final px = image.getPixel(x, y);
          final orig = RgbColor(px.rNormalized, px.gNormalized, px.bNormalized);
          final result = applyPipeline(
            original: orig,
            params: _params,
            lutBytes: _lutBytes,
            intensity: _intensity,
          );
          out.setPixelRgb(x, y,
            (result.r * 255).round(),
            (result.g * 255).round(),
            (result.b * 255).round(),
          );
          done++;
        }
        if (mounted) {
          setState(() => _exportProgress = done / total);
        }
      }

      HapticFeedback.notificationVibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보내기 완료!')),
        );
      }
    } finally {
      if (mounted) setState(() { _exporting = false; _exportProgress = 0; });
    }
  }

  List<AdjustSliderItem> get _sliderItems => [
    AdjustSliderItem(
      label: '노출', icon: '☀️',
      value: _params.exposure, min: -2.0, max: 2.0,
      onChanged: (v) { setState(() => _params = _params.copyWith(exposure: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '명암', icon: '◑',
      value: _params.contrast, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(contrast: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '채도', icon: '🌈',
      value: _params.saturation, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(saturation: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '색온도', icon: '🌡',
      value: _params.temperature, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(temperature: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '틴트', icon: '💜',
      value: _params.tint, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(tint: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '하이라이트', icon: '✦',
      value: _params.highlights, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(highlights: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '쉐도우', icon: '🌑',
      value: _params.shadows, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(shadows: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '선명도', icon: '🔍',
      value: _params.sharpen, min: 0, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(sharpen: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '비네팅', icon: '⬛',
      value: _params.vignette, min: 0, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(vignette: v)); _renderPreview(); },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanAbyss,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildPreviewArea()),
              _buildBottomPanel(),
            ],
          ),
          if (_exporting) _buildExportOverlay(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _IconBtn(
              icon: Icons.arrow_back_ios_rounded,
              onTap: () => context.pop(),
            ),
            const Spacer(),
            const Text(
              '편집',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnDark,
              ),
            ),
            const Spacer(),
            _IconBtn(
              icon: Icons.ios_share_rounded,
              onTap: _export,
              primary: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (widget.imagePath == null) {
      return const Center(
        child: Text('사진을 선택하세요',
            style: TextStyle(color: AppColors.textOnDarkSub)),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (_previewBytes != null)
          Image.memory(
            _previewBytes!,
            fit: BoxFit.contain,
            width: double.infinity,
          )
        else
          Image.file(
            File(widget.imagePath!),
            fit: BoxFit.contain,
            width: double.infinity,
          ),
        if (_processingPreview)
          Container(
            color: Colors.black26,
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.oceanFoam,
                strokeWidth: 2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _buildTabBar(),
          const SizedBox(height: 12),
          if (_tab == _EditorTab.filters) ...[
            FilterStrip(
              presets: _allPresets,
              selectedId: _selectedPreset?.id,
              onSelect: _selectPreset,
            ),
            const SizedBox(height: 10),
            if (_selectedPreset != null)
              IntensitySlider(
                value: _intensity,
                onChanged: (v) {
                  setState(() => _intensity = v);
                  _renderPreview();
                },
              ),
          ] else ...[
            AdjustParamsPanel(
              items: _sliderItems,
              selectedIndex: _adjustIndex,
              onSelectIndex: (i) => setState(() => _adjustIndex = i),
            ),
          ],
          const SizedBox(height: 16),
          SafeArea(top: false, child: const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _TabBtn(
            label: '필터',
            icon: Icons.filter_rounded,
            selected: _tab == _EditorTab.filters,
            onTap: () => setState(() => _tab = _EditorTab.filters),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '조절',
            icon: Icons.tune_rounded,
            selected: _tab == _EditorTab.adjust,
            onTap: () => setState(() => _tab = _EditorTab.adjust),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _params = AdjustParams.zero;
                _selectedPreset = null;
                _intensity = 1.0;
                _lutBytes = null;
              });
              _renderPreview();
            },
            child: const Text(
              '초기화',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOverlay() {
    return Container(
      color: AppColors.overlay40,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.oceanMid,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '내보내는 중...',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnDark,
                ),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _exportProgress,
                backgroundColor: AppColors.oceanNavy,
                valueColor: const AlwaysStoppedAnimation(AppColors.oceanFoam),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              const SizedBox(height: 12),
              Text(
                '${(_exportProgress * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: AppColors.textOnDarkSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.oceanTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? AppColors.cloudWhite
                    : AppColors.textOnDarkTert),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.cloudWhite
                    : AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primary ? AppColors.accentPrimary : AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: AppColors.cloudWhite, size: 18),
      ),
    );
  }
}
