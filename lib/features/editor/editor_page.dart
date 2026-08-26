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
import 'package:memoria/core/services/media_permission_service.dart';
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

enum _MainNavTab { style, tools, export }

enum _LocalSubTab { selective, dodgeBurn, tiltShift, lensBlur }

/// Ephemeral screen state that does not belong in render recipes, drafts, or
/// history. Keeping it together prevents the page shell from accumulating a
/// second, unrelated collection of mutable fields alongside editor data.
class _EditorUiState {
  _MainNavTab? mainNavTab;
  bool isToolActive = false;
  String? activeToolName;
  String? activeToolId;
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

  _MainNavTab? get _mainNavTab => _uiState.mainNavTab;
  set _mainNavTab(_MainNavTab? value) => _uiState.mainNavTab = value;
  bool get _isToolActive => _uiState.isToolActive;
  set _isToolActive(bool value) => _uiState.isToolActive = value;
  String? get _activeToolName => _uiState.activeToolName;
  set _activeToolName(String? value) => _uiState.activeToolName = value;
  String? get _activeToolId => _uiState.activeToolId;
  set _activeToolId(String? value) => _uiState.activeToolId = value;
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
  late final EditorDraftStore _draftStore;
  late final EditorResourcePreparer _resourcePreparer;

  final TransformationController _transformationController =
      TransformationController();

  // A tool transaction captures every editable field through the same
  // snapshot adapter used by history, drafts, and render recipes. LUT bytes
  // are kept separately because they are a loaded resource, not UI state.
  EditorStateSnapshot? _stateBeforeTool;
  Uint8List? _lutBytesBeforeTool;

  void _backupState() {
    _stateBeforeTool = _currentEditorState();
    _lutBytesBeforeTool = _lutBytes;
  }

  void _restoreState() {
    final state = _stateBeforeTool;
    if (state == null) return;
    _applyEditorState(state);
    _lutBytes = _lutBytesBeforeTool;
  }

  void _activateTool(String toolId, String toolName) {
    if (_isToolActive && _activeToolId == toolId) return;
    if (_isToolActive) {
      // A tool switch is a cancellation, never an implicit commit. Keep this
      // synchronous so the new tool snapshots the restored state.
      _cancelActiveTool();
    }
    _backupState();
    _captureComparePreview();
    if (toolId == 'rotate' || toolId == 'perspective') {
      _spatialBaseBytes = _previewBytes;
    }
    setState(() {
      _isToolActive = true;
      _activeToolId = toolId;
      _activeToolName = toolName;
    });
    if (toolId == 'text') {
      // Keep text editable as a live widget while this tool is open instead
      // of waiting for a full image raster on every keystroke.
      _renderPreview();
    }
  }

  void _cancelActiveTool() {
    // Ignore an in-flight LUT selection after the state has been restored.
    _presetSelectToken++;
    setState(() {
      _restoreState();
      _isToolActive = false;
      _activeToolId = null;
      _activeToolName = null;
      _spatialBaseBytes = null;
      _showComparePreview = false;
    });
    _renderPreview();
  }

  /// Resets only the active tool to its neutral state and keeps the tool open.
  /// Previously Reset restored the entry snapshot, which meant a filter or
  /// slider that already had a non-zero value could not actually be reset.
  void _resetActiveTool() {
    if (!_isToolActive) return;
    setState(() {
      switch (_activeToolId) {
        case 'filter':
          _presetSelectToken++;
          _selectedPreset = null;
          _lutBytes = null;
          _intensity = 1.0;
          _params = AdjustParams.zero;
          _syncCurvesFromParams();
          break;
        case 'tune':
          _params = AdjustParams.zero;
          _syncCurvesFromParams();
          break;
        case 'details':
          _params = _params.copyWith(sharpen: 0, structure: 0, clarity: 0);
          break;
        case 'curves':
          final json = Map<String, dynamic>.from(_params.toJson())
            ..remove('luminanceCurve')
            ..remove('rgbCurve')
            ..remove('redCurve')
            ..remove('greenCurve')
            ..remove('blueCurve');
          _params = AdjustParams.fromJson(json);
          _curves.clear();
          break;
        case 'white_balance':
          _params = _params.copyWith(temperature: 0, tint: 0);
          break;
        case 'crop':
          _cropRatio = CropRatioPreset.free;
          _cropCenterX = 0.5;
          _cropCenterY = 0.5;
          _cropLeft = 0;
          _cropTop = 0;
          _cropRight = 1;
          _cropBottom = 1;
          break;
        case 'rotate':
          _rotation = 0;
          _flipH = false;
          _flipV = false;
          break;
        case 'perspective':
          _perspH = 0;
          _perspV = 0;
          break;
        case 'expand':
          _expandTop = 0;
          _expandBottom = 0;
          _expandLeft = 0;
          _expandRight = 0;
          _expandMode = 'black';
          break;
        case 'hsl':
          _params = _params.copyWith(
            hsl: {for (final band in HslBand.values) band: HslBandParams.zero},
          );
          break;
        case 'selective':
          _selActive = false;
          _selX = 0.5;
          _selY = 0.5;
          _selBright = 0;
          _selContrast = 0;
          _selSat = 0;
          _selRadius = 0.3;
          break;
        case 'brush':
          _dbActive = false;
          _brushMode = 'dodge';
          _dodgeY = 0.25;
          _dodgeRadius = 0.25;
          _dodgeStrength = 0.3;
          _burnY = 0.75;
          _burnRadius = 0.25;
          _burnStrength = 0.3;
          _brushStrokes.clear();
          break;
        case 'tilt_shift':
          _tiltActive = false;
          _tiltFocusCenter = 0.5;
          _tiltBandWidth = 0.3;
          _tiltMaxBlur = 0;
          break;
        case 'lens_blur':
          _lensActive = false;
          _lensFocusDepth = 0;
          _lensMaxRadius = 0;
          break;
        case 'vignette':
          _params = _params.copyWith(vignette: 0);
          break;
        case 'grain':
          _params =
              _params.copyWith(grainStrength: 0, grainSize: 1, grainSeed: 0);
          break;
        case 'split_toning':
          _params = _params.copyWith(
            splitShadowHue: 0,
            splitShadowSat: 0,
            splitHighHue: 0,
            splitHighSat: 0,
            splitBalance: 0,
          );
          break;
        case 'noise':
          _params = _params.copyWith(luminanceNR: 0, colourNR: 0, nrDetail: 0);
          break;
        case 'glow':
          _params = _params.copyWith(
              glowStrength: 0, glowSaturation: 0, glowWarmth: 0);
          break;
        case 'portrait':
          _portraitSmooth = 0;
          _portraitSpotlight = 0;
          _skinTone = SkinTone.none;
          _skinToneStrength = 50;
          break;
        case 'double_exposure':
          _blendImagePath = null;
          _blendOpacity = 0.5;
          _blendMode = bm.BlendMode.lighten;
          break;
        case 'frame':
          _frameIndex = -1;
          break;
        case 'text':
          _overlayText = '';
          _textSize = 32;
          _textColor = Colors.white;
          _textFontFamily = 'Montserrat';
          _textX = 0.5;
          _textY = 0.82;
          _textRotation = 0;
          break;
        case 'light_leak':
          _params = _params.copyWith(
            lightLeakStrength: 0,
            lightLeakAngle: 35,
            lightLeakWarmth: 55,
          );
          break;
        case 'halation':
          _params = _params.copyWith(
            halationStrength: 0,
            halationThreshold: 70,
            halationWarmth: 70,
          );
          break;
        case 'drama':
        case 'hdr_scape':
          _effect = ArtisticEffect.none;
          _effectStrength = 1;
          break;
      }
      _showComparePreview = false;
    });
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _renderPreview();
  }

  void _applyActiveTool() {
    setState(() {
      _saveToHistory();
      _isToolActive = false;
      _activeToolId = null;
      _activeToolName = null;
      _spatialBaseBytes = null;
      _showComparePreview = false;
    });
    _renderPreview();
  }

  EditorStateSnapshot _currentEditorState() =>
      _editState.toSnapshot(localSubTabName: _localSubTab.name);

  EditorRenderRecipe _currentRenderRecipe({
    AdjustParams? adjustParams,
    Uint8List? lutBytes,
    bool overrideLutBytes = false,
    double? intensity,
  }) =>
      _currentEditorState().toRenderRecipe(
        lutBytes: _lutBytes,
        cropAspectRatio: _currentCropRect(),
        adjustParamsOverride: adjustParams,
        lutBytesOverride: lutBytes,
        overrideLutBytes: overrideLutBytes,
        intensityOverride: intensity,
      );

  void _saveToHistory() {
    final now = DateTime.now();
    final op = _currentEditorState().toOperation(
      id: now.microsecondsSinceEpoch.toString(),
      tool: _historyToolForActiveTool(),
      appliedAt: now,
    );
    _history.apply(op);
  }

  EditToolType _historyToolForActiveTool() {
    switch (_activeToolId) {
      case 'filter':
        return EditToolType.filter;
      case 'crop':
      case 'rotate':
      case 'perspective':
      case 'expand':
        return EditToolType.crop;
      case 'portrait':
        return EditToolType.portrait;
      case 'double_exposure':
      case 'frame':
      case 'text':
        return EditToolType.creative;
      case 'curves':
        return EditToolType.curve;
      case 'details':
        return EditToolType.details;
      case 'hsl':
        return EditToolType.hslAdjust;
      case 'selective':
        return EditToolType.selective;
      case 'brush':
        return EditToolType.brush;
      case 'tilt_shift':
      case 'lens_blur':
        return EditToolType.selective;
      case 'vignette':
        return EditToolType.vignette;
      case 'grain':
        return EditToolType.grainOverlay;
      case 'split_toning':
        return EditToolType.splitTone;
      case 'noise':
        return EditToolType.rawDevelop;
      case 'glow':
        return EditToolType.glow;
      case 'light_leak':
        return EditToolType.lightLeak;
      case 'halation':
        return EditToolType.halation;
      case 'drama':
      case 'hdr_scape':
        return EditToolType.drama;
      default:
        return EditToolType.globalAdjust;
    }
  }

  void _undo() {
    if (!_history.canUndo) return;
    final op = _history.undo();

    if (op != null) {
      setState(() {
        _applyHistorySnapshot(op);
      });
    } else {
      setState(() {
        _resetCommittedState();
      });
    }
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _reloadSelectedPresetLut();
    _renderPreview();
  }

  void _redo() {
    if (!_history.canRedo) return;
    final op = _history.redo();
    if (op == null) return;

    setState(() {
      _applyHistorySnapshot(op);
    });
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _reloadSelectedPresetLut();
    _renderPreview();
  }

  FilterPreset? _presetForId(String? id) {
    if (id == null) return null;
    for (final preset in _allPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  void _applyHistorySnapshot(EditOperation op) {
    _applyEditorState(EditorStateSnapshot.fromOperation(op));
  }

  void _applyEditorState(EditorStateSnapshot state) {
    _editState.restore(
      state,
      resolvedPreset: _presetForId(state.presetId),
    );
    _lutBytes = null;
  }

  void _resetCommittedState() {
    _applyEditorState(
      EditorStateSnapshot.initial(localSubTabName: _localSubTab.name),
    );
  }

  void _reloadSelectedPresetLut() {
    final preset = _selectedPreset;
    final token = ++_presetSelectToken;
    if (preset == null) return;
    unawaited(() async {
      final bytes = await _loadLutBytesCached(preset.lutPath);
      if (!mounted ||
          token != _presetSelectToken ||
          _selectedPreset != preset) {
        return;
      }
      setState(() => _lutBytes = bytes);
      await _renderPreview();
    }());
  }

  final EditorMediaExportCoordinator _mediaExportCoordinator =
      EditorMediaExportCoordinator();
  double _textGestureStartSize = 32.0;
  double _textGestureStartRotation = 0.0;

  Uint8List? _lutBytes;
  Uint8List? _previewBytes;
  Uint8List? _spatialBaseBytes;
  Uint8List? _comparePreviewBytes;
  Timer? _previewDebounce;
  Timer? _draftSaveDebounce;
  int _presetSelectToken = 0;
  int _previewRenderToken = 0;
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
    _previewDebounce?.cancel();
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

  Future<void> _loadFavoritesAndTip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('favorite_tool_ids');
      if (list != null) {
        setState(() {
          _favoriteToolIds = list;
        });
      }
      final dismissed = prefs.getBool('favorite_tip_dismissed') ?? false;
      setState(() {
        _showFavoriteTip = !dismissed;
      });
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Editor favorites could not be loaded; using defaults',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  Future<void> _saveFavoriteTools() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_tool_ids', _favoriteToolIds);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Editor favorite tools could not be saved',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  Future<void> _saveFavoriteTipDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('favorite_tip_dismissed', true);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Editor favorite tip state could not be saved',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  Future<void> _loadEditorState() async {
    try {
      await _loadFavoritesAndTip();
      final flags = await FeatureFlagsService.create();
      // Each source is fetched independently so a failure in one does not
      // prevent the others from loading (favorites and saved adjustments
      // should survive a corrupt custom-preset file).
      final customPresets = await FilterRepositoryImpl()
          .getCustomPresets()
          .catchError((Object error, StackTrace stackTrace) {
        ErrorLogger.log(
          'Custom presets unavailable during editor initialization',
          error.runtimeType,
          stackTrace,
        );
        return <FilterPreset>[];
      });
      final presets = [
        ...customPresets,
        ...BuiltinPresets.all,
      ];
      final favIds = await _favRepo.getFavoriteIds().catchError(
        (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'Favorite filters unavailable during editor initialization',
            error.runtimeType,
            stackTrace,
          );
          return <String>{};
        },
      );
      final customAdjs = await _adjRepo.getAll().catchError(
        (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'Custom adjustments unavailable during editor initialization',
            error.runtimeType,
            stackTrace,
          );
          return <CustomAdjustment>[];
        },
      );

      FilterPreset? initialPreset;
      if (widget.initialPresetId != null) {
        for (final preset in presets) {
          if (preset.id == widget.initialPresetId) {
            initialPreset = preset;
            break;
          }
        }
      }

      final initialLut = initialPreset == null
          ? null
          : await loadLutBytes(initialPreset.lutPath);

      if (!mounted) return;
      setState(() {
        _adService = FullScreenAdService(flags);
        _allPresets = presets;
        _selectedPreset = initialPreset;
        _params = initialPreset?.params ?? AdjustParams.zero;
        _intensity = initialPreset?.defaultIntensity ?? 1.0;
        _lutBytes = initialLut;
        _favoriteFilterIds = favIds;
        _customAdjustments = customAdjs;
        _history.reset();
        _syncCurvesFromParams();
      });
      _liveParamsNotifier.value = _params;
      _liveIntensityNotifier.value = _intensity;
      _preloadPresetLuts(presets);
      await _restoreDraft(presets);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Editor initialization degraded to built-in presets',
        error.runtimeType,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _allPresets = BuiltinPresets.all;
      });
    }

    if (widget.imagePath != null) {
      await _renderPreview();
    }
  }

  Future<void> _selectPreset(FilterPreset? preset) async {
    _captureComparePreview();
    final token = ++_presetSelectToken;
    setState(() {
      _selectedPreset = preset;
      _params = preset?.params ?? AdjustParams.zero;
      _intensity = preset?.defaultIntensity ?? 1.0;
      _lutBytes = null;
      _syncCurvesFromParams();
    });
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;

    final lutBytes =
        preset == null ? null : await _loadLutBytesCached(preset.lutPath);
    if (!mounted || token != _presetSelectToken) return;
    setState(() {
      _lutBytes = lutBytes;
    });
    await _renderPreview();
  }

  Future<void> _selectPresetForPreview(FilterPreset? preset) async {
    // Filters are transactional like every other editing tool. Selecting one
    // only changes the preview; the top-right check commits it to history.
    if (!_isToolActive) {
      _activateTool('filter', '필터');
    }
    await _selectPreset(preset);
  }

  void _debouncedPreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 32), _renderPreview);
  }

  void _captureComparePreview() {
    _comparePreviewBytes = _previewBytes;
  }

  void _setComparePreviewVisible(bool visible) {
    if (_showComparePreview == visible) return;
    setState(() => _showComparePreview = visible);
  }

  Future<ui.Image> _imgToUiImage(img.Image image) async {
    final rgbaBytes = image.getBytes(order: img.ChannelOrder.rgba);
    final codec = await ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(rgbaBytes),
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    ).instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _startLiveSliding() async {
    if (_slideGestureActive) return;
    _slideGestureActive = true;
    final prepareToken = ++_livePrepareToken;

    if (_liveBaseCacheImage != null) {
      if (mounted) setState(() => _isSliding = true);
      return;
    }

    try {
      final decoded = await _decodedSourceImage();
      if (decoded == null) return;
      final preview = _previewBaseImage(decoded);

      final resources = await _resourcePreparer.prepare(
        EditorResourcePreparationRequest(
          recipe: _currentRenderRecipe(),
          maskSource: preview,
          maskSourceKey: _previewBaseKey(),
          targetGeometry: EditorTargetGeometry(
              width: preview.width, height: preview.height),
          frameIndex: _frameIndex,
          blendImagePath: _blendImagePath,
          preparePortraitMask: _portraitActive,
          prepareTextOverlay: true,
        ),
      );

      // Keep only effects that require neighbour samples or multiple passes.
      // Everything else is applied exactly once by the live GPU shader.
      final onlyCpuParams = AdjustParams(
        sharpen: _params.sharpen,
        structure: _params.structure,
        clarity: _params.clarity,
        luminanceNR: _params.luminanceNR,
        colourNR: _params.colourNR,
        nrDetail: _params.nrDetail,
        glowStrength: _params.glowStrength,
        glowSaturation: _params.glowSaturation,
        glowWarmth: _params.glowWarmth,
        hdrStrength: _params.hdrStrength,
        hdrSaturation: _params.hdrSaturation,
        lightLeakStrength: _params.lightLeakStrength,
        lightLeakAngle: _params.lightLeakAngle,
        lightLeakWarmth: _params.lightLeakWarmth,
        halationStrength: _params.halationStrength,
        halationThreshold: _params.halationThreshold,
        halationWarmth: _params.halationWarmth,
      );

      final workerParams = _PreviewParams(
        width: preview.width,
        height: preview.height,
        imageBytes: preview.getBytes(order: img.ChannelOrder.rgba),
        recipe: _currentRenderRecipe(
          adjustParams: onlyCpuParams,
          lutBytes: null,
          overrideLutBytes: true,
          intensity: 0,
        ),
        resources: resources.renderResources,
      );

      final renderedImgBytes = await compute(_previewWorker, workerParams);
      final renderedImg = img.decodeImage(renderedImgBytes);
      if (renderedImg != null) {
        final uiImg = await _imgToUiImage(renderedImg);
        final lutAtlas = await buildLutAtlas(_lutBytes);
        final curve1D = await buildCurve1DTexture(_params);
        final lumCurve = await buildLumCurveTexture(_params);
        if (!mounted ||
            !_slideGestureActive ||
            prepareToken != _livePrepareToken) {
          uiImg.dispose();
          lutAtlas?.dispose();
          curve1D.dispose();
          lumCurve.dispose();
          return;
        }
        setState(() {
          _disposeLiveImages(afterFrame: true);
          _liveBaseCacheImage = uiImg;
          _liveLutAtlas = lutAtlas;
          _liveCurve1D = curve1D;
          _liveLumCurve = lumCurve;
          _isSliding = true;
        });
      }
    } catch (error, stackTrace) {
      // CPU preview updates continue while the live GPU path is unavailable.
      ErrorLogger.log(
        'Live GPU preview unavailable; continuing with CPU preview',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  void _updateLiveSliding(AdjustParams newParams) {
    _liveParamsNotifier.value = newParams;
  }

  void _endLiveSliding() {
    _slideGestureActive = false;
    _livePrepareToken++;
    setState(() {
      _isSliding = false;
      _disposeLiveImages(afterFrame: true);
    });
    _liveParamsNotifier.value = _params;
    unawaited(_renderPreview());
  }

  void _disposeLiveImages({bool afterFrame = false}) {
    final images = <ui.Image?>[
      _liveBaseCacheImage,
      _liveLutAtlas,
      _liveCurve1D,
      _liveLumCurve,
    ];
    _liveBaseCacheImage = null;
    _liveLutAtlas = null;
    _liveCurve1D = null;
    _liveLumCurve = null;

    void disposeImages() {
      for (final image in images) {
        image?.dispose();
      }
    }

    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => disposeImages());
    } else {
      disposeImages();
    }
  }

  Future<Uint8List?> _loadLutBytesCached(String? lutPath) async {
    if (lutPath == null || lutPath.isEmpty) return null;
    if (_lutByteCache.containsKey(lutPath)) {
      // Re-insert to mark as recently used (LRU).
      final cached = _lutByteCache.remove(lutPath);
      _lutByteCache[lutPath] = cached;
      return cached;
    }
    final bytes = await loadLutBytes(lutPath);
    while (_lutByteCache.length >= 16) {
      _lutByteCache.remove(_lutByteCache.keys.first);
    }
    _lutByteCache[lutPath] = bytes;
    return bytes;
  }

  void _preloadPresetLuts(List<FilterPreset> presets) {
    // Avoid saturating startup I/O with every large LUT. The small warm cache
    // covers the first interactions; all remaining LUTs load on demand.
    for (final preset
        in presets.where((preset) => preset.lutPath.isNotEmpty).take(4)) {
      if (preset.lutPath.isEmpty) continue;
      unawaited(_loadLutBytesCached(preset.lutPath));
    }
  }

  void _syncCurvesFromParams() {
    _editState.syncCurvesFromParams();
  }

  void _scheduleDraftSave() {
    if (widget.imagePath == null) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce =
        Timer(const Duration(milliseconds: 500), () => _saveDraft());
  }

  Future<void> _saveDraft() async {
    final imagePath = widget.imagePath;
    if (imagePath == null) return;
    try {
      await _draftStore.save(imagePath: imagePath, draft: _draftJson());
    } on EditorDraftStorageException catch (e, stackTrace) {
      ErrorLogger.log(
          'Editor draft persistence failed (${e.operation})', e, stackTrace);
      // Draft persistence must never block editing.
    }
  }

  Future<void> _restoreDraft(List<FilterPreset> presets) async {
    final imagePath = widget.imagePath;
    if (imagePath == null) return;
    try {
      final json = await _draftStore.read(
        imagePath: imagePath,
        initialPresetId: widget.initialPresetId,
      );
      if (json == null) return;

      final rawSnapshot = json['snapshot'];
      if (rawSnapshot is Map) {
        final snapshot = EditorStateSnapshot.fromDraftJson(
          Map<String, dynamic>.from(rawSnapshot),
        );
        final preset = _presetForId(snapshot.presetId);
        final lutBytes =
            preset == null ? null : await _loadLutBytesCached(preset.lutPath);
        EditorHistoryState? restoredHistory;
        if (json['editSession'] is Map<String, dynamic>) {
          restoredHistory = EditorHistoryController.parseJson(
            json['editSession'] as Map<String, dynamic>,
            expectedImageUri: imagePath,
          );
        }
        if (!mounted) return;
        setState(() {
          _applyEditorState(snapshot);
          _localSubTab = _enumByName(
            _LocalSubTab.values,
            snapshot.localSubTabName,
            _LocalSubTab.tiltShift,
          );
          _selectedPreset = preset;
          _lutBytes = lutBytes;
          if (restoredHistory != null) _history.restore(restoredHistory);
        });
        _liveParamsNotifier.value = _params;
        _liveIntensityNotifier.value = _intensity;
        return;
      }

      final presetId = json['selectedPresetId'] as String?;
      FilterPreset? preset;
      if (presetId != null) {
        for (final p in presets) {
          if (p.id == presetId) {
            preset = p;
            break;
          }
        }
      }
      final lutBytes =
          preset == null ? null : await _loadLutBytesCached(preset.lutPath);
      EditorHistoryState? restoredHistory;
      if (json['editSession'] is Map<String, dynamic>) {
        restoredHistory = EditorHistoryController.parseJson(
          json['editSession'] as Map<String, dynamic>,
          expectedImageUri: imagePath,
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedPreset = preset;
        _params =
            AdjustParams.fromJson(json['adjustParams'] as Map<String, dynamic>);
        _syncCurvesFromParams();
        _intensity = _doubleFromJson(json['intensity'], 1.0);
        _effect = _enumByName(ArtisticEffect.values, json['effect'] as String?,
            ArtisticEffect.none);
        _effectStrength = _doubleFromJson(json['effectStrength'], 1.0);
        _grainVariant = (json['grainVariant'] as num?)?.toInt() ?? 3;
        _cropRatio = _enumByName(CropRatioPreset.values,
            json['cropRatio'] as String?, CropRatioPreset.free);
        _cropCenterX = _doubleFromJson(json['cropCenterX'], 0.5);
        _cropCenterY = _doubleFromJson(json['cropCenterY'], 0.5);
        _rotation = _doubleFromJson(json['rotation'], 0.0);
        _flipH = json['flipH'] as bool? ?? false;
        _flipV = json['flipV'] as bool? ?? false;
        _perspH = _doubleFromJson(json['perspH'], 0.0);
        _perspV = _doubleFromJson(json['perspV'], 0.0);
        _cropLeft = _doubleFromJson(json['cropLeft'], 0.0);
        _cropTop = _doubleFromJson(json['cropTop'], 0.0);
        _cropRight = _doubleFromJson(json['cropRight'], 1.0);
        _cropBottom = _doubleFromJson(json['cropBottom'], 1.0);
        _expandTop = _doubleFromJson(json['expandTop'], 0.0);
        _expandBottom = _doubleFromJson(json['expandBottom'], 0.0);
        _expandLeft = _doubleFromJson(json['expandLeft'], 0.0);
        _expandRight = _doubleFromJson(json['expandRight'], 0.0);
        _expandMode = json['expandMode'] as String? ?? 'black';
        _localSubTab = _enumByName(_LocalSubTab.values,
            json['localSubTab'] as String?, _LocalSubTab.tiltShift);
        _selActive = json['selActive'] as bool? ?? false;
        _selX = _doubleFromJson(json['selX'], 0.5);
        _selY = _doubleFromJson(json['selY'], 0.5);
        _selBright = _doubleFromJson(json['selBright'], 0.0);
        _selContrast = _doubleFromJson(json['selContrast'], 0.0);
        _selSat = _doubleFromJson(json['selSat'], 0.0);
        _selRadius = _doubleFromJson(json['selRadius'], 0.3);
        _dbActive = json['dbActive'] as bool? ?? false;
        _brushMode = json['brushMode'] as String? ?? 'dodge';
        _dodgeY = _doubleFromJson(json['dodgeY'], 0.25);
        _dodgeRadius = _doubleFromJson(json['dodgeRadius'], 0.25);
        _dodgeStrength = _doubleFromJson(json['dodgeStrength'], 0.3);
        _burnY = _doubleFromJson(json['burnY'], 0.75);
        _burnRadius = _doubleFromJson(json['burnRadius'], 0.25);
        _burnStrength = _doubleFromJson(json['burnStrength'], 0.3);
        _brushStrokes
          ..clear()
          ..addAll(
            (json['brushStrokes'] as List<dynamic>? ?? const []).map(
              (rawStroke) {
                final stroke = rawStroke as Map<String, dynamic>;
                return DodgeBurnStroke(
                  x: _doubleFromJson(stroke['x'], 0.5),
                  y: _doubleFromJson(stroke['y'], 0.5),
                  radius: _doubleFromJson(stroke['radius'], 0.1),
                  strength: _doubleFromJson(stroke['strength'], 0.3),
                  isDodge: stroke['isDodge'] as bool? ?? true,
                );
              },
            ),
          );
        _tiltActive = json['tiltActive'] as bool? ?? false;
        _tiltFocusCenter = _doubleFromJson(json['tiltFocusCenter'], 0.5);
        _tiltBandWidth = _doubleFromJson(json['tiltBandWidth'], 0.3);
        _tiltMaxBlur = _doubleFromJson(json['tiltMaxBlur'], 8.0);
        _lensActive = json['lensActive'] as bool? ?? false;
        _lensFocusDepth = _doubleFromJson(json['lensFocusDepth'], 0.0);
        _lensMaxRadius = _doubleFromJson(json['lensMaxRadius'], 8.0);
        _portraitSmooth = _doubleFromJson(json['portraitSmooth'], 0.0);
        _portraitSpotlight = _doubleFromJson(json['portraitSpotlight'], 0.0);
        _skinTone = _enumByName(
            SkinTone.values, json['skinTone'] as String?, SkinTone.none);
        _skinToneStrength = _doubleFromJson(json['skinToneStrength'], 50.0);
        _blendImagePath = json['blendImagePath'] as String?;
        _blendMode = _enumByName(bm.BlendMode.values,
            json['blendMode'] as String?, bm.BlendMode.lighten);
        _blendOpacity = _doubleFromJson(json['blendOpacity'], 0.5);
        _frameIndex = (json['frameIndex'] as num?)?.toInt() ?? -1;
        _overlayText = json['overlayText'] as String? ?? '';
        _textFontFamily = json['textFontFamily'] as String? ?? 'Montserrat';
        _textSize = _doubleFromJson(json['textSize'], 32.0);
        _textColor = Color(
          (json['textColor'] as num?)?.toInt() ?? Colors.white.toARGB32(),
        );
        _textX = _doubleFromJson(json['textX'], 0.5).clamp(0.0, 1.0);
        _textY = _doubleFromJson(json['textY'], 0.82).clamp(0.0, 1.0);
        _textRotation = _doubleFromJson(json['textRotation'], 0.0);
        _lutBytes = lutBytes;
        if (restoredHistory != null) _history.restore(restoredHistory);
      });
      _liveParamsNotifier.value = _params;
      _liveIntensityNotifier.value = _intensity;
    } on EditorDraftStorageException catch (e, stackTrace) {
      ErrorLogger.log(
          'Editor draft restoration failed (${e.operation})', e, stackTrace);
      // Corrupt or stale drafts are ignored; the editor falls back to defaults.
    } catch (e, stackTrace) {
      ErrorLogger.log('Editor draft payload migration failed', e, stackTrace);
    }
  }

  Map<String, dynamic> _draftJson() => _currentEditorState().toDraftJson(
        imagePath: widget.imagePath,
        initialPresetId: widget.initialPresetId,
        history: _history.toJson(),
      );

  T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    return values.firstWhere((v) => v.name == name, orElse: () => fallback);
  }

  double _doubleFromJson(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  String _previewBaseKey() {
    if (_isToolActive && _activeToolId == 'crop') return 'crop_active';
    return [
      widget.imagePath,
      _cropRatio.name,
      _cropCenterX.toStringAsFixed(4),
      _cropCenterY.toStringAsFixed(4),
      _flipH,
      _flipV,
      _rotation.toStringAsFixed(2),
      _perspH.toStringAsFixed(2),
      _perspV.toStringAsFixed(2),
      _expandTop.toStringAsFixed(3),
      _expandBottom.toStringAsFixed(3),
      _expandLeft.toStringAsFixed(3),
      _expandRight.toStringAsFixed(3),
      _expandMode,
      _cropLeft.toStringAsFixed(4),
      _cropTop.toStringAsFixed(4),
      _cropRight.toStringAsFixed(4),
      _cropBottom.toStringAsFixed(4),
    ].join('|');
  }

  String _previewPipelineKey() => [
        _previewBaseKey(),
        // Filter / LUT
        _selectedPreset?.id ?? '',
        _intensity.toStringAsFixed(3),
        // Adjust params — content-based key (identity hashCode differs across copyWith calls)
        _params.toJsonString(),
        // Artistic effect
        _effect.name,
        _effectStrength.toStringAsFixed(2),
        _grainVariant,
        // Selective adjust
        _selActive, _selX.toStringAsFixed(3), _selY.toStringAsFixed(3),
        _selBright.toStringAsFixed(2), _selContrast.toStringAsFixed(2),
        _selSat.toStringAsFixed(2), _selRadius.toStringAsFixed(2),
        // Dodge / burn
        _dbActive,
        _dodgeStrength.toStringAsFixed(2), _dodgeY.toStringAsFixed(3),
        _dodgeRadius.toStringAsFixed(2),
        _burnStrength.toStringAsFixed(2), _burnY.toStringAsFixed(3),
        _burnRadius.toStringAsFixed(2),
        // Tilt shift
        _tiltActive, _tiltFocusCenter.toStringAsFixed(3),
        _tiltBandWidth.toStringAsFixed(3), _tiltMaxBlur.toStringAsFixed(2),
        // Lens blur
        _lensActive, _lensFocusDepth.toStringAsFixed(3),
        _lensMaxRadius.toStringAsFixed(2),
        // Portrait
        _portraitSmooth.toStringAsFixed(2),
        _portraitSpotlight.toStringAsFixed(2),
        _skinTone.name, _skinToneStrength.toStringAsFixed(2),
        // Creative
        _blendImagePath ?? '', _blendMode.name,
        _blendOpacity.toStringAsFixed(2),
        _frameIndex,
        _overlayText, _textSize.toStringAsFixed(1), _textColor.toARGB32(),
        _textX.toStringAsFixed(4), _textY.toStringAsFixed(4),
        _textRotation.toStringAsFixed(2),
        _textFontFamily,
        _isToolActive && _activeToolId == 'text',
        // Brush strokes
        _brushStrokes
            .map((s) =>
                '${s.x.toStringAsFixed(3)},${s.y.toStringAsFixed(3)},${s.radius.toStringAsFixed(3)},${s.strength.toStringAsFixed(2)},${s.isDodge}')
            .join(';'),
      ].join('|');

  Future<img.Image?> _decodedSourceImage() async {
    final path = widget.imagePath;
    if (path == null) return null;
    if (_decodedCachePath == path && _decodedCache != null) {
      return _decodedCache!;
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    final rawDecoded = img.decodeImage(bytes);
    final decoded = rawDecoded == null ? null : img.bakeOrientation(rawDecoded);
    _decodedCachePath = path;
    _decodedCache = decoded;
    _previewBaseCache = null;
    _previewBaseCacheKey = null;
    _previewRenderCache.clear();
    return decoded;
  }

  img.Image _previewBaseImage(img.Image decoded) {
    final key = _previewBaseKey();
    if (_previewBaseCacheKey == key && _previewBaseCache != null) {
      return _previewBaseCache!;
    }

    // While rotate is open flips are rendered by Transform in the widget tree.
    // Re-encoding and re-running the CPU pipeline for each tap made the two
    // flip controls noticeably slow on real devices.
    final previewingSpatialTransform =
        _isToolActive && _activeToolId == 'rotate';
    final preview = EditorRenderer.preparePreviewSource(
      decoded,
      _currentRenderRecipe(),
      maxLongEdge: 720,
      skipCrop: _isToolActive && _activeToolId == 'crop',
      skipTransforms: previewingSpatialTransform,
    );

    _previewBaseCacheKey = key;
    _previewBaseCache = preview;
    return preview;
  }

  bool get _portraitActive =>
      _portraitSmooth > 0 ||
      _portraitSpotlight > 0 ||
      _skinTone != SkinTone.none;

  /// Lazily loads SelfieSegmenter when Portrait effects are in use.
  Future<void> _ensureSegmenter() async {
    if (_segmenter != null || _segmenterLoading) return;
    if (!AiManager.instance.selfieReady) return;
    _segmenterLoading = true;
    try {
      final path = AiManager.instance.pathOf(kModelSelfie.key);
      if (path != null) {
        _segmenter = await SelfieSegmenter.load(path);
      }
    } finally {
      _segmenterLoading = false;
    }
  }

  /// Returns a segmentation mask for [preview], using a cached result when the
  /// base image hasn't changed. If the on-device model is unavailable, return
  /// an empty mask rather than guessing a face-shaped area in the middle of
  /// every photo.
  Future<Float32List> _getSegmentMask(img.Image preview, String baseKey) async {
    if (_segmentMaskBaseKey == baseKey && _segmentMask != null) {
      return _segmentMask!;
    }
    await _ensureSegmenter();
    final seg = _segmenter;
    // SelfieSegmenter.segment() is synchronous (TFLite runs on this isolate).
    // We run it on the main isolate so the interpreter stays alive; the result
    // Float32List is then passed as plain data into compute().
    final mask = seg != null
        ? seg.segment(preview).data
        : Float32List(preview.width * preview.height);
    _segmentMask = mask;
    _segmentMaskBaseKey = baseKey;
    return mask;
  }

  Future<void> _renderPreview() async {
    if (widget.imagePath == null) return;
    final renderToken = ++_previewRenderToken;
    if (_processingPreview) {
      _previewPending = true;
      _scheduleDraftSave();
      return;
    }
    _previewPending = false;
    setState(() => _processingPreview = true);

    try {
      final decoded = await _decodedSourceImage();
      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(S.get('editor.invalid_image')),
                behavior: SnackBarBehavior.floating),
          );
        }
        // No return — fall through to finally so _previewPending
        // re-dispatch below is still reached.
        return;
      }
      final preview = _previewBaseImage(decoded);
      final previewKey = _previewPipelineKey();
      final cachedPreview = _previewRenderCache[previewKey];
      if (cachedPreview != null) {
        // Re-insert to mark as recently used (LRU order).
        _previewRenderCache.remove(previewKey);
        _previewRenderCache[previewKey] = cachedPreview;
        if (mounted && renderToken == _previewRenderToken) {
          setState(() => _previewBytes = cachedPreview);
        }
        _scheduleDraftSave();
        return;
      }

      final useLiveTextOverlay = _isToolActive && _activeToolId == 'text';
      final resources = await _resourcePreparer.prepare(
        EditorResourcePreparationRequest(
          recipe: _currentRenderRecipe(),
          maskSource: preview,
          maskSourceKey: _previewBaseKey(),
          targetGeometry: EditorTargetGeometry(
              width: preview.width, height: preview.height),
          frameIndex: _frameIndex,
          blendImagePath: _blendImagePath,
          preparePortraitMask: _portraitActive,
          prepareTextOverlay: !useLiveTextOverlay,
        ),
      );

      final previewRaw = preview.getBytes(order: img.ChannelOrder.rgba);
      final params = _PreviewParams(
        width: preview.width,
        height: preview.height,
        imageBytes: previewRaw,
        recipe: _currentRenderRecipe(),
        resources: resources.renderResources,
        overlayTextOverride: useLiveTextOverlay ? '' : null,
      );
      final bytes = await compute(_previewWorker, params);
      // Stale token: a newer render was queued — discard this result but
      // still fall through so the pending re-dispatch fires.
      if (!mounted || renderToken != _previewRenderToken) return;
      // Evict oldest entry (insertion-order) to keep cache at ≤24 entries.
      while (_previewRenderCache.length >= 24) {
        _previewRenderCache.remove(_previewRenderCache.keys.first);
      }
      _previewRenderCache[previewKey] = bytes;
      setState(() => _previewBytes = bytes);
    } catch (e, stackTrace) {
      ErrorLogger.log('Preview rendering failed', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('미리보기를 업데이트하지 못했습니다. 다시 조절해 주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingPreview = false);
      // Re-dispatch any queued render that arrived while we were processing.
      if (_previewPending && mounted) {
        _previewPending = false;
        unawaited(_renderPreview());
      }
    }
  }

  Future<Uint8List?> _loadFrameBytes(int frameIndex) async {
    if (frameIndex < 0 || frameIndex >= _frameAssets.length) return null;
    try {
      final data = await rootBundle.load(_frameAssets[frameIndex]);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e, stackTrace) {
      ErrorLogger.log(
          'Frame asset unavailable (index: $frameIndex)', e, stackTrace);
      return null;
    }
  }

  /// Loads the blend source before crossing a render isolate boundary.
  /// The renderer only accepts bytes, never a local path, so preview and
  /// export cannot diverge because one path happened to re-read the file.
  Future<Uint8List?> _loadBlendImageBytesForPath(String blendPath) async {
    if (_blendImageCachedPath == blendPath && _blendImageCachedBytes != null) {
      return _blendImageCachedBytes;
    }
    try {
      final bytes = await File(blendPath).readAsBytes();
      _blendImageCachedPath = blendPath;
      _blendImageCachedBytes = bytes;
      return bytes;
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Blend source could not be loaded; omitting blend layer',
        error.runtimeType,
        stackTrace,
      );
      return null;
    }
  }

  Future<EditorPortraitMaskResource?> _preparePortraitMask(
    img.Image source,
    String sourceKey,
  ) async {
    final mask = await _getSegmentMask(source, sourceKey);
    return EditorPortraitMaskResource(
      data: mask,
      width: source.width,
      height: source.height,
    );
  }

  Future<void> _export({bool share = false}) async {
    if (_exporting) return;
    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.applyOrExport);
    }
    if (!mounted) return;

    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportForShare = share;
    });

    try {
      final result = await _mediaExportCoordinator.export(
        share: share,
        buildRequest: _buildExportRequest,
        onProgress: (progress) {
          if (mounted) setState(() => _exportProgress = progress);
        },
        onRetryAtLowerResolution: (dimension) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('메모리 부족으로 인해 해상도를 조절하여 재시도합니다... (${dimension}px)'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
      if (!result.cancelled && mounted) {
        setState(() => _exportProgress = 1.0);
        hapticMedium();
        if (!share) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.get('editor.saved_to_gallery')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      final failure = EditorExportFailure.fromError(error);
      ErrorLogger.log(
        'Editor media export failed (${failure.kind.name})',
        failure.diagnostic,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${S.get('editor.save_failed')}: ${failure.userMessage}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportProgress = 0;
        });
      }
    }
  }

  Future<EditorExportRequest> _buildExportRequest(
      EditorMediaExportAttempt attempt) async {
    final fullDecoded = await _decodedSourceImage();
    final recipe = _currentRenderRecipe();
    final resources = fullDecoded == null
        ? const EditorPreparedResources(
            renderResources: EditorRenderResources(),
            targetGeometry: EditorTargetGeometry(width: 0, height: 0),
          )
        : await _resourcePreparer.prepare(
            EditorResourcePreparationRequest(
              recipe: recipe,
              maskSource: fullDecoded,
              maskSourceKey:
                  'export:${widget.imagePath}:${attempt.maxDimension ?? 'full'}',
              targetGeometry: EditorSpatialRenderer.outputGeometry(
                fullDecoded.width,
                fullDecoded.height,
                recipe,
                maxDimension: attempt.maxDimension,
              ),
              frameIndex: _frameIndex,
              blendImagePath: _blendImagePath,
              preparePortraitMask: _portraitActive,
              prepareTextOverlay: true,
            ),
          );

    return EditorExportRequest(
      imagePath: widget.imagePath!,
      outputPath: attempt.outputPath,
      format: attempt.renderFormat,
      quality: attempt.quality,
      maxDimension: attempt.maxDimension,
      recipe: recipe,
      segmentMask: resources.renderResources.segmentMask,
      segmentMaskWidth: resources.renderResources.segmentMaskWidth,
      segmentMaskHeight: resources.renderResources.segmentMaskHeight,
      blendImageBytes: resources.renderResources.blendImageBytes,
      frameBytes: resources.renderResources.frameBytes,
      textOverlayBytes: resources.renderResources.textOverlayBytes,
    );
  }

  Future<void> _cancelExport() async {
    if (!_exporting) return;
    await _mediaExportCoordinator.cancel();
    if (mounted) {
      setState(() {
        _exporting = false;
        _exportProgress = 0;
      });
    }
  }

  Future<void> _toggleFavorite(String presetId) async {
    // Update in-memory state immediately for instant UI response,
    // then persist — avoids a second async read-back and concurrent-toggle races.
    setState(() {
      if (_favoriteFilterIds.contains(presetId)) {
        _favoriteFilterIds = {..._favoriteFilterIds}..remove(presetId);
      } else {
        _favoriteFilterIds = {..._favoriteFilterIds, presetId};
      }
    });
    await _favRepo.toggle(presetId);
  }

  Future<void> _saveCustomAdjustment(String name) async {
    final adj = CustomAdjustment(
      id: 'cadj_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      params: _params,
      createdAt: DateTime.now(),
    );
    await _adjRepo.save(adj);
    final all = await _adjRepo.getAll();
    if (mounted) setState(() => _customAdjustments = all);
  }

  Future<void> _deleteCustomAdjustment(String id) async {
    await _adjRepo.delete(id);
    final all = await _adjRepo.getAll();
    if (mounted) setState(() => _customAdjustments = all);
  }

  void _applyCustomAdjustment(CustomAdjustment adj) {
    setState(() {
      _params = adj.params;
      _selectedPreset =
          null; // clear filter highlight — params now come from custom adj
      _lutBytes = null;
      _intensity = 1.0;
      _syncCurvesFromParams();
    });
    _renderPreview();
  }

  void _showSaveAdjustmentDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.oceanMid,
        title: const Text(
          '조정 프리셋 저장',
          style: TextStyle(
            fontFamily: 'NotoSerif',
            color: AppColors.textOnDark,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            color: AppColors.textOnDark,
          ),
          decoration: InputDecoration(
            hintText: '프리셋 이름',
            hintStyle: const TextStyle(color: AppColors.textOnDarkTert),
            filled: true,
            fillColor: AppColors.oceanNavy,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textOnDarkSub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.oceanTeal),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                _saveCustomAdjustment(name);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showLoadAdjustmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.oceanMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textOnDarkTert,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '커스텀 조정 프리셋',
                      style: TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ..._customAdjustments.map((adj) => ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    title: Text(
                      adj.name,
                      style: const TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnDark,
                      ),
                    ),
                    subtitle: Text(
                      _formatAdjSummary(adj.params),
                      style: const TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 11,
                        color: AppColors.textOnDarkTert,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await _deleteCustomAdjustment(adj.id);
                            if (!ctx.mounted) return;
                            setSheetState(() {});
                            if (_customAdjustments.isEmpty) {
                              Navigator.pop(ctx);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: AppColors.textOnDarkTert, size: 20),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            _applyCustomAdjustment(adj);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.oceanTeal,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '적용',
                              style: TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.cloudWhite,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAdjSummary(AdjustParams p) {
    final parts = <String>[];
    if (p.exposure.abs() >= 0.05)
      parts.add(
          '노출 ${p.exposure > 0 ? '+' : ''}${p.exposure.toStringAsFixed(1)}');
    if (p.contrast.abs() >= 1)
      parts.add('명암 ${p.contrast > 0 ? '+' : ''}${p.contrast.toInt()}');
    if (p.saturation.abs() >= 1)
      parts.add('채도 ${p.saturation > 0 ? '+' : ''}${p.saturation.toInt()}');
    if (p.temperature.abs() >= 1)
      parts.add('색온도 ${p.temperature > 0 ? '+' : ''}${p.temperature.toInt()}');
    if (parts.isEmpty) return '기본값';
    return parts.take(3).join(' · ');
  }

  List<AdjustSliderItem> get _sliderItems => [
        AdjustSliderItem(
          label: '노출',
          icon: '',
          value: _params.exposure,
          min: -2.0,
          max: 2.0,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(exposure: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '명암',
          icon: '',
          value: _params.contrast,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(contrast: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '채도',
          icon: '',
          value: _params.saturation,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(saturation: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '색온도',
          icon: '',
          value: _params.temperature,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(temperature: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '틴트',
          icon: '',
          value: _params.tint,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(tint: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '하이라이트',
          icon: '',
          value: _params.highlights,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(highlights: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '쉐도우',
          icon: '',
          value: _params.shadows,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(shadows: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '선명도',
          icon: '',
          value: _params.sharpen,
          min: 0,
          max: 100,
          onChanged: (v) {
            setState(() => _params = _params.copyWith(sharpen: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: '비네팅',
          icon: '',
          value: _params.vignette,
          min: 0,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(vignette: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '구조감',
          icon: '',
          value: _params.structure,
          min: -100,
          max: 100,
          onChanged: (v) {
            setState(() => _params = _params.copyWith(structure: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: '명료도',
          icon: '',
          value: _params.clarity,
          min: -100,
          max: 100,
          onChanged: (v) {
            setState(() => _params = _params.copyWith(clarity: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: '톤 그늘',
          icon: '',
          value: _params.tonalShadows,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(tonalShadows: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '톤 미드',
          icon: '',
          value: _params.tonalMidtones,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(tonalMidtones: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: '톤 밝음',
          icon: '',
          value: _params.tonalHighlights,
          min: -100,
          max: 100,
          onChangeStart: (_) {
            _captureComparePreview();
            unawaited(_startLiveSliding());
          },
          onChanged: (v) {
            if (!_isSliding) _startLiveSliding();
            setState(() => _params = _params.copyWith(tonalHighlights: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
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
    if (widget.imagePath == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF111411),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: Icon(backIcon(), color: AppColors.oceanFoam),
                    ),
                    const Expanded(
                      child: Text(
                        '편집',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.oceanFoam,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(child: _buildPreviewArea()),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _handleEditorBack(),
      child: Scaffold(
        backgroundColor: const Color(0xFF111411),
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
      ),
    );
  }

  Future<void> _handleEditorBack() async {
    // First back is always tool cancel. Leaving the editor is explicitly
    // confirmed so accidental navigation never silently drops edits.
    if (_isToolActive) {
      _cancelActiveTool();
      return;
    }
    final discard = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '계속 편집',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      pageBuilder: (dialogContext, _, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 390),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF294737).withValues(alpha: 0.96),
                      const Color(0xFF101B15).withValues(alpha: 0.97),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 40,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFFDAD6).withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                const Color(0xFFFFB4AB).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.undo_rounded,
                          color: Color(0xFFFFB4AB),
                          size: 29,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '편집을 취소할까요?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '지금까지 적용한 편집 내용은\n저장되지 않고 사라집니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.07),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text('계속 편집'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: FilledButton.styleFrom(
                                foregroundColor: const Color(0xFF3B0906),
                                backgroundColor: const Color(0xFFFFB4AB),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                '편집 취소',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (discard == true && mounted) context.pop();
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _EditorOverlayIconButton(
              icon: backIcon(),
              tooltip: '뒤로가기',
              onTap: _handleEditorBack,
            ),
            if (!_isToolActive) ...[
              const SizedBox(width: 8),
              _EditorOverlayIconButton(
                icon: Icons.undo_rounded,
                tooltip: '실행 취소',
                enabled: _history.canUndo,
                onTap: _undo,
              ),
              const SizedBox(width: 6),
              _EditorOverlayIconButton(
                icon: Icons.redo_rounded,
                tooltip: '다시 실행',
                enabled: _history.canRedo,
                onTap: _redo,
              ),
            ],
            const Spacer(),
            const Text(
              '편집',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnDark,
              ),
            ),
            const Spacer(),
            if (_isToolActive) ...[
              _buildCompareHoldIcon(),
              const SizedBox(width: 8),
              _EditorApplyButton(
                onTap: () {
                  hapticLight();
                  _applyActiveTool();
                },
              ),
            ] else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromEmpty() async {
    if (_pickingEmptyImage) return;
    _pickingEmptyImage = true;
    try {
      if (!await MediaPermissionService.ensurePhotoAccess()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(S.get('permission.photos_denied')),
                behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xFile != null && mounted) {
        context.pop();
        context.pushNamed('editor', extra: xFile.path);
      }
    } finally {
      _pickingEmptyImage = false;
    }
  }

  Size get _currentImageSize {
    final base = _previewBaseCache;
    if (base != null) {
      return Size(base.width.toDouble(), base.height.toDouble());
    }
    final decoded = _decodedCache;
    if (decoded != null) {
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    }
    return const Size(1000, 1000);
  }

  Widget _buildPreviewArea() {
    if (widget.imagePath == null) {
      return Center(
        child: Container(
          width: 272,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          decoration: BoxDecoration(
            color: AppColors.cloudWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cloudVeil),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10032111),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🖼️', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              Text(
                S.get('editor.no_image_selected'),
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                S.get('editor.no_image_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.4,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _pickImageFromEmpty,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 19),
                label: Text(S.get('editor.select_photo')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oceanFoam,
                  foregroundColor: AppColors.cloudWhite,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (_showComparePreview)
              _comparePreviewBytes != null
                  ? Image.memory(
                      _comparePreviewBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    )
                  : Image.file(
                      File(widget.imagePath!),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    )
            else if (_isSliding && _liveBaseCacheImage != null)
              GpuImageView(
                sourceImage: _liveBaseCacheImage!,
                params: _params,
                intensity: _intensity,
                lutAtlas: _liveLutAtlas,
                curve1D: _liveCurve1D,
                lumCurve: _liveLumCurve,
                paramsNotifier: _liveParamsNotifier,
                intensityNotifier: _liveIntensityNotifier,
                onShaderError: _endLiveSliding,
              )
            else if (_isToolActive &&
                (_activeToolId == 'rotate' || _activeToolId == 'perspective'))
              Builder(
                builder: (ctx) {
                  final bytes = _spatialBaseBytes ?? _previewBytes;
                  final Widget base = bytes != null
                      ? Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        )
                      : Image.file(
                          File(widget.imagePath!),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        );
                  final rotRad = _rotation * math.pi / 180.0;
                  final skewX = _perspH * math.pi / 180.0;
                  final skewY = _perspV * math.pi / 180.0;
                  final matrix = Matrix4.identity();
                  matrix.setEntry(0, 1, math.tan(skewX));
                  matrix.setEntry(1, 0, math.tan(skewY));
                  return Transform.flip(
                    flipX: _flipH,
                    flipY: _flipV,
                    child: Transform(
                      transform: matrix,
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: rotRad,
                        child: base,
                      ),
                    ),
                  );
                },
              )
            else if (_previewBytes != null)
              Image.memory(
                _previewBytes!,
                fit: BoxFit.contain,
                width: double.infinity,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              )
            else
              Image.file(
                File(widget.imagePath!),
                fit: BoxFit.contain,
                width: double.infinity,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            if (_isToolActive &&
                _activeToolId == 'text' &&
                _overlayText.trim().isNotEmpty)
              _buildLiveTextOverlay(constraints),
            if (_isToolActive && _activeToolId == 'crop')
              CropOverlayWidget(
                imageSize: _currentImageSize,
                cropLeft: _cropLeft,
                cropTop: _cropTop,
                cropRight: _cropRight,
                cropBottom: _cropBottom,
                aspectRatio: _resolvedCropAspectRatio(),
                gridMode: CropGridMode.thirds,
                onCropChanged: (left, top, right, bottom) {
                  setState(() {
                    _cropLeft = left;
                    _cropTop = top;
                    _cropRight = right;
                    _cropBottom = bottom;
                    _cropCenterX = (left + right) / 2;
                    _cropCenterY = (top + bottom) / 2;
                  });
                },
                onDragEnd: () {
                  _debouncedPreview();
                },
              ),
            if (_isToolActive && _activeToolId == 'selective')
              _buildSelectiveTouchOverlay(),
            if (_isToolActive && _activeToolId == 'brush')
              BrushOverlayWidget(
                imageSize: _currentImageSize,
                strokes: _brushStrokes,
                brushSize:
                    (_brushMode == 'dodge' ? _dodgeRadius : _burnRadius) * 200,
                hardness: 0.5,
                transformationController: _transformationController,
                onStroke: (stroke) {
                  setState(() {
                    _dbActive = true;
                    final newStroke = DodgeBurnStroke(
                      x: stroke.x,
                      y: stroke.y,
                      radius: stroke.radius,
                      strength: _brushMode == 'dodge'
                          ? _dodgeStrength
                          : _burnStrength,
                      isDodge: _brushMode == 'dodge',
                    );
                    _brushStrokes.add(newStroke);
                  });
                },
                onStrokeEnd: () {
                  _debouncedPreview();
                },
              ),
            if (_isToolActive && _activeToolId == 'tilt_shift')
              FocusOverlayWidget(
                imageSize: _currentImageSize,
                focusCenter: _tiltFocusCenter,
                bandWidth: _tiltBandWidth,
                onFocusCenterChanged: (v) {
                  setState(() {
                    _tiltActive = true;
                    _tiltFocusCenter = v;
                  });
                  _debouncedPreview();
                },
                onBandWidthChanged: (v) {
                  setState(() {
                    _tiltActive = true;
                    _tiltBandWidth = v;
                  });
                  _debouncedPreview();
                },
                onDragEnd: () {
                  _debouncedPreview();
                },
              ),
            if (_processingPreview) const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  Widget _buildLiveTextOverlay(BoxConstraints constraints) {
    final source = _currentImageSize;
    if (constraints.maxWidth <= 0 ||
        constraints.maxHeight <= 0 ||
        source.width <= 0 ||
        source.height <= 0) {
      return const SizedBox.shrink();
    }

    // Match the BoxFit.contain image rect exactly. Text coordinates are stored
    // in normalized image space, never in the surrounding editor chrome.
    final sourceAspect = source.width / source.height;
    final viewportAspect = constraints.maxWidth / constraints.maxHeight;
    final imageWidth = viewportAspect > sourceAspect
        ? constraints.maxHeight * sourceAspect
        : constraints.maxWidth;
    final imageHeight = imageWidth / sourceAspect;
    final imageLeft = (constraints.maxWidth - imageWidth) / 2;
    final imageTop = (constraints.maxHeight - imageHeight) / 2;
    final visualSize = (_textSize * (imageHeight / 1080.0)).clamp(14.0, 96.0);
    return Positioned(
      left: imageLeft,
      top: imageTop,
      width: imageWidth,
      height: imageHeight,
      child: Align(
        alignment: Alignment(_textX * 2 - 1, _textY * 2 - 1),
        child: Semantics(
          label: '텍스트 위치와 회전 조절',
          hint: '드래그하여 이동하고 두 손가락으로 크기와 회전을 조절합니다',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _textGestureStartSize = _textSize;
              _textGestureStartRotation = _textRotation;
            },
            onScaleUpdate: (details) {
              setState(() {
                _textX = (_textX + details.focalPointDelta.dx / imageWidth)
                    .clamp(0.02, 0.98);
                _textY = (_textY + details.focalPointDelta.dy / imageHeight)
                    .clamp(0.02, 0.98);
                _textSize =
                    (_textGestureStartSize * details.scale).clamp(12.0, 96.0);
                _textRotation = (_textGestureStartRotation +
                        details.rotation * 180 / math.pi)
                    .clamp(-180.0, 180.0);
              });
            },
            onScaleEnd: (_) {
              _scheduleDraftSave();
            },
            child: Transform.rotate(
              angle: _textRotation * math.pi / 180,
              child: Container(
                key: const ValueKey('live-text-overlay'),
                constraints: BoxConstraints(maxWidth: imageWidth * 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.86),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _overlayText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _textFontFamily,
                    fontSize: visualSize,
                    height: 1.05,
                    color: _textColor,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectiveTouchOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        void updatePoint(Offset localPosition) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) return;
          setState(() {
            _selX = (localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            _selY = (localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
            _selActive = true;
          });
          _debouncedPreview();
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => updatePoint(details.localPosition),
          onPanUpdate: (details) => updatePoint(details.localPosition),
          child: Stack(
            children: [
              if (_selActive)
                Positioned(
                  left: _selX * constraints.maxWidth - 18,
                  top: _selY * constraints.maxHeight - 18,
                  child: IgnorePointer(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                      child: const Icon(Icons.adjust_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    return SafeArea(
      top: false,
      child: _buildBottomPanelContent(),
    );
  }

  static const List<_ToolItem> _tools = [
    _ToolItem(id: 'tune', label: '기본 보정', icon: Icons.tune_rounded),
    _ToolItem(id: 'details', label: '세부 정보', icon: Icons.details_rounded),
    _ToolItem(id: 'curves', label: '커브', icon: Icons.waves_rounded),
    _ToolItem(
        id: 'white_balance', label: '화이트 밸런스', icon: Icons.wb_sunny_rounded),
    _ToolItem(id: 'crop', label: '크롭', icon: Icons.crop_rounded),
    _ToolItem(id: 'rotate', label: '회전', icon: Icons.rotate_right_rounded),
    _ToolItem(id: 'perspective', label: '원근', icon: Icons.transform_rounded),
    _ToolItem(id: 'expand', label: '확장', icon: Icons.aspect_ratio_rounded),
    _ToolItem(id: 'hsl', label: '색상 HSL', icon: Icons.color_lens_rounded),
    _ToolItem(
        id: 'selective',
        label: '부분 보정',
        icon: Icons.filter_center_focus_rounded),
    _ToolItem(id: 'brush', label: '브러시', icon: Icons.brush_rounded),
    _ToolItem(
        id: 'tilt_shift', label: '틸트 시프트', icon: Icons.blur_linear_rounded),
    _ToolItem(
        id: 'lens_blur', label: '원형 초점 흐림', icon: Icons.blur_circular_rounded),
    _ToolItem(id: 'vignette', label: '비네팅', icon: Icons.vignette_rounded),
    _ToolItem(id: 'grain', label: '그레인', icon: Icons.grain_rounded),
    _ToolItem(id: 'split_toning', label: '스플릿 톤', icon: Icons.looks_rounded),
    _ToolItem(id: 'noise', label: '노이즈', icon: Icons.texture_rounded),
    _ToolItem(id: 'glow', label: '글로우', icon: Icons.wb_twilight_rounded),
    _ToolItem(id: 'portrait', label: '인물 영역', icon: Icons.face_rounded),
    _ToolItem(
        id: 'double_exposure', label: '이중 노출', icon: Icons.layers_rounded),
    _ToolItem(id: 'frame', label: '프레임', icon: Icons.crop_original_rounded),
    _ToolItem(id: 'text', label: '텍스트', icon: Icons.text_fields_rounded),
    _ToolItem(id: 'light_leak', label: '광학 유출', icon: Icons.flare_rounded),
    _ToolItem(
        id: 'halation', label: '헐레이션', icon: Icons.wb_incandescent_rounded),
    _ToolItem(id: 'drama', label: '드라마', icon: Icons.theater_comedy_rounded),
    _ToolItem(id: 'hdr_scape', label: 'HDR 스케이프', icon: Icons.hdr_on_rounded),
  ];

  Future<void> _pickBlendImage() async {
    if (_pickingBlendImage) return;
    _pickingBlendImage = true;
    try {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xFile != null && mounted) {
        setState(() => _blendImagePath = xFile.path);
        _renderPreview();
      }
    } finally {
      _pickingBlendImage = false;
    }
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {ValueChanged<double>? onChangeEnd}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFFFFC400),
                inactiveTrackColor: AppColors.textSecondary.withOpacity(0.2),
                thumbColor: const Color(0xFFFFC400),
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
      String label, IconData icon, bool active, VoidCallback onTap,
      {bool rotate = false}) {
    return ActionChip(
      avatar: Transform.rotate(
        angle: rotate ? math.pi / 2 : 0,
        child: Icon(icon,
            size: 16, color: active ? Colors.black : AppColors.textSecondary),
      ),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: active ? const Color(0xFFFFC400) : Colors.white,
      labelStyle: TextStyle(
        color: active ? Colors.black : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  Widget _buildCropPresetRow() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: CropRatioPreset.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = CropRatioPreset.values[i];
          final sel = _cropRatio == preset;
          return GestureDetector(
            onTap: () {
              hapticLight();
              _setCropRatioPreset(preset);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFFFC400) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel
                      ? const Color(0xFFFFC400)
                      : AppColors.textSecondary.withOpacity(0.15),
                ),
              ),
              child: Text(
                preset.label,
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.black : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _setCropRatioPreset(CropRatioPreset preset) {
    final ratio = preset == CropRatioPreset.original
        ? _resolvedCropAspectRatio(imageSize: _decodedCache)
        : preset.ratio;
    setState(() {
      _cropRatio = preset;
      _cropCenterX = 0.5;
      _cropCenterY = 0.5;

      // A ratio change is a fresh framing request, never a resize inside the
      // previous crop. Reusing the old rect was what made repeated switches
      // steadily shrink the crop window.
      if (ratio == null) {
        _cropLeft = 0;
        _cropTop = 0;
        _cropRight = 1;
        _cropBottom = 1;
        return;
      }

      final imageSize = _currentImageSize;
      final imageRatio = imageSize.width / imageSize.height;
      final width = imageRatio > ratio ? ratio / imageRatio : 1.0;
      final height = imageRatio > ratio ? 1.0 : imageRatio / ratio;
      _cropLeft = (1 - width) / 2;
      _cropRight = _cropLeft + width;
      _cropTop = (1 - height) / 2;
      _cropBottom = _cropTop + height;
    });
  }

  Widget _buildActiveToolControls() {
    switch (_activeToolId) {
      case 'tune':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _BnwToggle(
                      enabled: _params.bnwEnabled,
                      onToggle: (v) {
                        setState(
                            () => _params = _params.copyWith(bnwEnabled: v));
                        _renderPreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_rounded,
                        color: Colors.black87),
                    tooltip: '조정 저장',
                    onPressed: _showSaveAdjustmentDialog,
                  ),
                  if (_customAdjustments.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.bookmarks_rounded,
                          color: Colors.black87),
                      tooltip: '조정 불러오기',
                      onPressed: _showLoadAdjustmentSheet,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            AdjustParamsPanel(
              items: _sliderItems,
              selectedIndex: _adjustIndex,
              onSelectIndex: (i) => setState(() => _adjustIndex = i),
            ),
          ],
        );
      case 'details':
        return DetailsPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'curves':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CurveEditorPanel(
            curves: _curves,
            onChanged: (channel, data) {
              setState(() {
                _curves[channel] = data;
                _params = _params.copyWith(
                  luminanceCurve: _curves[CurveChannel.luminance],
                  rgbCurve: _curves[CurveChannel.rgb],
                  redCurve: _curves[CurveChannel.red],
                  greenCurve: _curves[CurveChannel.green],
                  blueCurve: _curves[CurveChannel.blue],
                );
              });
              _debouncedPreview();
            },
          ),
        );
      case 'white_balance':
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WbPresetRow(
                onSelect: (preset) {
                  setState(() => _params = preset.applyTo(_params));
                  _renderPreview();
                },
              ),
            ),
            const SizedBox(height: 8),
            _sliderRow('색온도', _params.temperature, -100, 100, (v) {
              setState(() => _params = _params.copyWith(temperature: v));
              _debouncedPreview();
            }),
            _sliderRow('틴트', _params.tint, -100, 100, (v) {
              setState(() => _params = _params.copyWith(tint: v));
              _debouncedPreview();
            }),
          ],
        );
      case 'crop':
        return _buildCropPresetRow();
      case 'filter':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterStrip(
              presets: _allPresets,
              selectedId: _selectedPreset?.id,
              favoriteIds: _favoriteFilterIds,
              onSelect: _selectPreset,
              onFavoriteToggle: _toggleFavorite,
            ),
            if (_selectedPreset != null)
              IntensitySlider(
                value: _intensity,
                onChanged: (v) {
                  setState(() => _intensity = v);
                  _debouncedPreview();
                },
                onChangeEnd: (_) => _renderPreview(),
              ),
          ],
        );
      case 'rotate':
        return Column(
          children: [
            _sliderRow('회전', _rotation, -45, 45, (v) {
              setState(() => _rotation = v);
            }, onChangeEnd: (_) => _renderPreview()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionChip('좌우 반전', Icons.flip_rounded, _flipH, () {
                    setState(() => _flipH = !_flipH);
                  }),
                  _actionChip('상하 반전', Icons.flip_rounded, _flipV, () {
                    setState(() => _flipV = !_flipV);
                  }, rotate: true),
                ],
              ),
            ),
          ],
        );
      case 'perspective':
        return Column(
          children: [
            _sliderRow('수평 기울기', _perspH, -20, 20, (v) {
              setState(() => _perspH = v);
              _debouncedPreview();
            }),
            _sliderRow('수직 기울기', _perspV, -20, 20, (v) {
              setState(() => _perspV = v);
              _debouncedPreview();
            }),
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('기울기 초기화'),
              onPressed: () {
                setState(() {
                  _perspH = 0.0;
                  _perspV = 0.0;
                });
                _renderPreview();
              },
            ),
          ],
        );
      case 'expand':
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['black', 'white'].map((m) {
                final sel = _expandMode == m;
                final label = m == 'black' ? '블랙' : '화이트';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: sel,
                    onSelected: (_) {
                      setState(() => _expandMode = m);
                      _renderPreview();
                    },
                    selectedColor: const Color(0xFFFFC400),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: sel ? Colors.black : AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            _sliderRow('상단 확장', _expandTop, 0.0, 0.5, (v) {
              setState(() => _expandTop = v);
              _debouncedPreview();
            }),
            _sliderRow('하단 확장', _expandBottom, 0.0, 0.5, (v) {
              setState(() => _expandBottom = v);
              _debouncedPreview();
            }),
            _sliderRow('좌측 확장', _expandLeft, 0.0, 0.5, (v) {
              setState(() => _expandLeft = v);
              _debouncedPreview();
            }),
            _sliderRow('우측 확장', _expandRight, 0.0, 0.5, (v) {
              setState(() => _expandRight = v);
              _debouncedPreview();
            }),
          ],
        );
      case 'hsl':
        return HslPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'selective':
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _selActive
                    ? '표시된 지점을 드래그해 위치를 바꾸고, 아래 값으로 해당 영역만 보정합니다.'
                    : '사진을 터치하거나 드래그해 먼저 보정할 위치를 지정하세요.',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (_selActive) ...[
              _sliderRow('밝기', _selBright, -100, 100, (v) {
                setState(() => _selBright = v);
                _debouncedPreview();
              }),
              _sliderRow('대비', _selContrast, -100, 100, (v) {
                setState(() => _selContrast = v);
                _debouncedPreview();
              }),
              _sliderRow('채도', _selSat, -100, 100, (v) {
                setState(() => _selSat = v);
                _debouncedPreview();
              }),
              _sliderRow('반경', _selRadius, 0.1, 0.8, (v) {
                setState(() => _selRadius = v);
                _debouncedPreview();
              }),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('지점을 추가하면 부분 보정 조절이 활성화됩니다.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
          ],
        );
      case 'brush':
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('닷지 (Dodge / 밝게)'),
                  selected: _brushMode == 'dodge',
                  onSelected: (selected) {
                    if (selected) setState(() => _brushMode = 'dodge');
                  },
                  selectedColor: const Color(0xFFFFC400),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _brushMode == 'dodge'
                        ? Colors.black
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('번 (Burn / 어둡게)'),
                  selected: _brushMode == 'burn',
                  onSelected: (selected) {
                    if (selected) setState(() => _brushMode = 'burn');
                  },
                  selectedColor: const Color(0xFFFFC400),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _brushMode == 'burn'
                        ? Colors.black
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _sliderRow('반경', _brushMode == 'dodge' ? _dodgeRadius : _burnRadius,
                0.05, 0.5, (v) {
              setState(() {
                if (_brushMode == 'dodge') {
                  _dodgeRadius = v;
                } else {
                  _burnRadius = v;
                }
              });
            }),
            _sliderRow(
                '강도',
                _brushMode == 'dodge' ? _dodgeStrength : _burnStrength,
                0.0,
                1.0, (v) {
              setState(() {
                if (_brushMode == 'dodge') {
                  _dodgeStrength = v;
                } else {
                  _burnStrength = v;
                }
              });
            }),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('모든 브러시 스트로크 지우기'),
              onPressed: () {
                setState(() {
                  _brushStrokes.clear();
                });
                _renderPreview();
              },
            ),
          ],
        );
      case 'tilt_shift':
        return Column(
          children: [
            _sliderRow('초점 위치', _tiltFocusCenter, 0.0, 1.0, (v) {
              setState(() {
                _tiltActive = true;
                _tiltFocusCenter = v;
              });
              _debouncedPreview();
            }),
            _sliderRow('범위 넓이', _tiltBandWidth, 0.1, 0.6, (v) {
              setState(() {
                _tiltActive = true;
                _tiltBandWidth = v;
              });
              _debouncedPreview();
            }),
            _sliderRow('최대 흐림', _tiltMaxBlur, 0.0, 20.0, (v) {
              setState(() {
                _tiltActive = v > 0;
                _tiltMaxBlur = v;
              });
              _debouncedPreview();
            }),
          ],
        );
      case 'lens_blur':
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '사진 중심에서의 거리를 기준으로 초점 영역을 만듭니다.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            _sliderRow('초점 거리', _lensFocusDepth, 0.0, 1.0, (v) {
              setState(() {
                _lensActive = _lensMaxRadius > 0;
                _lensFocusDepth = v;
              });
              _debouncedPreview();
            }),
            _sliderRow('흐림 반경', _lensMaxRadius, 0.0, 20.0, (v) {
              setState(() {
                _lensActive = v > 0;
                _lensMaxRadius = v;
              });
              _debouncedPreview();
            }),
          ],
        );
      case 'vignette':
        return VignettePanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'grain':
        return GrainPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'split_toning':
        return SplitToningPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'noise':
        return NoisePanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'glow':
        return GlowPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'portrait':
        return _PortraitPanel(
          smooth: _portraitSmooth,
          spotlight: _portraitSpotlight,
          skinTone: _skinTone,
          skinStrength: _skinToneStrength,
          onSmooth: (v) {
            setState(() => _portraitSmooth = v);
            _debouncedPreview();
          },
          onSpotlight: (v) {
            setState(() => _portraitSpotlight = v);
            _debouncedPreview();
          },
          onSkinTone: (t) {
            setState(() => _skinTone = t);
            _renderPreview();
          },
          onSkinStrength: (v) {
            setState(() => _skinToneStrength = v);
            _debouncedPreview();
          },
        );
      case 'double_exposure':
        return _CreativePanel(
          forceTab: _CreativeSubTab.doubleExposure,
          blendImagePath: _blendImagePath,
          blendMode: _blendMode,
          blendOpacity: _blendOpacity,
          frameIndex: _frameIndex,
          overlayText: _overlayText,
          textSize: _textSize,
          textColor: _textColor,
          textFontFamily: _textFontFamily,
          onPickBlend: _pickBlendImage,
          onBlendMode: (m) {
            setState(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            setState(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            setState(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            setState(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            setState(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            setState(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            setState(() => _textFontFamily = font);
            _renderPreview();
          },
        );
      case 'frame':
        return _CreativePanel(
          forceTab: _CreativeSubTab.frame,
          blendImagePath: _blendImagePath,
          blendMode: _blendMode,
          blendOpacity: _blendOpacity,
          frameIndex: _frameIndex,
          overlayText: _overlayText,
          textSize: _textSize,
          textColor: _textColor,
          textFontFamily: _textFontFamily,
          onPickBlend: _pickBlendImage,
          onBlendMode: (m) {
            setState(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            setState(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            setState(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            setState(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            setState(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            setState(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            setState(() => _textFontFamily = font);
            _renderPreview();
          },
        );
      case 'text':
        return _CreativePanel(
          forceTab: _CreativeSubTab.text,
          blendImagePath: _blendImagePath,
          blendMode: _blendMode,
          blendOpacity: _blendOpacity,
          frameIndex: _frameIndex,
          overlayText: _overlayText,
          textSize: _textSize,
          textColor: _textColor,
          textFontFamily: _textFontFamily,
          onPickBlend: _pickBlendImage,
          onBlendMode: (m) {
            setState(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            setState(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            setState(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            setState(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            setState(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            setState(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            setState(() => _textFontFamily = font);
            _renderPreview();
          },
        );
      case 'light_leak':
        return LightLeakPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'halation':
        return HalationPanel(
          params: _params,
          onChanged: (p) {
            setState(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'drama':
        return _EffectsPanel(
          imagePath: widget.imagePath,
          selected: _effect,
          strength: _effectStrength,
          forceGroup: '드라마',
          onEffect: (e) {
            setState(() => _effect = e);
            _renderPreview();
          },
          onStrength: (v) {
            setState(() => _effectStrength = v);
            _debouncedPreview();
          },
        );
      case 'hdr_scape':
        return _EffectsPanel(
          imagePath: widget.imagePath,
          selected: _effect,
          strength: _effectStrength,
          forceGroup: 'HDR',
          onEffect: (e) {
            setState(() => _effect = e);
            _renderPreview();
          },
          onStrength: (v) {
            setState(() => _effectStrength = v);
            _debouncedPreview();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildActiveToolBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withOpacity(0.05),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Text(
              _activeToolName ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            tooltip: '초기화',
            icon: const Icon(Icons.refresh_rounded, color: Colors.black87),
            onPressed: () {
              hapticLight();
              _resetActiveTool();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompareHoldIcon() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        hapticLight();
        _setComparePreviewVisible(true);
      },
      onTapUp: (_) => _setComparePreviewVisible(false),
      onTapCancel: () => _setComparePreviewVisible(false),
      child: Semantics(
        button: true,
        label: '적용 전 보기',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _showComparePreview
                ? AppColors.oceanFoam
                : Colors.black.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _showComparePreview
                  ? Colors.white.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.76),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, color: Colors.white, size: 19),
              SizedBox(width: 6),
              Text(
                '적용 전',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteToolsDock() {
    final favTools =
        _tools.where((t) => _favoriteToolIds.contains(t.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '자주 찾는 도구',
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              GestureDetector(
                onTap: _showCustomizeFavoritesSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0EE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_outlined,
                          size: 12, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(
                        '맞춤 설정',
                        style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 85,
          child: favTools.isEmpty
              ? const Center(
                  child: Text(
                    '자주 찾는 도구가 없습니다. 맞춤 설정을 눌러보세요.',
                    style: TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 11,
                        color: Colors.black54),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: favTools.length,
                  itemBuilder: (context, index) {
                    final tool = favTools[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () {
                          hapticLight();
                          _activateTool(tool.id, tool.label);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.04),
                                ),
                              ),
                              child: Icon(
                                tool.icon,
                                size: 24,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              tool.label,
                              style: const TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCustomizeFavoritesSheet() {
    hapticLight();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF7F7F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '자주 찾는 도구 맞춤 설정',
                            style: TextStyle(
                              fontFamily: 'NotoSerif',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _saveFavoriteTools();
                              Navigator.pop(context);
                              setState(() {}); // Refresh parent state
                            },
                            child: const Text(
                              '완료',
                              style: TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFC400),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Text(
                        '자주 사용하는 도구를 선택하여 퀵 액세스 바에 고정하세요. 갯수 제한은 없습니다.',
                        style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: _tools.length,
                        itemBuilder: (context, index) {
                          final tool = _tools[index];
                          final isFav = _favoriteToolIds.contains(tool.id);
                          return GestureDetector(
                            onTap: () {
                              hapticLight();
                              setSheetState(() {
                                if (isFav) {
                                  _favoriteToolIds.remove(tool.id);
                                } else {
                                  _favoriteToolIds.add(tool.id);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: isFav
                                    ? Colors.white
                                    : const Color(0xFFECECE9),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isFav
                                      ? const Color(0xFFFFC400)
                                      : Colors.transparent,
                                  width: 2.0,
                                ),
                                boxShadow: isFav
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFFC400)
                                              .withOpacity(0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          tool.icon,
                                          size: 24,
                                          color: isFav
                                              ? Colors.black87
                                              : Colors.black54,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          tool.label,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'NotoSerif',
                                            fontSize: 11,
                                            fontWeight: isFav
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isFav
                                                ? Colors.black87
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isFav)
                                    const Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: Color(0xFFFFC400),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildToolsGridView() {
    return Container(
      height: 255,
      padding: const EdgeInsets.only(left: 12, right: 12, top: 2, bottom: 8),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: _tools.length,
        itemBuilder: (context, index) {
          final tool = _tools[index];
          return GestureDetector(
            onTap: () {
              hapticLight();
              _activateTool(tool.id, tool.label);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Colors.black.withOpacity(0.04),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool.icon,
                    size: 22,
                    color: Colors.black87,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tool.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withOpacity(0.05),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavTabItem(_MainNavTab.style, '스타일', Icons.style_outlined),
          _buildNavTabItem(_MainNavTab.tools, '도구', Icons.grid_view_rounded),
          _buildNavTabItem(_MainNavTab.export, '내보내기', Icons.ios_share_rounded),
        ],
      ),
    );
  }

  Widget _buildNavTabItem(_MainNavTab tab, String label, IconData icon) {
    final active = _mainNavTab == tab;
    return GestureDetector(
      onTap: () {
        hapticLight();
        setState(() {
          if (_mainNavTab == tab) {
            _mainNavTab = null;
          } else {
            _mainNavTab = tab;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFC400) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.black : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.black : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportMenu() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _buildCompareHoldTile(),
          const SizedBox(height: 12),
          _buildExportTile(
            title: '갤러리에 저장',
            subtitle: '현재 편집된 고해상도 이미지를 사진 라이브러리에 저장합니다.',
            icon: Icons.save_alt_rounded,
            onTap: () {
              hapticLight();
              _export();
            },
          ),
          const SizedBox(height: 12),
          _buildExportTile(
            title: '다른 앱으로 공유',
            subtitle: '편집된 이미지를 메신저나 SNS 등으로 바로 공유합니다.',
            icon: Icons.share_rounded,
            onTap: () {
              hapticLight();
              _export(share: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompareHoldTile() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        hapticLight();
        _setComparePreviewVisible(true);
      },
      onTapUp: (_) => _setComparePreviewVisible(false),
      onTapCancel: () => _setComparePreviewVisible(false),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: const Row(
          children: [
            Icon(Icons.visibility_outlined, color: Colors.white, size: 20),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '적용 전 보기',
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '누르고 있는 동안 현재 필터/조정 적용 전 화면을 보여줍니다.',
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withOpacity(0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC400).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.black87,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanelContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          if (_isToolActive) ...[
            _buildActiveToolControls(),
            const SizedBox(height: 12),
            _buildActiveToolBottomBar(),
          ] else ...[
            if (_mainNavTab == null) ...[
              _buildFavoriteToolsDock(),
            ] else if (_mainNavTab == _MainNavTab.style) ...[
              FilterStrip(
                presets: _allPresets,
                selectedId: _selectedPreset?.id,
                favoriteIds: _favoriteFilterIds,
                onSelect: _selectPresetForPreview,
                onFavoriteToggle: _toggleFavorite,
              ),
              const SizedBox(height: 2),
              if (_selectedPreset != null)
                IntensitySlider(
                  value: _intensity,
                  onChangeStart: (_) {
                    _captureComparePreview();
                    unawaited(_startLiveSliding());
                  },
                  onChanged: (v) {
                    setState(() => _intensity = v);
                    _liveIntensityNotifier.value = v;
                    if (!_isSliding) _debouncedPreview();
                  },
                  onChangeEnd: (_) =>
                      _isSliding ? _endLiveSliding() : _renderPreview(),
                ),
              if (_showFavoriteTip)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBE6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE58F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          color: Color(0xFFFAAD14), size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '필터를 길게 누르면 즐겨찾기에 추가/해제할 수 있습니다.',
                          style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _showFavoriteTip = false);
                          _saveFavoriteTipDismissed();
                        },
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          S.get('editor.got_it'),
                          style: const TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 11,
                            color: AppColors.oceanFoam,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (_mainNavTab == _MainNavTab.tools) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '모든 도구',
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              _buildToolsGridView(),
            ] else if (_mainNavTab == _MainNavTab.export) ...[
              _buildExportMenu(),
            ],
            const SizedBox(height: 8),
            _buildMainBottomNavigation(),
          ],
        ],
      ),
    );
  }

  Widget _buildExportOverlay() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          color: AppColors.overlay40,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(
                    0xE6092717), // Premium dark theme matching oceanFoam
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _exportForShare
                          ? Icons.ios_share_rounded
                          : Icons.save_alt_rounded,
                      color: const Color(0xFFFFC400),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _exportForShare ? '공유 준비 중...' : S.get('editor.exporting'),
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _exportForShare
                        ? '다른 앱으로 전송하기 위해 고해상도 이미지를 렌더링하고 있습니다.\n완료 후 공유할 앱 선택 창이 열립니다.'
                        : '편집 결과를 고해상도로 갤러리에 저장하는 중입니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: _exportProgress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFC400)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${(_exportProgress * 100).round()}%',
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _cancelExport,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Text(
                        S.get('editor.cancel_export'),
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorOverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _EditorOverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.black.withValues(alpha: 0.36)
                    : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.76)
                      : Colors.white.withValues(alpha: 0.24),
                  width: 1.5,
                ),
                boxShadow: enabled
                    ? const [
                        BoxShadow(
                          color: Color(0x52000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorApplyButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EditorApplyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '적용',
      child: Semantics(
        button: true,
        label: '적용',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.oceanFoam,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59032111),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 20, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    '적용',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 0, right: 8),
        children: WhiteBalancePreset.values.map((preset) {
          return GestureDetector(
            onTap: () {
              hapticLight();
              onSelect(preset);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.oceanFoam.withOpacity(0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                preset.label,
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 12,
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
                alignment:
                    enabled ? Alignment.centerRight : Alignment.centerLeft,
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

class _SubTabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
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
            Icon(icon,
                size: 14,
                color:
                    selected ? AppColors.cloudWhite : AppColors.textOnDarkTert),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.cloudWhite : AppColors.textOnDarkTert,
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
  final String? imagePath;
  final ArtisticEffect selected;
  final double strength;
  final String? forceGroup;
  final ValueChanged<ArtisticEffect> onEffect;
  final ValueChanged<double> onStrength;

  const _EffectsPanel({
    required this.imagePath,
    required this.selected,
    required this.strength,
    this.forceGroup,
    required this.onEffect,
    required this.onStrength,
  });

  static const _groups = [
    _EffectGroup('없음', [ArtisticEffect.none]),
    _EffectGroup('필름', [
      ArtisticEffect.grain,
      ArtisticEffect.grainyFilm,
      ArtisticEffect.vintage,
      ArtisticEffect.retrolux
    ]),
    _EffectGroup('드라마', [
      ArtisticEffect.drama1,
      ArtisticEffect.drama2,
      ArtisticEffect.dramaBright1,
      ArtisticEffect.dramaBright2,
      ArtisticEffect.dramaDark1,
      ArtisticEffect.dramaDark2
    ]),
    _EffectGroup('HDR', [
      ArtisticEffect.hdrFine,
      ArtisticEffect.hdrNature,
      ArtisticEffect.hdrPeople,
      ArtisticEffect.hdrStrong
    ]),
    _EffectGroup('기타', [ArtisticEffect.glamourGlow, ArtisticEffect.grunge]),
  ];

  @override
  Widget build(BuildContext context) {
    final groups = forceGroup != null
        ? _groups.where((g) => g.label == forceGroup).toList()
        : _groups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이펙트 선택 스크롤 행
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.fold(0, (s, g) => s + g.effects.length) +
                groups.length -
                1, // separators
            separatorBuilder: (_, i) => const SizedBox(width: 12),
            itemBuilder: (context, flatIdx) {
              // flatten groups with separators
              int pos = 0;
              for (int g = 0; g < groups.length; g++) {
                if (g > 0) {
                  if (pos == flatIdx) {
                    return _GroupDivider(label: groups[g].label);
                  }
                  pos++;
                }
                for (final e in groups[g].effects) {
                  if (pos == flatIdx) {
                    return _EffectChip(
                      imagePath: imagePath,
                      effect: e,
                      selected: e == selected,
                      onTap: () {
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.oceanFoam,
                      inactiveTrackColor: AppColors.oceanNavy,
                      thumbColor: AppColors.cloudWhite,
                      overlayColor: AppColors.oceanFoam.withOpacity(0.2),
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: strength,
                      min: 0.0,
                      max: 1.0,
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
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
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
        Container(width: 1.5, height: 32, color: Colors.black26),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _EffectChip extends StatefulWidget {
  final String? imagePath;
  final ArtisticEffect effect;
  final bool selected;
  final VoidCallback onTap;

  const _EffectChip(
      {required this.imagePath,
      required this.effect,
      required this.selected,
      required this.onTap});

  @override
  State<_EffectChip> createState() => _EffectChipState();
}

class _EffectChipState extends State<_EffectChip> {
  static final Map<String, Future<Uint8List?>> _thumbnailJobs = {};
  static final Map<String, Future<img.Image?>> _sourceProxyJobs = {};

  static Future<img.Image?> _sourceProxy(String imagePath) =>
      _sourceProxyJobs.putIfAbsent(
        imagePath,
        () async {
          try {
            final bytes = await File(imagePath).readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded == null) return null;
            return img.copyResize(
              decoded,
              width: 112,
              height: 72,
              interpolation: img.Interpolation.linear,
            );
          } catch (error, stackTrace) {
            ErrorLogger.log(
              'Effect thumbnail source could not be decoded',
              error.runtimeType,
              stackTrace,
            );
            return null;
          }
        },
      );

  Future<Uint8List?> _thumbnail() {
    final imagePath = widget.imagePath;
    if (imagePath == null) return Future.value(null);
    final key = '$imagePath|${widget.effect.name}';
    return _thumbnailJobs.putIfAbsent(
      key,
      () async {
        try {
          final proxy = await _sourceProxy(imagePath);
          if (proxy == null) return null;
          final rendered = widget.effect == ArtisticEffect.none
              ? proxy
              : await applyArtisticEffect(proxy, widget.effect);
          return Uint8List.fromList(img.encodeJpg(rendered, quality: 82));
        } catch (error, stackTrace) {
          ErrorLogger.log(
            'Effect thumbnail rendering failed',
            error.runtimeType,
            stackTrace,
          );
          return null;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 84,
        decoration: BoxDecoration(
          color:
              widget.selected ? AppColors.oceanTeal : const Color(0xFF0B1C14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected
                ? AppColors.oceanFoam
                : Colors.white.withValues(alpha: 0.26),
            width: widget.selected ? 2 : 1.25,
          ),
          boxShadow: widget.selected
              ? const [
                  BoxShadow(
                    color: Color(0x3D75E5B1),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 74,
                  height: 39,
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbnail(),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes != null) {
                        return Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                        );
                      }
                      return Container(
                        color: const Color(0xFF102B20),
                        alignment: Alignment.center,
                        child:
                            snapshot.connectionState == ConnectionState.waiting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: AppColors.oceanFoam,
                                    ),
                                  )
                                : Icon(
                                    _iconFor(widget.effect),
                                    size: 20,
                                    color: Colors.white70,
                                  ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Text(
              widget.effect.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 10,
                height: 1.1,
                fontWeight: widget.selected ? FontWeight.bold : FontWeight.w600,
                color: widget.selected ? Colors.white : Colors.white70,
              ),
            ),
            if (widget.selected)
              const Icon(Icons.check_circle_rounded,
                  size: 12, color: AppColors.oceanFoam),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ArtisticEffect e) {
    switch (e) {
      case ArtisticEffect.none:
        return Icons.block_rounded;
      case ArtisticEffect.grain:
      case ArtisticEffect.grainyFilm:
        return Icons.grain_rounded;
      case ArtisticEffect.vintage:
      case ArtisticEffect.retrolux:
        return Icons.camera_rounded;
      case ArtisticEffect.drama1:
      case ArtisticEffect.drama2:
      case ArtisticEffect.dramaBright1:
      case ArtisticEffect.dramaBright2:
      case ArtisticEffect.dramaDark1:
      case ArtisticEffect.dramaDark2:
        return Icons.contrast_rounded;
      case ArtisticEffect.hdrFine:
      case ArtisticEffect.hdrNature:
      case ArtisticEffect.hdrPeople:
      case ArtisticEffect.hdrStrong:
        return Icons.hdr_on_rounded;
      case ArtisticEffect.glamourGlow:
        return Icons.auto_awesome_rounded;
      case ArtisticEffect.grunge:
        return Icons.texture_rounded;
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
    required this.smooth,
    required this.spotlight,
    required this.skinTone,
    required this.skinStrength,
    required this.onSmooth,
    required this.onSpotlight,
    required this.onSkinTone,
    required this.onSkinStrength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _portraitModelStatus(),
        _row('인물 영역 부드럽게', smooth, 0, 100, onSmooth),
        _row('인물 영역 밝히기', spotlight, 0, 100, onSpotlight),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('인물 영역 색조',
              style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 12,
                  color: AppColors.textOnDarkSub)),
        ),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: SkinTone.values.map((t) {
              final sel = t == skinTone;
              return GestureDetector(
                onTap: () {
                  hapticLight();
                  onSkinTone(t);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(t.label,
                      style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? AppColors.cloudWhite
                              : AppColors.textOnDarkSub)),
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

  Widget _portraitModelStatus() {
    return AnimatedBuilder(
      animation: AiManager.instance,
      builder: (context, _) {
        final state = AiManager.instance.stateOf(kModelSelfie.key);
        final isReady = state.status == ModelStatus.ready;
        final isLoading = state.status == ModelStatus.downloading;
        final message = isReady
            ? '기기 내 인물 분할을 사용합니다. 얼굴 피부만 따로 구분하는 보정은 아닙니다.'
            : isLoading
                ? '인물 영역 모델을 준비하고 있습니다. ${(state.progress * 100).round()}%'
                : '인물 영역 모델이 준비되지 않아 현재 보정은 적용되지 않습니다.';
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isReady ? const Color(0xFFEAF2ED) : const Color(0xFFFFF3D6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (isLoading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (!isReady && !isLoading)
                TextButton(
                  onPressed: () =>
                      unawaited(AiManager.instance.preload(kModelSelfie)),
                  child: const Text('재시도'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, double value, double min, double max,
      ValueChanged<double> onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child:
                  Slider(value: value, min: min, max: max, onChanged: onChange),
            ),
          ),
          SizedBox(
              width: 32,
              child: Text(value.round().toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      color: AppColors.textOnDarkTert))),
        ],
      ),
    );
  }
}

// ── Creative Panel ────────────────────────────────────────

// frame asset list (small thumbnails)
const _frameAssets = [
  'assets/frames/hp_frame_00_overlay.png',
  'assets/frames/hp_frame_01_overlay.png',
  'assets/frames/hp_frame_02_overlay.png',
  'assets/frames/hp_frame_03_overlay.png',
  'assets/frames/hp_frame_04_overlay.png',
  'assets/frames/hp_frame_05_overlay.png',
  'assets/frames/hp_frame_06_overlay.png',
  'assets/frames/hp_frame_07_overlay.png',
  'assets/frames/hp_frame_08_overlay.png',
  'assets/frames/hp_frame_09_overlay.png',
  'assets/frames/hp_frame_10_overlay.png',
  'assets/frames/hp_frame_11_overlay.png',
  'assets/frames/hp_frame_12_overlay.png',
];

enum _CreativeSubTab { doubleExposure, frame, text }

class _CreativePanel extends StatefulWidget {
  final _CreativeSubTab? forceTab;
  final String? blendImagePath;
  final bm.BlendMode blendMode;
  final double blendOpacity;
  final int frameIndex;
  final String overlayText;
  final double textSize;
  final Color textColor;
  final String textFontFamily;
  final VoidCallback onPickBlend;
  final ValueChanged<bm.BlendMode> onBlendMode;
  final ValueChanged<double> onBlendOpacity;
  final ValueChanged<int> onFrameIndex;
  final ValueChanged<String> onText;
  final ValueChanged<double> onTextSize;
  final ValueChanged<Color> onTextColor;
  final ValueChanged<String> onTextFontFamily;

  const _CreativePanel({
    this.forceTab,
    required this.blendImagePath,
    required this.blendMode,
    required this.blendOpacity,
    required this.frameIndex,
    required this.overlayText,
    required this.textSize,
    required this.textColor,
    required this.textFontFamily,
    required this.onPickBlend,
    required this.onBlendMode,
    required this.onBlendOpacity,
    required this.onFrameIndex,
    required this.onText,
    required this.onTextSize,
    required this.onTextColor,
    required this.onTextFontFamily,
  });

  @override
  State<_CreativePanel> createState() => _CreativePanelState();
}

class _CreativePanelState extends State<_CreativePanel> {
  late _CreativeSubTab _sub;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _sub = widget.forceTab ?? _CreativeSubTab.doubleExposure;
    _textController = TextEditingController(text: widget.overlayText);
  }

  @override
  void didUpdateWidget(covariant _CreativePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayText != widget.overlayText &&
        _textController.text != widget.overlayText) {
      _textController.value = TextEditingValue(
        text: widget.overlayText,
        selection: TextSelection.collapsed(offset: widget.overlayText.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.forceTab == null) ...[
          // sub-tab row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _SubTabBtn(
                    label: '이중 노출',
                    icon: Icons.layers_rounded,
                    selected: _sub == _CreativeSubTab.doubleExposure,
                    onTap: () =>
                        setState(() => _sub = _CreativeSubTab.doubleExposure)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: '프레임',
                    icon: Icons.photo_size_select_large_rounded,
                    selected: _sub == _CreativeSubTab.frame,
                    onTap: () => setState(() => _sub = _CreativeSubTab.frame)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: '텍스트',
                    icon: Icons.text_fields_rounded,
                    selected: _sub == _CreativeSubTab.text,
                    onTap: () => setState(() => _sub = _CreativeSubTab.text)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_sub == _CreativeSubTab.doubleExposure)
          _buildDoubleExposure()
        else if (_sub == _CreativeSubTab.frame)
          _buildFrame()
        else
          _buildText(),
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
                border: Border.all(color: AppColors.oceanFoam.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_rounded,
                      size: 18, color: AppColors.oceanFoam),
                  const SizedBox(width: 8),
                  Text(
                    widget.blendImagePath != null ? '이미지 변경' : '이미지 선택',
                    style: const TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 13,
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
                  onTap: () {
                    hapticLight();
                    widget.onBlendMode(m);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(m.label,
                        style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 12,
                            color: sel
                                ? AppColors.cloudWhite
                                : AppColors.textOnDarkSub)),
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
          const SizedBox(
              width: 56,
              child: Text('불투명도',
                  style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub))),
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
                  value: widget.blendOpacity,
                  min: 0,
                  max: 1,
                  onChanged: widget.onBlendOpacity),
            ),
          ),
          SizedBox(
              width: 32,
              child: Text('${(widget.blendOpacity * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
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
              onTap: () {
                hapticLight();
                widget.onFrameIndex(-1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel
                          ? AppColors.oceanFoam
                          : AppColors.oceanFoam.withOpacity(0.15)),
                ),
                child: const Center(
                    child: Text('없음',
                        style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 11,
                            color: AppColors.textOnDarkSub))),
              ),
            );
          }
          final idx = i - 1;
          final sel = widget.frameIndex == idx;
          return GestureDetector(
            onTap: () {
              hapticLight();
              widget.onFrameIndex(idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 64,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? AppColors.oceanFoam : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(_frameAssets[idx],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppColors.oceanNavy)),
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
            controller: _textController,
            onChanged: widget.onText,
            style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 14,
                color: AppColors.textOnDark),
            decoration: InputDecoration(
              hintText: '텍스트 입력…',
              hintStyle: const TextStyle(
                  fontFamily: 'NotoSerif', color: AppColors.textOnDarkTert),
              filled: true,
              fillColor: AppColors.oceanNavy,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              '사진 위 텍스트를 드래그해 옮기고, 두 손가락으로 크기와 회전을 조절하세요.',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 11,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                  width: 48,
                  child: Text('크기',
                      style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          color: AppColors.textOnDarkSub))),
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
                      value: widget.textSize,
                      min: 12,
                      max: 96,
                      onChanged: widget.onTextSize),
                ),
              ),
              SizedBox(
                  width: 36,
                  child: Text(widget.textSize.round().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 11,
                          color: AppColors.textOnDarkTert))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                  width: 48,
                  child: Text('폰트',
                      style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          color: AppColors.textOnDarkSub))),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: TextRasterizer.presetFonts.map((font) {
                      final sel = widget.textFontFamily == font;
                      return GestureDetector(
                        onTap: () {
                          hapticLight();
                          widget.onTextFontFamily(font);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel
                                  ? AppColors.oceanFoam
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            font,
                            style: TextStyle(
                              fontFamily: font,
                              fontSize: 11,
                              color: sel
                                  ? AppColors.cloudWhite
                                  : AppColors.textOnDarkSub,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('색상',
                  style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub)),
              const SizedBox(width: 12),
              ...[
                Colors.white,
                Colors.black,
                Colors.yellow,
                Colors.red,
                Colors.blue,
                Colors.green
              ].map((c) {
                final sel = widget.textColor == c;
                return GestureDetector(
                  onTap: () {
                    hapticLight();
                    widget.onTextColor(c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
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

// ── Preview Isolate ───────────────────────────────────────────

class _PreviewParams {
  final int width;
  final int height;
  final Uint8List imageBytes;
  final EditorRenderRecipe recipe;
  final EditorRenderResources resources;
  final String? overlayTextOverride;

  const _PreviewParams({
    required this.width,
    required this.height,
    required this.imageBytes,
    required this.recipe,
    required this.resources,
    this.overlayTextOverride,
  });
}

Future<Uint8List> _previewWorker(_PreviewParams p) async {
  return EditorRenderer.renderPreviewBytes(
    EditorPreviewRenderRequest(
      width: p.width,
      height: p.height,
      imageBytes: p.imageBytes,
      recipe: p.recipe,
      resources: EditorRenderResources(
        segmentMask: p.resources.segmentMask,
        segmentMaskWidth: p.resources.segmentMaskWidth,
        segmentMaskHeight: p.resources.segmentMaskHeight,
        blendImageBytes: p.resources.blendImageBytes,
        frameBytes: p.resources.frameBytes,
        overlayTextOverride: p.overlayTextOverride,
        textOverlayBytes: p.resources.textOverlayBytes,
      ),
    ),
  );
}

class _ToolItem {
  final String id;
  final String label;
  final IconData icon;

  const _ToolItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}
