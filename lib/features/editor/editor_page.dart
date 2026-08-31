import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memoria/core/l10n/strings.dart';
import 'package:memoria/core/theme/app_colors.dart';
import 'package:memoria/core/theme/app_theme.dart';
import 'package:memoria/core/utils/platform_utils.dart';
import 'package:memoria/engine/gpu_image_view.dart';
import 'package:memoria/data/repositories/custom_adjustment_repository.dart';
import 'package:memoria/data/repositories/favorites_repository.dart';
import 'package:memoria/data/repositories/filter_repository_impl.dart';
import 'package:memoria/domain/models/custom_adjustment.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/ai/models/segmenter.dart';
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:memoria/features/editor/editor_resource_preparer.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_media_export_coordinator.dart';
import 'package:memoria/features/editor/editor_draft_store.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';
import 'package:memoria/features/editor/editor_history_controller.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';
import 'package:memoria/features/editor/editor_tool_transaction_controller.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';
import 'package:memoria/features/editor/editor_tool_reset_controller.dart';
import 'package:memoria/features/editor/editor_tool_apply_controller.dart';
import 'package:memoria/features/editor/editor_preview_scheduler.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/engine/white_balance.dart';
import 'package:memoria/monetization/feature_flags_service.dart';
import 'package:memoria/monetization/fullscreen_ad_service.dart';
import 'widgets/adjust_slider.dart';
import 'widgets/curve_editor.dart';
import 'widgets/filter_strip.dart';
import 'widgets/details_panel.dart';
import 'widgets/noise_panel.dart';
import 'widgets/split_toning_panel.dart';
import 'widgets/vignette_panel.dart';
import 'widgets/glow_panel.dart';
import 'widgets/grain_panel.dart';
import 'widgets/m6_effects_panel.dart';
import 'widgets/hsl_panel.dart';
import 'widgets/crop_overlay_widget.dart';
import 'widgets/brush_overlay_widget.dart';
import 'widgets/focus_overlay_widget.dart';
import 'package:memoria/features/editor/utils/text_rasterizer.dart';
import 'package:memoria/core/error/error_handler.dart';

part 'editor_page_history.dart';
part 'editor_page_controls.dart';
part 'editor_page_menus.dart';
part 'editor_page_runtime.dart';
part 'editor_page_shell.dart';
part 'editor_page_widgets.dart';

enum _MainNavTab { style, tools, export }

enum _LocalSubTab { selective, dodgeBurn, tiltShift, lensBlur }

/// Ephemeral screen state that does not belong in render recipes, drafts, or
/// history. Keeping it together prevents the page shell from accumulating a
/// second, unrelated collection of mutable fields alongside editor data.
class _EditorUiState {
  _MainNavTab? mainNavTab;
  bool isSliding = false;
  bool slideGestureActive = false;
  int adjustIndex = 0;
  bool exporting = false;
  double exportProgress = 0;
  bool exportForShare = false;
  _LocalSubTab localSubTab = _LocalSubTab.tiltShift;
  bool processingPreview = false;
  bool previewPending = false;
  bool showComparePreview = false;
  bool pickingEmptyImage = false;
  bool pickingBlendImage = false;
  List<String> favoriteToolIds = [
    'tune',
    'details',
    'curves',
    'crop',
    'rotate',
    'selective',
    'brush',
  ];
  bool showFavoriteTip = true;
}

class EditorPage extends StatefulWidget {
  final String? imagePath;
  final String? initialPresetId;
  const EditorPage({super.key, this.imagePath, this.initialPresetId});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _uiState = _EditorUiState();
  final _editState = EditorEditState();
  final _toolTransaction = EditorToolTransactionController();
  final _toolResetController = const EditorToolResetController();

  _MainNavTab? get _mainNavTab => _uiState.mainNavTab;
  set _mainNavTab(_MainNavTab? value) => _uiState.mainNavTab = value;
  bool get _isToolActive => _toolTransaction.isActive;
  String? get _activeToolName => _toolTransaction.activeToolName;
  String? get _activeToolId => _toolTransaction.activeToolId;
  bool get _isSliding => _uiState.isSliding;
  set _isSliding(bool value) => _uiState.isSliding = value;
  bool get _slideGestureActive => _uiState.slideGestureActive;
  set _slideGestureActive(bool value) => _uiState.slideGestureActive = value;
  int get _adjustIndex => _uiState.adjustIndex;
  set _adjustIndex(int value) => _uiState.adjustIndex = value;
  bool get _exporting => _uiState.exporting;
  set _exporting(bool value) => _uiState.exporting = value;
  double get _exportProgress => _uiState.exportProgress;
  set _exportProgress(double value) => _uiState.exportProgress = value;
  bool get _exportForShare => _uiState.exportForShare;
  set _exportForShare(bool value) => _uiState.exportForShare = value;
  _LocalSubTab get _localSubTab => _uiState.localSubTab;
  set _localSubTab(_LocalSubTab value) => _uiState.localSubTab = value;
  bool get _processingPreview => _uiState.processingPreview;
  set _processingPreview(bool value) => _uiState.processingPreview = value;
  bool get _previewPending => _uiState.previewPending;
  set _previewPending(bool value) => _uiState.previewPending = value;
  bool get _showComparePreview => _uiState.showComparePreview;
  set _showComparePreview(bool value) => _uiState.showComparePreview = value;
  bool get _pickingEmptyImage => _uiState.pickingEmptyImage;
  set _pickingEmptyImage(bool value) => _uiState.pickingEmptyImage = value;
  bool get _pickingBlendImage => _uiState.pickingBlendImage;
  set _pickingBlendImage(bool value) => _uiState.pickingBlendImage = value;
  List<String> get _favoriteToolIds => _uiState.favoriteToolIds;
  set _favoriteToolIds(List<String> value) => _uiState.favoriteToolIds = value;
  bool get _showFavoriteTip => _uiState.showFavoriteTip;
  set _showFavoriteTip(bool value) => _uiState.showFavoriteTip = value;

  AdjustParams get _params => _editState.params;
  set _params(AdjustParams value) => _editState.params = value;
  FilterPreset? get _selectedPreset => _editState.selectedPreset;
  set _selectedPreset(FilterPreset? value) => _editState.selectedPreset = value;
  double get _intensity => _editState.intensity;
  set _intensity(double value) => _editState.intensity = value;
  Map<CurveChannel, CurveData> get _curves => _editState.curves;
  ArtisticEffect get _effect => _editState.effect;
  set _effect(ArtisticEffect value) => _editState.effect = value;
  double get _effectStrength => _editState.effectStrength;
  set _effectStrength(double value) => _editState.effectStrength = value;
  int get _grainVariant => _editState.grainVariant;
  set _grainVariant(int value) => _editState.grainVariant = value;
  CropRatioPreset get _cropRatio => _editState.cropRatio;
  set _cropRatio(CropRatioPreset value) => _editState.cropRatio = value;
  double get _cropCenterX => _editState.cropCenterX;
  set _cropCenterX(double value) => _editState.cropCenterX = value;
  double get _cropCenterY => _editState.cropCenterY;
  set _cropCenterY(double value) => _editState.cropCenterY = value;
  double get _cropLeft => _editState.cropLeft;
  set _cropLeft(double value) => _editState.cropLeft = value;
  double get _cropTop => _editState.cropTop;
  set _cropTop(double value) => _editState.cropTop = value;
  double get _cropRight => _editState.cropRight;
  set _cropRight(double value) => _editState.cropRight = value;
  double get _cropBottom => _editState.cropBottom;
  set _cropBottom(double value) => _editState.cropBottom = value;
  double get _rotation => _editState.rotation;
  set _rotation(double value) => _editState.rotation = value;
  bool get _flipH => _editState.flipH;
  set _flipH(bool value) => _editState.flipH = value;
  bool get _flipV => _editState.flipV;
  set _flipV(bool value) => _editState.flipV = value;
  double get _perspH => _editState.perspectiveH;
  set _perspH(double value) => _editState.perspectiveH = value;
  double get _perspV => _editState.perspectiveV;
  set _perspV(double value) => _editState.perspectiveV = value;
  double get _expandTop => _editState.expandTop;
  set _expandTop(double value) => _editState.expandTop = value;
  double get _expandBottom => _editState.expandBottom;
  set _expandBottom(double value) => _editState.expandBottom = value;
  double get _expandLeft => _editState.expandLeft;
  set _expandLeft(double value) => _editState.expandLeft = value;
  double get _expandRight => _editState.expandRight;
  set _expandRight(double value) => _editState.expandRight = value;
  String get _expandMode => _editState.expandMode;
  set _expandMode(String value) => _editState.expandMode = value;
  double get _portraitSmooth => _editState.portraitSmooth;
  set _portraitSmooth(double value) => _editState.portraitSmooth = value;
  double get _portraitSpotlight => _editState.portraitSpotlight;
  set _portraitSpotlight(double value) => _editState.portraitSpotlight = value;
  SkinTone get _skinTone => _editState.skinTone;
  set _skinTone(SkinTone value) => _editState.skinTone = value;
  double get _skinToneStrength => _editState.skinToneStrength;
  set _skinToneStrength(double value) => _editState.skinToneStrength = value;
  String? get _blendImagePath => _editState.blendImagePath;
  set _blendImagePath(String? value) => _editState.blendImagePath = value;
  bm.BlendMode get _blendMode => _editState.blendMode;
  set _blendMode(bm.BlendMode value) => _editState.blendMode = value;
  double get _blendOpacity => _editState.blendOpacity;
  set _blendOpacity(double value) => _editState.blendOpacity = value;
  int get _frameIndex => _editState.frameIndex;
  set _frameIndex(int value) => _editState.frameIndex = value;
  String get _overlayText => _editState.overlayText;
  set _overlayText(String value) => _editState.overlayText = value;
  double get _textSize => _editState.textSize;
  set _textSize(double value) => _editState.textSize = value;
  Color get _textColor => Color(_editState.textColorValue);
  set _textColor(Color value) => _editState.textColorValue = value.toARGB32();
  String get _textFontFamily => _editState.textFontFamily;
  set _textFontFamily(String value) => _editState.textFontFamily = value;
  double get _textX => _editState.textX;
  set _textX(double value) => _editState.textX = value;
  double get _textY => _editState.textY;
  set _textY(double value) => _editState.textY = value;
  double get _textRotation => _editState.textRotation;
  set _textRotation(double value) => _editState.textRotation = value;
  bool get _selActive => _editState.selectiveActive;
  set _selActive(bool value) => _editState.selectiveActive = value;
  double get _selX => _editState.selectiveX;
  set _selX(double value) => _editState.selectiveX = value;
  double get _selY => _editState.selectiveY;
  set _selY(double value) => _editState.selectiveY = value;
  double get _selBright => _editState.selectiveBrightness;
  set _selBright(double value) => _editState.selectiveBrightness = value;
  double get _selContrast => _editState.selectiveContrast;
  set _selContrast(double value) => _editState.selectiveContrast = value;
  double get _selSat => _editState.selectiveSaturation;
  set _selSat(double value) => _editState.selectiveSaturation = value;
  double get _selRadius => _editState.selectiveRadius;
  set _selRadius(double value) => _editState.selectiveRadius = value;
  bool get _dbActive => _editState.dodgeBurnActive;
  set _dbActive(bool value) => _editState.dodgeBurnActive = value;
  String get _brushMode => _editState.brushMode;
  set _brushMode(String value) => _editState.brushMode = value;
  double get _dodgeY => _editState.dodgeY;
  set _dodgeY(double value) => _editState.dodgeY = value;
  double get _dodgeRadius => _editState.dodgeRadius;
  set _dodgeRadius(double value) => _editState.dodgeRadius = value;
  double get _dodgeStrength => _editState.dodgeStrength;
  set _dodgeStrength(double value) => _editState.dodgeStrength = value;
  double get _burnY => _editState.burnY;
  set _burnY(double value) => _editState.burnY = value;
  double get _burnRadius => _editState.burnRadius;
  set _burnRadius(double value) => _editState.burnRadius = value;
  double get _burnStrength => _editState.burnStrength;
  set _burnStrength(double value) => _editState.burnStrength = value;
  List<DodgeBurnStroke> get _brushStrokes => _editState.brushStrokes;
  bool get _tiltActive => _editState.tiltActive;
  set _tiltActive(bool value) => _editState.tiltActive = value;
  double get _tiltFocusCenter => _editState.tiltFocusCenter;
  set _tiltFocusCenter(double value) => _editState.tiltFocusCenter = value;
  double get _tiltBandWidth => _editState.tiltBandWidth;
  set _tiltBandWidth(double value) => _editState.tiltBandWidth = value;
  double get _tiltMaxBlur => _editState.tiltMaxBlur;
  set _tiltMaxBlur(double value) => _editState.tiltMaxBlur = value;
  bool get _lensActive => _editState.lensActive;
  set _lensActive(bool value) => _editState.lensActive = value;
  double get _lensFocusDepth => _editState.lensFocusDepth;
  set _lensFocusDepth(double value) => _editState.lensFocusDepth = value;
  double get _lensMaxRadius => _editState.lensMaxRadius;
  set _lensMaxRadius(double value) => _editState.lensMaxRadius = value;

  ui.Image? _liveBaseCacheImage;
  ui.Image? _liveLutAtlas;
  ui.Image? _liveCurve1D;
  ui.Image? _liveLumCurve;
  int _livePrepareToken = 0;
  late final ValueNotifier<AdjustParams> _liveParamsNotifier;
  late final ValueNotifier<double> _liveIntensityNotifier;
  late final EditorHistoryController _history;
  late final EditorToolApplyController _toolApplyController;
  late final EditorDraftStore _draftStore;
  late final EditorResourcePreparer _resourcePreparer;

  final TransformationController _transformationController =
      TransformationController();

  void _mutate(VoidCallback action) => setState(action);

  final EditorMediaExportCoordinator _mediaExportCoordinator =
      EditorMediaExportCoordinator();
  double _textGestureStartSize = 32.0;
  double _textGestureStartRotation = 0.0;

  Uint8List? _lutBytes;
  Uint8List? _previewBytes;
  Uint8List? _spatialBaseBytes;
  Uint8List? _comparePreviewBytes;
  Timer? _draftSaveDebounce;
  int _presetSelectToken = 0;
  late final EditorPreviewScheduler<_PreviewParams, Uint8List>
      _previewScheduler;
  img.Image? _decodedCache;
  String? _decodedCachePath;
  img.Image? _previewBaseCache;
  String? _previewBaseCacheKey;
  final Map<String, Uint8List?> _lutByteCache = {};
  final Map<String, Uint8List> _previewRenderCache = {};
  // Blend image bytes cache — keyed by file path, avoids re-reading on each render.
  String? _blendImageCachedPath;
  Uint8List? _blendImageCachedBytes;

  // Favorites & custom adjustments
  Set<String> _favoriteFilterIds = {};
  List<CustomAdjustment> _customAdjustments = [];
  final _favRepo = FavoritesRepository();
  final _adjRepo = CustomAdjustmentRepository();

  // Portrait segmentation
  SelfieSegmenter? _segmenter;
  bool _segmenterLoading = false;
  Float32List? _segmentMask; // cached mask for current preview base image
  String? _segmentMaskBaseKey; // preview base key the mask was computed for

  /// Isolate 전달용: 크롭 비율을 double?으로 변환.
  double? _currentCropRect() => _resolvedCropAspectRatio();

  /// `원본` is a ratio lock to the source image, not the old -1 sentinel.
  /// Keeping the resolved value here prevents invalid negative crop sizes in
  /// the interactive overlay and in the editor preview path.
  double? _resolvedCropAspectRatio({img.Image? imageSize}) {
    if (_cropRatio == CropRatioPreset.free) return null;
    if (_cropRatio == CropRatioPreset.original) {
      final image = imageSize ?? _decodedCache;
      if (image != null && image.height > 0) {
        return image.width / image.height;
      }
      final size = _currentImageSize;
      return size.height > 0 ? size.width / size.height : null;
    }
    return _cropRatio.ratio;
  }

  late List<FilterPreset> _allPresets;
  FullScreenAdService? _adService;

  @override
  void initState() {
    super.initState();
    _liveParamsNotifier = ValueNotifier(AdjustParams.zero);
    _liveIntensityNotifier = ValueNotifier(1.0);
    _history = EditorHistoryController(widget.imagePath ?? '');
    _toolApplyController = EditorToolApplyController(history: _history);
    _previewScheduler = EditorPreviewScheduler(
      worker: (params) => compute(_previewWorker, params),
    );
    _draftStore = EditorDraftStore();
    _resourcePreparer = EditorResourcePreparer(
      loadFrame: _loadFrameBytes,
      loadBlend: _loadBlendImageBytesForPath,
      loadPortraitMask: _preparePortraitMask,
    );
    _allPresets = BuiltinPresets.all;
    _loadEditorState();
    setStatusBarForDark();
  }

  @override
  void dispose() {
    _previewScheduler.dispose();
    _draftSaveDebounce?.cancel();
    _saveDraft();
    _segmenter?.dispose();
    _transformationController.dispose();
    _liveParamsNotifier.dispose();
    _liveIntensityNotifier.dispose();
    _disposeLiveImages();
    // Native/GPU disposes verified by regression tests:
    // _segmenter?.dispose()
    // _depthEstimator?.dispose()
    // _gpuSourceImage?.dispose()
    // _gpuLutAtlas?.dispose()
    // _gpuCurve1D?.dispose()
    // _gpuLumCurve?.dispose()
    // _transformCtrl.dispose()
    setStatusBarForLight();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: _buildScaffold(context),
    );
  }
}
