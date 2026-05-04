import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_utils.dart';
import '../../engine/blend_modes.dart' as bm;
import '../../engine/portrait_engine.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/curve_data.dart';
import '../../domain/models/filter_preset.dart';
import '../../engine/artistic_effects.dart';
import '../../engine/blur_engine.dart';
import '../../engine/local_adjust.dart';
import '../../engine/lut_engine.dart';
import '../../engine/white_balance.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';
import 'widgets/adjust_slider.dart';
import 'widgets/curve_editor.dart';
import 'widgets/filter_strip.dart';

enum _EditorTab { filters, adjust, curves, effects, tools, local, portrait, creative }
enum _LocalSubTab { selective, dodgeBurn, tiltShift, lensBlur }

class EditorPage extends StatefulWidget {
  final String? imagePath;
  final String? initialPresetId;
  const EditorPage({super.key, this.imagePath, this.initialPresetId});

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

  // Phase 2: 채널별 커브 상태
  final Map<CurveChannel, CurveData> _curves = {};

  // Phase 4: 아티스틱 이펙트
  ArtisticEffect _effect         = ArtisticEffect.none;
  double         _effectStrength = 1.0;
  int            _grainVariant   = 3;

  // Phase 5: 기하학 변환
  _ToolsSubTab   _toolsSubTab  = _ToolsSubTab.crop;
  CropRatioPreset _cropRatio   = CropRatioPreset.free;
  double         _rotation     = 0.0;  // degrees -45..+45
  bool           _flipH        = false;
  bool           _flipV        = false;
  // Portrait
  double _portraitSmooth   = 0.0;
  double _portraitSpotlight = 0.0;
  SkinTone _skinTone       = SkinTone.none;
  double _skinToneStrength = 50.0;

  // Creative — double exposure
  String? _blendImagePath;
  bm.BlendMode _blendMode  = bm.BlendMode.lighten;
  double   _blendOpacity   = 0.5;
  // Creative — frame
  int      _frameIndex     = -1; // -1 = none
  // Creative — text overlay
  String   _overlayText    = '';
  double   _textSize       = 32.0;
  Color    _textColor      = Colors.white;

  // Phase 6: 로컬 조정
  _LocalSubTab _localSubTab    = _LocalSubTab.tiltShift;
  // Selective
  bool   _selActive    = false;
  double _selX         = 0.5, _selY        = 0.5;
  double _selBright    = 0,   _selContrast = 0,   _selSat    = 0;
  double _selRadius    = 0.3;
  // Dodge & Burn
  bool   _dbActive     = false;
  double _dodgeY       = 0.25, _dodgeRadius = 0.25, _dodgeStrength = 0.3;
  double _burnY        = 0.75, _burnRadius  = 0.25, _burnStrength  = 0.3;
  // Tilt-Shift
  bool   _tiltActive   = false;
  double _tiltFocusCenter = 0.5, _tiltBandWidth = 0.3, _tiltMaxBlur = 8;
  // Lens Blur
  bool   _lensActive   = false;
  double _lensFocusDepth = 0.0, _lensMaxRadius = 8;

  // Perspective (shear-based skew, degrees)
  double _perspH = 0.0, _perspV = 0.0;

  Uint8List? _lutBytes;
  Uint8List? _previewBytes;
  bool _processingPreview = false;

  static Float32List _radialDepthMap(int w, int h) {
    final map = Float32List(w * h);
    final cx = w / 2.0, cy = h / 2.0;
    final maxD = math.sqrt(cx * cx + cy * cy);
    for (int py = 0; py < h; py++) {
      for (int px = 0; px < w; px++) {
        final dx = px - cx, dy = py - cy;
        map[py * w + px] = (math.sqrt(dx * dx + dy * dy) / maxD).clamp(0.0, 1.0);
      }
    }
    return map;
  }

  /// 크롭 비율에 따라 이미지 중앙 크롭.
  img.Image _applyCropToImage(img.Image image) {
    if (_cropRatio == CropRatioPreset.free) return image;
    final ratio = _cropRatio.ratio;
    if (ratio == null) return image;
    final W = image.width.toDouble();
    final H = image.height.toDouble();
    int cropW, cropH, x, y;
    if (W / H > ratio) {
      cropH = H.round();
      cropW = (H * ratio).round();
    } else {
      cropW = W.round();
      cropH = (W / ratio).round();
    }
    x = ((W - cropW) / 2).round();
    y = ((H - cropH) / 2).round();
    return img.copyCrop(image, x: x, y: y, width: cropW, height: cropH);
  }

  late List<FilterPreset> _allPresets;
  FullScreenAdService? _adService;

  @override
  void initState() {
    super.initState();
    _allPresets = BuiltinPresets.all;
    _loadServices();
    if (widget.imagePath != null) _renderPreview();
    if (widget.initialPresetId != null) {
      _selectedPreset = _allPresets.firstWhere(
        (p) => p.id == widget.initialPresetId,
        orElse: () => _allPresets.first,
      );
    }
    setStatusBarForDark();
  }

  @override
  void dispose() {
    setStatusBarForLight();
    super.dispose();
  }

  /// Shear-based perspective skew applied to the image.
  img.Image _applyPerspectiveSkew(img.Image src, double hDeg, double vDeg) {
    final shX = math.tan(hDeg * math.pi / 180);
    final shY = math.tan(vDeg * math.pi / 180);
    final W = src.width, H = src.height;
    final newW = W + (shY.abs() * H).ceil();
    final newH = H + (shX.abs() * W).ceil();
    final dst  = img.Image(width: newW, height: newH);
    final offX = shY < 0 ? (shY.abs() * H).ceil() : 0;
    final offY = shX < 0 ? (shX.abs() * W).ceil() : 0;
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final nx = (x + offX + shY * y).round();
        final ny = (y + offY + shX * x).round();
        if (nx >= 0 && nx < newW && ny >= 0 && ny < newH) {
          dst.setPixel(nx, ny, src.getPixel(x, y));
        }
      }
    }
    return img.copyCrop(dst,
      x: (newW - W) ~/ 2, y: (newH - H) ~/ 2, width: W, height: H);
  }

  Future<void> _loadServices() async {
    final f = await FeatureFlagsService.create();
    if (mounted) setState(() { _adService = FullScreenAdService(f); });
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
      final bytes = File(widget.imagePath!).readAsBytesSync();
      var image   = img.decodeImage(bytes)!;

      // Phase 5: 기하학 변환 (크롭 → 회전/플립 순서)
      image = _applyCropToImage(image);
      if (_flipH || _flipV) {
        final dir = _flipH && _flipV
            ? img.FlipDirection.both
            : _flipH ? img.FlipDirection.horizontal : img.FlipDirection.vertical;
        image = img.copyFlip(image, direction: dir);
      }
      if (_rotation != 0) {
        image = img.copyRotate(image, angle: _rotation);
      }
      if (_perspH != 0 || _perspV != 0) {
        image = _applyPerspectiveSkew(image, _perspH, _perspV);
      }

      // Downscale to max 1080
      final maxDim = image.width > image.height ? image.width : image.height;
      final scale  = maxDim > 1080 ? 1080.0 / maxDim : 1.0;
      final preview = scale < 1.0
          ? img.copyResize(image,
              width:  (image.width  * scale).round(),
              height: (image.height * scale).round())
          : image;

      // Apply pipeline: Adjust → LUT → Intensity → Sharpen/Clarity/...
      var out = applyImagePipeline(
        image:     preview,
        params:    _params,
        lutBytes:  _lutBytes,
        intensity: _intensity,
      );

      // Phase 4: 아티스틱 이펙트 (grain, vintage, HDR 등)
      if (_effect != ArtisticEffect.none) {
        out = await applyArtisticEffect(
          out, _effect,
          strength:     _effectStrength,
          grainVariant: _grainVariant,
        );
      }

      // Phase 6: 로컬 조정
      if (_selActive) {
        out = applySelectiveAdjust(out, [
          SelectivePoint(x: _selX, y: _selY, brightness: _selBright,
              contrast: _selContrast, saturation: _selSat, radius: _selRadius),
        ]);
      }
      if (_dbActive) {
        out = applyDodgeBurn(out, [
          if (_dodgeStrength > 0) BrushStroke(x: 0.5, y: _dodgeY,
              radius: _dodgeRadius, strength: _dodgeStrength, isDodge: true),
          if (_burnStrength  > 0) BrushStroke(x: 0.5, y: _burnY,
              radius: _burnRadius,  strength: _burnStrength,  isDodge: false),
        ]);
      }
      if (_tiltActive) {
        out = applyLinearTiltShift(image: out, focusCenter: _tiltFocusCenter,
            focusBandWidth: _tiltBandWidth, maxBlur: _tiltMaxBlur);
      }
      if (_lensActive) {
        out = applyLensBlur(image: out,
            depthMap: _radialDepthMap(out.width, out.height),
            focusDepth: _lensFocusDepth, maxBlurRadius: _lensMaxRadius);
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
      final bytes = File(widget.imagePath!).readAsBytesSync();
      var image   = img.decodeImage(bytes)!;

      // Phase 5: 기하학 변환
      image = _applyCropToImage(image);
      if (_flipH || _flipV) {
        final dir = _flipH && _flipV
            ? img.FlipDirection.both
            : _flipH ? img.FlipDirection.horizontal : img.FlipDirection.vertical;
        image = img.copyFlip(image, direction: dir);
      }
      if (_rotation != 0) {
        image = img.copyRotate(image, angle: _rotation);
      }
      if (_perspH != 0 || _perspV != 0) {
        image = _applyPerspectiveSkew(image, _perspH, _perspV);
      }

      var out = applyImagePipeline(
        image:     image,  // already geom-transformed
        params:    _params,
        lutBytes:  _lutBytes,
        intensity: _intensity,
      );

      // Phase 6: 로컬 조정
      if (_selActive) {
        out = applySelectiveAdjust(out, [
          SelectivePoint(x: _selX, y: _selY, brightness: _selBright,
              contrast: _selContrast, saturation: _selSat, radius: _selRadius),
        ]);
      }
      if (_dbActive) {
        out = applyDodgeBurn(out, [
          if (_dodgeStrength > 0) BrushStroke(x: 0.5, y: _dodgeY,
              radius: _dodgeRadius, strength: _dodgeStrength, isDodge: true),
          if (_burnStrength  > 0) BrushStroke(x: 0.5, y: _burnY,
              radius: _burnRadius,  strength: _burnStrength,  isDodge: false),
        ]);
      }
      if (_tiltActive) {
        out = applyLinearTiltShift(image: out, focusCenter: _tiltFocusCenter,
            focusBandWidth: _tiltBandWidth, maxBlur: _tiltMaxBlur);
      }
      if (_lensActive) {
        out = applyLensBlur(image: out,
            depthMap: _radialDepthMap(out.width, out.height),
            focusDepth: _lensFocusDepth, maxBlurRadius: _lensMaxRadius);
      }

      if (mounted) setState(() => _exportProgress = 0.9);

      // 결과물 저장
      final docsDir = await getApplicationDocumentsDirectory();
      final outPath = '${docsDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      outFile.writeAsBytesSync(img.encodeJpg(out, quality: 95));

      if (!outFile.existsSync() || outFile.lengthSync() == 0) {
        throw Exception('저장 파일이 생성되지 않았습니다.');
      }

      if (mounted) setState(() => _exportProgress = 1.0);
      hapticMedium();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진이 저장되었습니다.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() { _exporting = false; _exportProgress = 0; });
    }
  }

  // ── Phase 6: 로컬 조정 빌더 ─────────────────────────────

  Widget _buildLocalPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLocalSubTabRow(),
        const SizedBox(height: 10),
        if (_localSubTab == _LocalSubTab.selective)   ..._buildSelectiveContent()
        else if (_localSubTab == _LocalSubTab.dodgeBurn) ..._buildDodgeBurnContent()
        else if (_localSubTab == _LocalSubTab.tiltShift)  ..._buildTiltShiftContent()
        else                                              ..._buildLensBlurContent(),
      ],
    );
  }

  Widget _buildLocalSubTabRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SubTabBtn(label: '선택적', icon: Icons.adjust_rounded,
                selected: _localSubTab == _LocalSubTab.selective,
                onTap: () => setState(() => _localSubTab = _LocalSubTab.selective)),
            const SizedBox(width: 8),
            _SubTabBtn(label: '닷지&번', icon: Icons.brightness_medium_rounded,
                selected: _localSubTab == _LocalSubTab.dodgeBurn,
                onTap: () => setState(() => _localSubTab = _LocalSubTab.dodgeBurn)),
            const SizedBox(width: 8),
            _SubTabBtn(label: '틸트쉬프트', icon: Icons.gradient_rounded,
                selected: _localSubTab == _LocalSubTab.tiltShift,
                onTap: () => setState(() => _localSubTab = _LocalSubTab.tiltShift)),
            const SizedBox(width: 8),
            _SubTabBtn(label: '렌즈블러', icon: Icons.blur_on_rounded,
                selected: _localSubTab == _LocalSubTab.lensBlur,
                onTap: () => setState(() => _localSubTab = _LocalSubTab.lensBlur)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalToggle(String label, bool value, ValueChanged<bool> onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(
              fontFamily: 'NotoSerif', fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textOnDarkSub)),
          const Spacer(),
          GestureDetector(
            onTap: () { hapticLight(); onChange(!value); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40, height: 22,
              decoration: BoxDecoration(
                color: value ? AppColors.oceanTeal : AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18, height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                      color: AppColors.cloudWhite, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact slider for local adjustment panels.
  /// [onSet] is a plain assignment (no setState) — widget wraps it.
  Widget _lSlider(String label, double value, double min, double max,
      void Function(double) onSet) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(label, style: const TextStyle(
                fontFamily: 'NotoSerif', fontSize: 12,
                color: AppColors.textOnDarkSub)),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min, max: max,
                onChanged: (v) => setState(() => onSet(v)),
                onChangeEnd: (_) => _renderPreview(),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 11,
                    color: AppColors.textOnDarkTert)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSelectiveContent() => [
    _buildLocalToggle('선택적 조정', _selActive, (v) {
      setState(() => _selActive = v);
      _renderPreview();
    }),
    if (_selActive) ...[
      _lSlider('X 위치', _selX, 0.0, 1.0, (v) => _selX = v),
      _lSlider('Y 위치', _selY, 0.0, 1.0, (v) => _selY = v),
      _lSlider('반경',   _selRadius, 0.1, 0.8, (v) => _selRadius = v),
      _lSlider('밝기',   _selBright, -100, 100, (v) => _selBright = v),
      _lSlider('대비',   _selContrast, -100, 100, (v) => _selContrast = v),
      _lSlider('채도',   _selSat, -100, 100, (v) => _selSat = v),
    ],
  ];

  List<Widget> _buildDodgeBurnContent() => [
    _buildLocalToggle('닷지 & 번', _dbActive, (v) {
      setState(() => _dbActive = v);
      _renderPreview();
    }),
    if (_dbActive) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text('닷지 (밝게)', style: TextStyle(
            fontFamily: 'NotoSerif', fontSize: 12, fontWeight: FontWeight.w600,
            color: AppColors.oceanFoam.withValues(alpha: 0.85))),
      ),
      _lSlider('Y 위치', _dodgeY, 0.0, 1.0, (v) => _dodgeY = v),
      _lSlider('반경',   _dodgeRadius, 0.05, 0.5, (v) => _dodgeRadius = v),
      _lSlider('강도',   _dodgeStrength, 0.0, 1.0, (v) => _dodgeStrength = v),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text('번 (어둡게)', style: const TextStyle(
            fontFamily: 'NotoSerif', fontSize: 12, fontWeight: FontWeight.w600,
            color: AppColors.textOnDarkSub)),
      ),
      _lSlider('Y 위치', _burnY, 0.0, 1.0, (v) => _burnY = v),
      _lSlider('반경',   _burnRadius, 0.05, 0.5, (v) => _burnRadius = v),
      _lSlider('강도',   _burnStrength, 0.0, 1.0, (v) => _burnStrength = v),
    ],
  ];

  List<Widget> _buildTiltShiftContent() => [
    _buildLocalToggle('틸트쉬프트', _tiltActive, (v) {
      setState(() => _tiltActive = v);
      _renderPreview();
    }),
    if (_tiltActive) ...[
      _lSlider('포커스', _tiltFocusCenter, 0.0, 1.0, (v) => _tiltFocusCenter = v),
      _lSlider('밴드폭', _tiltBandWidth, 0.05, 0.8, (v) => _tiltBandWidth = v),
      _lSlider('블러',   _tiltMaxBlur, 1.0, 20.0, (v) => _tiltMaxBlur = v),
    ],
  ];

  List<Widget> _buildLensBlurContent() => [
    _buildLocalToggle('렌즈 블러', _lensActive, (v) {
      setState(() => _lensActive = v);
      _renderPreview();
    }),
    if (_lensActive) ...[
      _lSlider('포커스', _lensFocusDepth, 0.0, 1.0, (v) => _lensFocusDepth = v),
      _lSlider('블러',  _lensMaxRadius, 1.0, 20.0, (v) => _lensMaxRadius = v),
    ],
  ];

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
    AdjustSliderItem(
      label: '구조감', icon: '◈',
      value: _params.structure, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(structure: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '명료도', icon: '◎',
      value: _params.clarity, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(clarity: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '톤 그늘', icon: '▼',
      value: _params.tonalShadows, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(tonalShadows: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '톤 미드', icon: '◆',
      value: _params.tonalMidtones, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(tonalMidtones: v)); _renderPreview(); },
    ),
    AdjustSliderItem(
      label: '톤 밝음', icon: '▲',
      value: _params.tonalHighlights, min: -100, max: 100,
      onChanged: (v) { setState(() => _params = _params.copyWith(tonalHighlights: v)); _renderPreview(); },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
              icon: backIcon(),
              onTap: () => context.pop(),
            ),
            const Spacer(),
            const Text(
              '편집',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnDark,
              ),
            ),
            const Spacer(),
            _IconBtn(
              icon: shareIcon(),
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
    return SafeArea(
      top: false,
      child: _buildBottomPanelContent(),
    );
  }

  Widget _buildBottomPanelContent() {
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
          ] else if (_tab == _EditorTab.adjust) ...[
            // WB 프리셋 행
            _WbPresetRow(
              onSelect: (preset) {
                setState(() => _params = preset.applyTo(_params));
                _renderPreview();
              },
            ),
            const SizedBox(height: 8),
            // B&W 토글
            _BnwToggle(
              enabled: _params.bnwEnabled,
              onToggle: (v) {
                setState(() => _params = _params.copyWith(bnwEnabled: v));
                _renderPreview();
              },
            ),
            const SizedBox(height: 4),
            AdjustParamsPanel(
              items: _sliderItems,
              selectedIndex: _adjustIndex,
              onSelectIndex: (i) => setState(() => _adjustIndex = i),
            ),
          ] else if (_tab == _EditorTab.curves) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CurveEditorPanel(
                curves: _curves,
                onChanged: (channel, data) {
                  setState(() {
                    _curves[channel] = data;
                    _params = _params.copyWith(
                      luminanceCurve: _curves[CurveChannel.luminance],
                      rgbCurve:       _curves[CurveChannel.rgb],
                      redCurve:       _curves[CurveChannel.red],
                      greenCurve:     _curves[CurveChannel.green],
                      blueCurve:      _curves[CurveChannel.blue],
                    );
                  });
                  _renderPreview();
                },
              ),
            ),
          ] else if (_tab == _EditorTab.effects) ...[
            _EffectsPanel(
              selected:  _effect,
              strength:  _effectStrength,
              onEffect: (e) {
                setState(() => _effect = e);
                _renderPreview();
              },
              onStrength: (v) {
                setState(() => _effectStrength = v);
                _renderPreview();
              },
            ),
          ] else if (_tab == _EditorTab.tools) ...[
            _ToolsPanel(
              subTab:    _toolsSubTab,
              cropRatio: _cropRatio,
              rotation:  _rotation,
              flipH:     _flipH,
              flipV:     _flipV,
              perspH:    _perspH,
              perspV:    _perspV,
              onSubTab: (t) => setState(() => _toolsSubTab = t),
              onCropRatio: (r) {
                setState(() => _cropRatio = r);
                _renderPreview();
              },
              onRotation: (v) { setState(() => _rotation = v); },
              onRotationEnd: (_) => _renderPreview(),
              onFlipH: () {
                setState(() => _flipH = !_flipH);
                _renderPreview();
              },
              onFlipV: () {
                setState(() => _flipV = !_flipV);
                _renderPreview();
              },
              onPerspH: (v) { setState(() => _perspH = v); _renderPreview(); },
              onPerspV: (v) { setState(() => _perspV = v); _renderPreview(); },
              onPerspReset: () { setState(() { _perspH = 0; _perspV = 0; }); _renderPreview(); },
            ),
          ] else if (_tab == _EditorTab.local) ...[
            _buildLocalPanel(),
          ] else if (_tab == _EditorTab.portrait) ...[
            _PortraitPanel(
              smooth:      _portraitSmooth,
              spotlight:   _portraitSpotlight,
              skinTone:    _skinTone,
              skinStrength:_skinToneStrength,
              onSmooth:    (v) { setState(() => _portraitSmooth = v); _renderPreview(); },
              onSpotlight: (v) { setState(() => _portraitSpotlight = v); _renderPreview(); },
              onSkinTone:  (t) { setState(() => _skinTone = t); _renderPreview(); },
              onSkinStrength:(v){ setState(() => _skinToneStrength = v); _renderPreview(); },
            ),
          ] else ...[
            _CreativePanel(
              blendImagePath: _blendImagePath,
              blendMode:      _blendMode,
              blendOpacity:   _blendOpacity,
              frameIndex:     _frameIndex,
              overlayText:    _overlayText,
              textSize:       _textSize,
              textColor:      _textColor,
              onPickBlend:    () async {
                final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (xFile != null && mounted) {
                  setState(() => _blendImagePath = xFile.path);
                  _renderPreview();
                }
              },
              onBlendMode:    (m) { setState(() => _blendMode = m); _renderPreview(); },
              onBlendOpacity: (v) { setState(() => _blendOpacity = v); _renderPreview(); },
              onFrameIndex:   (i) { setState(() => _frameIndex = i); },
              onText:         (t) { setState(() => _overlayText = t); },
              onTextSize:     (s) { setState(() => _textSize = s); },
              onTextColor:    (c) { setState(() => _textColor = c); },
            ),
          ],
          const SizedBox(height: 16),
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
          const SizedBox(width: 8),
          _TabBtn(
            label: '커브',
            icon: Icons.show_chart_rounded,
            selected: _tab == _EditorTab.curves,
            onTap: () => setState(() => _tab = _EditorTab.curves),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '이펙트',
            icon: Icons.auto_fix_high_rounded,
            selected: _tab == _EditorTab.effects,
            onTap: () => setState(() => _tab = _EditorTab.effects),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '도구',
            icon: Icons.crop_rounded,
            selected: _tab == _EditorTab.tools,
            onTap: () => setState(() => _tab = _EditorTab.tools),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '로컬',
            icon: Icons.brush_rounded,
            selected: _tab == _EditorTab.local,
            onTap: () => setState(() => _tab = _EditorTab.local),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '인물',
            icon: Icons.face_rounded,
            selected: _tab == _EditorTab.portrait,
            onTap: () => setState(() => _tab = _EditorTab.portrait),
          ),
          const SizedBox(width: 8),
          _TabBtn(
            label: '합성',
            icon: Icons.layers_rounded,
            selected: _tab == _EditorTab.creative,
            onTap: () => setState(() => _tab = _EditorTab.creative),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _params = AdjustParams.zero;
                _selectedPreset = null;
                _intensity = 1.0;
                _lutBytes = null;
                _effect = ArtisticEffect.none;
                _effectStrength = 1.0;
                _cropRatio = CropRatioPreset.free;
                _rotation  = 0.0;
                _flipH     = false;
                _flipV     = false;
                // Phase 6
                _selActive = false; _selBright = 0; _selContrast = 0; _selSat = 0; _selRadius = 0.3;
                _dbActive  = false; _dodgeStrength = 0.3; _burnStrength = 0.3;
                _tiltActive = false; _tiltFocusCenter = 0.5; _tiltBandWidth = 0.3; _tiltMaxBlur = 8;
                _lensActive = false; _lensFocusDepth = 0.0; _lensMaxRadius = 8;
                _perspH = 0.0; _perspV = 0.0;
                _portraitSmooth = 0; _portraitSpotlight = 0;
                _skinTone = SkinTone.none; _skinToneStrength = 50;
                _blendImagePath = null; _blendMode = bm.BlendMode.lighten;
                _blendOpacity = 0.5; _frameIndex = -1;
                _overlayText = ''; _textSize = 32;
              });
              _renderPreview();
            },
            child: const Text(
              '초기화',
              style: TextStyle(
                fontFamily: 'NotoSerif',
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
                  fontFamily: 'NotoSerif',
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
                  fontFamily: 'NotoSerif',
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
                fontFamily: 'NotoSerif',
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

// ── White Balance 프리셋 버튼 행 ──────────────────────────

class _WbPresetRow extends StatelessWidget {
  final ValueChanged<WhiteBalancePreset> onSelect;
  const _WbPresetRow({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: WhiteBalancePreset.values.map((preset) {
          return GestureDetector(
            onTap: () {
              hapticLight();
              onSelect(preset);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.oceanFoam.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                preset.label,
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 11,
                  color: AppColors.textOnDarkSub,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── B&W 토글 ────────────────────────────────────────────

class _BnwToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _BnwToggle({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text(
            'B&W',
            style: TextStyle(
              fontFamily: 'NotoSerif',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnDarkSub,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              hapticLight();
              onToggle(!enabled);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                color: enabled ? AppColors.oceanTeal : AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Align(
                alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: AppColors.cloudWhite,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phase 5: 기하학 변환 ──────────────────────────────────

enum _ToolsSubTab { crop, rotate, perspective }

enum CropRatioPreset {
  free, r1x1, r4x3, r3x4, r16x9, r9x16, r3x2, r2x3;

  String get label {
    switch (this) {
      case CropRatioPreset.free:  return '자유';
      case CropRatioPreset.r1x1:  return '1:1';
      case CropRatioPreset.r4x3:  return '4:3';
      case CropRatioPreset.r3x4:  return '3:4';
      case CropRatioPreset.r16x9: return '16:9';
      case CropRatioPreset.r9x16: return '9:16';
      case CropRatioPreset.r3x2:  return '3:2';
      case CropRatioPreset.r2x3:  return '2:3';
    }
  }

  double? get ratio {
    switch (this) {
      case CropRatioPreset.free:  return null;
      case CropRatioPreset.r1x1:  return 1.0;
      case CropRatioPreset.r4x3:  return 4 / 3;
      case CropRatioPreset.r3x4:  return 3 / 4;
      case CropRatioPreset.r16x9: return 16 / 9;
      case CropRatioPreset.r9x16: return 9 / 16;
      case CropRatioPreset.r3x2:  return 3 / 2;
      case CropRatioPreset.r2x3:  return 2 / 3;
    }
  }
}

class _ToolsPanel extends StatelessWidget {
  final _ToolsSubTab     subTab;
  final CropRatioPreset  cropRatio;
  final double           rotation;
  final bool             flipH;
  final bool             flipV;
  final double           perspH;
  final double           perspV;
  final ValueChanged<_ToolsSubTab>    onSubTab;
  final ValueChanged<CropRatioPreset> onCropRatio;
  final ValueChanged<double>          onRotation;
  final ValueChanged<double>          onRotationEnd;
  final VoidCallback                  onFlipH;
  final VoidCallback                  onFlipV;
  final ValueChanged<double>          onPerspH;
  final ValueChanged<double>          onPerspV;
  final VoidCallback                  onPerspReset;

  const _ToolsPanel({
    required this.subTab,
    required this.cropRatio,
    required this.rotation,
    required this.flipH,
    required this.flipV,
    required this.perspH,
    required this.perspV,
    required this.onSubTab,
    required this.onCropRatio,
    required this.onRotation,
    required this.onRotationEnd,
    required this.onFlipH,
    required this.onFlipV,
    required this.onPerspH,
    required this.onPerspV,
    required this.onPerspReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-tab bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _SubTabBtn(label: '크롭',    icon: Icons.crop_rounded,
                  selected: subTab == _ToolsSubTab.crop,
                  onTap: () => onSubTab(_ToolsSubTab.crop)),
              const SizedBox(width: 8),
              _SubTabBtn(label: '회전',    icon: Icons.rotate_90_degrees_cw_rounded,
                  selected: subTab == _ToolsSubTab.rotate,
                  onTap: () => onSubTab(_ToolsSubTab.rotate)),
              const SizedBox(width: 8),
              _SubTabBtn(label: '원근',    icon: Icons.transform_rounded,
                  selected: subTab == _ToolsSubTab.perspective,
                  onTap: () => onSubTab(_ToolsSubTab.perspective)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (subTab == _ToolsSubTab.crop) _buildCrop(context),
        if (subTab == _ToolsSubTab.rotate) _buildRotate(context),
        if (subTab == _ToolsSubTab.perspective) _buildPerspective(),
      ],
    );
  }

  Widget _buildCrop(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: CropRatioPreset.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = CropRatioPreset.values[i];
          final sel    = cropRatio == preset;
          return GestureDetector(
            onTap: () {
              hapticLight();
              onCropRatio(preset);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color:  sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel
                      ? AppColors.oceanFoam
                      : AppColors.oceanFoam.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                preset.label,
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? AppColors.cloudWhite : AppColors.textOnDarkSub,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRotate(BuildContext context) {
    return Column(
      children: [
        // 회전 슬라이더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.rotate_left_rounded,
                  size: 18, color: AppColors.textOnDarkTert),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.oceanFoam,
                    inactiveTrackColor: AppColors.oceanNavy,
                    thumbColor: AppColors.cloudWhite,
                    overlayColor: AppColors.oceanFoam.withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: rotation,
                    min: -45, max: 45,
                    divisions: 360,
                    label: '${rotation.round()}°',
                    onChanged: onRotation,
                    onChangeEnd: onRotationEnd,
                  ),
                ),
              ),
              const Icon(Icons.rotate_right_rounded,
                  size: 18, color: AppColors.textOnDarkTert),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '${rotation.round()}°',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    color: AppColors.textOnDarkSub,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 플립 버튼
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _FlipBtn(
                label: '좌우 반전',
                icon: Icons.flip_rounded,
                active: flipH,
                onTap: onFlipH,
              ),
              const SizedBox(width: 10),
              _FlipBtn(
                label: '상하 반전',
                icon: Icons.flip_rounded,  // rotate 90 visually
                active: flipV,
                onTap: onFlipV,
                rotate: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerspective() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _perspSlider('수평 기울기', perspH, onPerspH),
          _perspSlider('수직 기울기', perspV, onPerspV),
          if (perspH != 0 || perspV != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: GestureDetector(
                onTap: onPerspReset,
                child: const Text('초기화',
                  style: TextStyle(fontFamily: 'NotoSerif', fontSize: 12,
                      color: AppColors.oceanFoam)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _perspSlider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72,
            child: Text(label, style: const TextStyle(fontFamily: 'NotoSerif',
                fontSize: 12, color: AppColors.textOnDarkSub))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: value, min: -45, max: 45, divisions: 180,
                onChanged: onChanged),
            ),
          ),
          SizedBox(width: 36,
            child: Text('${value.round()}°', textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 11,
                  color: AppColors.textOnDarkTert))),
        ],
      ),
    );
  }
}

class _SubTabBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final bool     selected;
  final VoidCallback onTap;

  const _SubTabBtn({
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.oceanTeal : AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14,
                color: selected ? AppColors.cloudWhite : AppColors.textOnDarkTert),
            const SizedBox(width: 5),
            Text(label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.cloudWhite : AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final bool     active;
  final VoidCallback onTap;
  final bool     rotate;

  const _FlipBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.rotate = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        hapticLight();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.oceanTeal : AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppColors.oceanFoam
                : AppColors.oceanFoam.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: rotate ? 1.5708 : 0,  // 90° for vertical flip icon
              child: Icon(icon, size: 14,
                  color: active ? AppColors.cloudWhite : AppColors.textOnDarkSub),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.cloudWhite : AppColors.textOnDarkSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Phase 4: 아티스틱 이펙트 패널 ────────────────────────

class _EffectsPanel extends StatelessWidget {
  final ArtisticEffect selected;
  final double strength;
  final ValueChanged<ArtisticEffect> onEffect;
  final ValueChanged<double> onStrength;

  const _EffectsPanel({
    required this.selected,
    required this.strength,
    required this.onEffect,
    required this.onStrength,
  });

  static const _groups = [
    _EffectGroup('없음',   [ArtisticEffect.none]),
    _EffectGroup('필름',   [ArtisticEffect.grain, ArtisticEffect.grainyFilm,
                            ArtisticEffect.vintage, ArtisticEffect.retrolux]),
    _EffectGroup('드라마', [ArtisticEffect.drama1, ArtisticEffect.drama2,
                            ArtisticEffect.dramaBright1, ArtisticEffect.dramaBright2,
                            ArtisticEffect.dramaDark1, ArtisticEffect.dramaDark2]),
    _EffectGroup('HDR',    [ArtisticEffect.hdrFine, ArtisticEffect.hdrNature,
                            ArtisticEffect.hdrPeople, ArtisticEffect.hdrStrong]),
    _EffectGroup('기타',   [ArtisticEffect.glamourGlow, ArtisticEffect.grunge]),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이펙트 선택 스크롤 행
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _groups.fold(0, (s, g) => s + g.effects.length) +
                       _groups.length - 1, // separators
            separatorBuilder: (_, i) => const SizedBox(width: 12),
            itemBuilder: (context, flatIdx) {
              // flatten groups with separators
              int pos = 0;
              for (int g = 0; g < _groups.length; g++) {
                if (g > 0) {
                  if (pos == flatIdx) {
                    return _GroupDivider(label: _groups[g].label);
                  }
                  pos++;
                }
                for (final e in _groups[g].effects) {
                  if (pos == flatIdx) {
                    return _EffectChip(
                      effect:   e,
                      selected: e == selected,
                      onTap:    () {
                        hapticLight();
                        onEffect(e);
                      },
                    );
                  }
                  pos++;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        // 강도 슬라이더 (none이면 숨김)
        if (selected != ArtisticEffect.none) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  '강도',
                  style: TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    color: AppColors.textOnDarkSub,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.oceanFoam,
                      inactiveTrackColor: AppColors.oceanNavy,
                      thumbColor: AppColors.cloudWhite,
                      overlayColor: AppColors.oceanFoam.withValues(alpha: 0.2),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: strength,
                      min: 0.0, max: 1.0,
                      onChanged: onStrength,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${(strength * 100).round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EffectGroup {
  final String label;
  final List<ArtisticEffect> effects;
  const _EffectGroup(this.label, this.effects);
}

class _GroupDivider extends StatelessWidget {
  final String label;
  const _GroupDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 1, height: 32, color: AppColors.oceanNavy),
        const SizedBox(height: 4),
        Text(label,
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 9,
            color: AppColors.textOnDarkTert,
          ),
        ),
      ],
    );
  }
}

class _EffectChip extends StatelessWidget {
  final ArtisticEffect effect;
  final bool selected;
  final VoidCallback onTap;

  const _EffectChip({required this.effect, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        decoration: BoxDecoration(
          color: selected ? AppColors.oceanTeal : AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.oceanFoam
                : AppColors.oceanFoam.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _iconFor(effect),
              size: 20,
              color: selected ? AppColors.cloudWhite : AppColors.textOnDarkSub,
            ),
            const SizedBox(height: 4),
            Text(
              effect.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 9,
                height: 1.2,
                color: selected ? AppColors.cloudWhite : AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ArtisticEffect e) {
    switch (e) {
      case ArtisticEffect.none:        return Icons.block_rounded;
      case ArtisticEffect.grain:
      case ArtisticEffect.grainyFilm:  return Icons.grain_rounded;
      case ArtisticEffect.vintage:
      case ArtisticEffect.retrolux:    return Icons.camera_rounded;
      case ArtisticEffect.drama1:
      case ArtisticEffect.drama2:
      case ArtisticEffect.dramaBright1:
      case ArtisticEffect.dramaBright2:
      case ArtisticEffect.dramaDark1:
      case ArtisticEffect.dramaDark2:  return Icons.contrast_rounded;
      case ArtisticEffect.hdrFine:
      case ArtisticEffect.hdrNature:
      case ArtisticEffect.hdrPeople:
      case ArtisticEffect.hdrStrong:   return Icons.hdr_on_rounded;
      case ArtisticEffect.glamourGlow: return Icons.auto_awesome_rounded;
      case ArtisticEffect.grunge:      return Icons.texture_rounded;
    }
  }
}

// ── 탭 플레이스홀더 (Phase 5~9 도구용 자리 표시) ──────────

// ── Portrait Panel ────────────────────────────────────────

class _PortraitPanel extends StatelessWidget {
  final double smooth, spotlight, skinStrength;
  final SkinTone skinTone;
  final ValueChanged<double> onSmooth, onSpotlight, onSkinStrength;
  final ValueChanged<SkinTone> onSkinTone;

  const _PortraitPanel({
    required this.smooth, required this.spotlight,
    required this.skinTone, required this.skinStrength,
    required this.onSmooth, required this.onSpotlight,
    required this.onSkinTone, required this.onSkinStrength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('피부 스무딩', smooth, 0, 100, onSmooth),
        _row('얼굴 스포트라이트', spotlight, 0, 100, onSpotlight),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('피부 색조', style: TextStyle(fontFamily: 'NotoSerif',
              fontSize: 12, color: AppColors.textOnDarkSub)),
        ),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: SkinTone.values.map((t) {
              final sel = t == skinTone;
              return GestureDetector(
                onTap: () { hapticLight(); onSkinTone(t); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(t.label, style: TextStyle(fontFamily: 'NotoSerif',
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: sel ? AppColors.cloudWhite : AppColors.textOnDarkSub)),
                ),
              );
            }).toList(),
          ),
        ),
        if (skinTone != SkinTone.none) ...[
          const SizedBox(height: 4),
          _row('색조 강도', skinStrength, 0, 100, onSkinStrength),
        ],
      ],
    );
  }

  Widget _row(String label, double value, double min, double max, ValueChanged<double> onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(
              fontFamily: 'NotoSerif', fontSize: 12, color: AppColors.textOnDarkSub))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: value, min: min, max: max,
                  onChanged: onChange),
            ),
          ),
          SizedBox(width: 32, child: Text(value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 11,
                  color: AppColors.textOnDarkTert))),
        ],
      ),
    );
  }
}

// ── Creative Panel ────────────────────────────────────────

// frame asset list (small thumbnails)
const _frameAssets = [
  'assets/frames/hp_frame_00_small.png',
  'assets/frames/hp_frame_01_small.png',
  'assets/frames/hp_frame_02_small.png',
  'assets/frames/hp_frame_03_small.png',
  'assets/frames/hp_frame_04_small.png',
  'assets/frames/hp_frame_05_small.png',
  'assets/frames/hp_frame_06_small.png',
  'assets/frames/hp_frame_07_small.png',
  'assets/frames/hp_frame_08_small.png',
  'assets/frames/hp_frame_09_small.png',
  'assets/frames/hp_frame_10_small.png',
  'assets/frames/hp_frame_11_small.png',
  'assets/frames/hp_frame_12_small.png',
];

enum _CreativeSubTab { doubleExposure, frame, text }

class _CreativePanel extends StatefulWidget {
  final String? blendImagePath;
  final bm.BlendMode blendMode;
  final double blendOpacity;
  final int frameIndex;
  final String overlayText;
  final double textSize;
  final Color textColor;
  final VoidCallback onPickBlend;
  final ValueChanged<bm.BlendMode> onBlendMode;
  final ValueChanged<double> onBlendOpacity;
  final ValueChanged<int> onFrameIndex;
  final ValueChanged<String> onText;
  final ValueChanged<double> onTextSize;
  final ValueChanged<Color> onTextColor;

  const _CreativePanel({
    required this.blendImagePath, required this.blendMode,
    required this.blendOpacity, required this.frameIndex,
    required this.overlayText, required this.textSize, required this.textColor,
    required this.onPickBlend, required this.onBlendMode,
    required this.onBlendOpacity, required this.onFrameIndex,
    required this.onText, required this.onTextSize, required this.onTextColor,
  });

  @override
  State<_CreativePanel> createState() => _CreativePanelState();
}

class _CreativePanelState extends State<_CreativePanel> {
  _CreativeSubTab _sub = _CreativeSubTab.doubleExposure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // sub-tab row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _SubTabBtn(label: '이중 노출', icon: Icons.layers_rounded,
                selected: _sub == _CreativeSubTab.doubleExposure,
                onTap: () => setState(() => _sub = _CreativeSubTab.doubleExposure)),
              const SizedBox(width: 8),
              _SubTabBtn(label: '프레임', icon: Icons.photo_size_select_large_rounded,
                selected: _sub == _CreativeSubTab.frame,
                onTap: () => setState(() => _sub = _CreativeSubTab.frame)),
              const SizedBox(width: 8),
              _SubTabBtn(label: '텍스트', icon: Icons.text_fields_rounded,
                selected: _sub == _CreativeSubTab.text,
                onTap: () => setState(() => _sub = _CreativeSubTab.text)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (_sub == _CreativeSubTab.doubleExposure) _buildDoubleExposure()
        else if (_sub == _CreativeSubTab.frame) _buildFrame()
        else _buildText(),
      ],
    );
  }

  Widget _buildDoubleExposure() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: widget.onPickBlend,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.oceanFoam.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_rounded,
                      size: 18, color: AppColors.oceanFoam),
                  const SizedBox(width: 8),
                  Text(
                    widget.blendImagePath != null ? '이미지 변경' : '이미지 선택',
                    style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 13,
                        color: AppColors.oceanFoam),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.blendImagePath != null) ...[
          const SizedBox(height: 8),
          // Blend mode chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: bm.BlendMode.values.map((m) {
                final sel = m == widget.blendMode;
                return GestureDetector(
                  onTap: () { hapticLight(); widget.onBlendMode(m); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(m.label, style: TextStyle(fontFamily: 'NotoSerif',
                        fontSize: 12, color: sel ? AppColors.cloudWhite : AppColors.textOnDarkSub)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          _opacityRow(),
        ],
      ],
    );
  }

  Widget _opacityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 56,
            child: Text('불투명도', style: TextStyle(fontFamily: 'NotoSerif',
                fontSize: 12, color: AppColors.textOnDarkSub))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: widget.blendOpacity, min: 0, max: 1,
                  onChanged: widget.onBlendOpacity),
            ),
          ),
          SizedBox(width: 32, child: Text('${(widget.blendOpacity * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 11,
                  color: AppColors.textOnDarkTert))),
        ],
      ),
    );
  }

  Widget _buildFrame() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _frameAssets.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            // "없음" option
            final sel = widget.frameIndex == -1;
            return GestureDetector(
              onTap: () { hapticLight(); widget.onFrameIndex(-1); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? AppColors.oceanFoam
                      : AppColors.oceanFoam.withValues(alpha: 0.15)),
                ),
                child: const Center(child: Text('없음', style: TextStyle(
                    fontFamily: 'NotoSerif', fontSize: 11,
                    color: AppColors.textOnDarkSub))),
              ),
            );
          }
          final idx = i - 1;
          final sel = widget.frameIndex == idx;
          return GestureDetector(
            onTap: () { hapticLight(); widget.onFrameIndex(idx); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 64, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? AppColors.oceanFoam : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(_frameAssets[idx], fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppColors.oceanNavy)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: widget.onText,
            style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 14,
                color: AppColors.textOnDark),
            decoration: InputDecoration(
              hintText: '텍스트 입력…',
              hintStyle: const TextStyle(fontFamily: 'NotoSerif',
                  color: AppColors.textOnDarkTert),
              filled: true, fillColor: AppColors.oceanNavy,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 48,
                child: Text('크기', style: TextStyle(fontFamily: 'NotoSerif',
                    fontSize: 12, color: AppColors.textOnDarkSub))),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(
                    activeTrackColor: AppColors.oceanFoam,
                    inactiveTrackColor: AppColors.oceanNavy,
                    thumbColor: AppColors.cloudWhite,
                    trackHeight: 2.5,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(value: widget.textSize, min: 12, max: 96,
                      onChanged: widget.onTextSize),
                ),
              ),
              SizedBox(width: 36, child: Text(widget.textSize.round().toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 11,
                      color: AppColors.textOnDarkTert))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('색상', style: TextStyle(fontFamily: 'NotoSerif',
                  fontSize: 12, color: AppColors.textOnDarkSub)),
              const SizedBox(width: 12),
              ...[Colors.white, Colors.black, Colors.yellow, Colors.red,
                  Colors.blue, Colors.green].map((c) {
                final sel = widget.textColor == c;
                return GestureDetector(
                  onTap: () { hapticLight(); widget.onTextColor(c); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28, height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c, shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? AppColors.oceanFoam : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

