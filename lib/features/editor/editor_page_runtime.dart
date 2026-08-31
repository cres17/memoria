part of 'editor_page.dart';

extension _EditorRuntimeActions on _EditorPageState {
  Future<void> _loadFavoritesAndTip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('favorite_tool_ids');
      if (list != null) {
        _mutate(() {
          _favoriteToolIds = list;
        });
      }
      final dismissed = prefs.getBool('favorite_tip_dismissed') ?? false;
      _mutate(() {
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
      _mutate(() {
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
      _mutate(() {
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
    _mutate(() {
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
    _mutate(() {
      _lutBytes = lutBytes;
    });
    await _renderPreview();
  }

  Future<void> _selectPresetForPreview(FilterPreset? preset) async {
    // Filters are transactional like every other editing tool. Selecting one
    // only changes the preview; the top-right check commits it to history.
    if (!_isToolActive) {
      _activateTool('filter', S.get('nav.filters'));
    }
    await _selectPreset(preset);
  }

  void _debouncedPreview() {
    _previewScheduler.debounce(
      const Duration(milliseconds: 32),
      () => unawaited(_renderPreview()),
    );
  }

  void _captureComparePreview() {
    _comparePreviewBytes = _previewBytes;
  }

  void _setComparePreviewVisible(bool visible) {
    if (_showComparePreview == visible) return;
    _mutate(() => _showComparePreview = visible);
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
      if (mounted) _mutate(() => _isSliding = true);
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
        _mutate(() {
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
    _mutate(() {
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
        _mutate(() {
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
      _mutate(() {
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
    final renderToken = _previewScheduler.beginRequest();
    if (_processingPreview) {
      _previewPending = true;
      _scheduleDraftSave();
      return;
    }
    _previewPending = false;
    _mutate(() => _processingPreview = true);

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
        if (mounted && _previewScheduler.isLatest(renderToken)) {
          _mutate(() => _previewBytes = cachedPreview);
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
      final execution = await _previewScheduler.execute(
        params,
        token: renderToken,
      );
      // Stale token: a newer render was queued — discard this result but
      // still fall through so the pending re-dispatch fires.
      if (!mounted || !execution.isLatest) return;
      final bytes = execution.value;
      // Evict oldest entry (insertion-order) to keep cache at ≤24 entries.
      while (_previewRenderCache.length >= 24) {
        _previewRenderCache.remove(_previewRenderCache.keys.first);
      }
      _previewRenderCache[previewKey] = bytes;
      _mutate(() => _previewBytes = bytes);
    } catch (e, stackTrace) {
      ErrorLogger.log('Preview rendering failed', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.get('editor.preview_update_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) _mutate(() => _processingPreview = false);
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

    _mutate(() {
      _exporting = true;
      _exportProgress = 0;
      _exportForShare = share;
    });

    try {
      final result = await _mediaExportCoordinator.export(
        share: share,
        buildRequest: _buildExportRequest,
        onProgress: (progress) {
          if (mounted) _mutate(() => _exportProgress = progress);
        },
        onRetryAtLowerResolution: (dimension) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S
                  .get('editor.export_retry_lower_resolution')
                  .replaceAll('{n}', '$dimension')),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
      if (!result.cancelled && mounted) {
        _mutate(() => _exportProgress = 1.0);
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
        _mutate(() {
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
      _mutate(() {
        _exporting = false;
        _exportProgress = 0;
      });
    }
  }

  Future<void> _toggleFavorite(String presetId) async {
    // Update in-memory state immediately for instant UI response,
    // then persist — avoids a second async read-back and concurrent-toggle races.
    _mutate(() {
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
    if (mounted) _mutate(() => _customAdjustments = all);
  }

  Future<void> _deleteCustomAdjustment(String id) async {
    await _adjRepo.delete(id);
    final all = await _adjRepo.getAll();
    if (mounted) _mutate(() => _customAdjustments = all);
  }

  void _applyCustomAdjustment(CustomAdjustment adj) {
    _mutate(() {
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
        title: Text(
          S.get('editor.adjustment_preset_save'),
          style: const TextStyle(
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
            hintText: S.get('editor.adjustment_preset_name'),
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
            child: Text(S.get('common.cancel'),
                style: const TextStyle(color: AppColors.textOnDarkSub)),
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
            child: Text(S.get('editor.adjustment_save')),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      S.get('editor.adjustment_presets'),
                      style: const TextStyle(
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
                            child: Text(
                              S.get('editor.apply'),
                              style: const TextStyle(
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
    if (p.exposure.abs() >= 0.05) {
      parts.add(
          '${S.get('editor.exposure')} ${p.exposure > 0 ? '+' : ''}${p.exposure.toStringAsFixed(1)}');
    }
    if (p.contrast.abs() >= 1) {
      parts.add(
          '${S.get('editor.contrast')} ${p.contrast > 0 ? '+' : ''}${p.contrast.toInt()}');
    }
    if (p.saturation.abs() >= 1) {
      parts.add(
          '${S.get('editor.saturation')} ${p.saturation > 0 ? '+' : ''}${p.saturation.toInt()}');
    }
    if (p.temperature.abs() >= 1) {
      parts.add(
          '${S.get('editor.temperature')} ${p.temperature > 0 ? '+' : ''}${p.temperature.toInt()}');
    }
    if (parts.isEmpty) return S.get('editor.default_value');
    return parts.take(3).join(' · ');
  }
}
