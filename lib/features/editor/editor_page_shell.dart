part of 'editor_page.dart';

extension _EditorPageShell on _EditorPageState {
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
                    Semantics(
                      button: true,
                      label: S.get('editor.go_back'),
                      excludeSemantics: true,
                      child: IconButton(
                        tooltip: S.get('editor.go_back'),
                        onPressed: () => context.pop(),
                        icon: Icon(backIcon(), color: AppColors.oceanFoam),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        S.get('editor.title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
      barrierLabel: S.get('editor.keep_editing'),
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
                      Text(
                        S.get('editor.discard_title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        S.get('editor.discard_body'),
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
                              child: Text(S.get('editor.keep_editing')),
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
                              child: Text(
                                S.get('editor.discard'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
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
              tooltip: S.get('editor.back'),
              onTap: _handleEditorBack,
            ),
            if (!_isToolActive) ...[
              const SizedBox(width: 8),
              _EditorOverlayIconButton(
                icon: Icons.undo_rounded,
                tooltip: S.get('editor.undo'),
                enabled: _history.canUndo,
                onTap: _undo,
              ),
              const SizedBox(width: 6),
              _EditorOverlayIconButton(
                icon: Icons.redo_rounded,
                tooltip: S.get('editor.redo'),
                enabled: _history.canRedo,
                onTap: _redo,
              ),
            ],
            const Spacer(),
            Text(
              S.get('editor.title'),
              style: const TextStyle(
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
                  _mutate(() {
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
                  _mutate(() {
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
                  _mutate(() {
                    _tiltActive = true;
                    _tiltFocusCenter = v;
                  });
                  _debouncedPreview();
                },
                onBandWidthChanged: (v) {
                  _mutate(() {
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
          label: S.get('editor.text_gesture_label'),
          hint: S.get('editor.text_gesture_hint'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _textGestureStartSize = _textSize;
              _textGestureStartRotation = _textRotation;
            },
            onScaleUpdate: (details) {
              _mutate(() {
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
          _mutate(() {
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

  Future<void> _pickBlendImage() async {
    if (_pickingBlendImage) return;
    _pickingBlendImage = true;
    try {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xFile != null && mounted) {
        _mutate(() => _blendImagePath = xFile.path);
        _renderPreview();
      }
    } finally {
      _pickingBlendImage = false;
    }
  }
}
