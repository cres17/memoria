part of 'editor_page.dart';

extension _EditorToolControls on _EditorPageState {
  List<AdjustSliderItem> get _sliderItems => [
        AdjustSliderItem(
          label: S.get('editor.exposure'),
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
            _mutate(() => _params = _params.copyWith(exposure: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.contrast'),
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
            _mutate(() => _params = _params.copyWith(contrast: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.saturation'),
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
            _mutate(() => _params = _params.copyWith(saturation: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.temperature'),
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
            _mutate(() => _params = _params.copyWith(temperature: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.tint'),
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
            _mutate(() => _params = _params.copyWith(tint: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.highlights'),
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
            _mutate(() => _params = _params.copyWith(highlights: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.shadows'),
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
            _mutate(() => _params = _params.copyWith(shadows: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.sharpen'),
          icon: '',
          value: _params.sharpen,
          min: 0,
          max: 100,
          onChanged: (v) {
            _mutate(() => _params = _params.copyWith(sharpen: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: S.get('vignette.strength'),
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
            _mutate(() => _params = _params.copyWith(vignette: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.structure'),
          icon: '',
          value: _params.structure,
          min: -100,
          max: 100,
          onChanged: (v) {
            _mutate(() => _params = _params.copyWith(structure: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: S.get('editor.clarity'),
          icon: '',
          value: _params.clarity,
          min: -100,
          max: 100,
          onChanged: (v) {
            _mutate(() => _params = _params.copyWith(clarity: v));
            _debouncedPreview();
          },
          onChangeEnd: (_) => _renderPreview(),
        ),
        AdjustSliderItem(
          label: S.get('editor.tonal_shadows'),
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
            _mutate(() => _params = _params.copyWith(tonalShadows: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.tonal_midtones'),
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
            _mutate(() => _params = _params.copyWith(tonalMidtones: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
        AdjustSliderItem(
          label: S.get('editor.tonal_highlights'),
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
            _mutate(() => _params = _params.copyWith(tonalHighlights: v));
            _updateLiveSliding(_params);
            if (!_isSliding) _debouncedPreview();
          },
          onChangeEnd: (_) => _endLiveSliding(),
        ),
      ];

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
                inactiveTrackColor:
                    AppColors.textSecondary.withValues(alpha: 0.2),
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
                      : AppColors.textSecondary.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                S.get(preset.l10nKey),
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
    _mutate(() {
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
                        _mutate(
                            () => _params = _params.copyWith(bnwEnabled: v));
                        _renderPreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_rounded,
                        color: Colors.black87),
                    tooltip: S.get('editor.adjustment_save'),
                    onPressed: _showSaveAdjustmentDialog,
                  ),
                  if (_customAdjustments.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.bookmarks_rounded,
                          color: Colors.black87),
                      tooltip: S.get('editor.adjustment_load'),
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
              onSelectIndex: (i) => _mutate(() => _adjustIndex = i),
            ),
          ],
        );
      case 'details':
        return DetailsPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'curves':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CurveEditorPanel(
            curves: _curves,
            onChanged: (channel, data) {
              _mutate(() {
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
                  _mutate(() => _params = preset.applyTo(_params));
                  _renderPreview();
                },
              ),
            ),
            const SizedBox(height: 8),
            _sliderRow(
                S.get('editor.temperature'), _params.temperature, -100, 100,
                (v) {
              _mutate(() => _params = _params.copyWith(temperature: v));
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.tint'), _params.tint, -100, 100, (v) {
              _mutate(() => _params = _params.copyWith(tint: v));
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
                  _mutate(() => _intensity = v);
                  _debouncedPreview();
                },
                onChangeEnd: (_) => _renderPreview(),
              ),
          ],
        );
      case 'rotate':
        return Column(
          children: [
            _sliderRow(S.get('editor.rotation'), _rotation, -45, 45, (v) {
              _mutate(() => _rotation = v);
            }, onChangeEnd: (_) => _renderPreview()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionChip(S.get('editor.flip_horizontal'),
                      Icons.flip_rounded, _flipH, () {
                    _mutate(() => _flipH = !_flipH);
                  }),
                  _actionChip(
                      S.get('editor.flip_vertical'), Icons.flip_rounded, _flipV,
                      () {
                    _mutate(() => _flipV = !_flipV);
                  }, rotate: true),
                ],
              ),
            ),
          ],
        );
      case 'perspective':
        return Column(
          children: [
            _sliderRow(S.get('editor.perspective_horizontal'), _perspH, -20, 20,
                (v) {
              _mutate(() => _perspH = v);
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.perspective_vertical'), _perspV, -20, 20,
                (v) {
              _mutate(() => _perspV = v);
              _debouncedPreview();
            }),
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(S.get('editor.reset_tilt')),
              onPressed: () {
                _mutate(() {
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
                final label =
                    S.get(m == 'black' ? 'editor.black' : 'editor.white');
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: sel,
                    onSelected: (_) {
                      _mutate(() => _expandMode = m);
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
            _sliderRow(S.get('editor.expand_top'), _expandTop, 0.0, 0.5, (v) {
              _mutate(() => _expandTop = v);
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.expand_bottom'), _expandBottom, 0.0, 0.5,
                (v) {
              _mutate(() => _expandBottom = v);
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.expand_left'), _expandLeft, 0.0, 0.5, (v) {
              _mutate(() => _expandLeft = v);
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.expand_right'), _expandRight, 0.0, 0.5,
                (v) {
              _mutate(() => _expandRight = v);
              _debouncedPreview();
            }),
          ],
        );
      case 'hsl':
        return HslPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
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
                    ? S.get('editor.selective_active_hint')
                    : S.get('editor.selective_inactive_hint'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (_selActive) ...[
              _sliderRow(S.get('editor.brightness'), _selBright, -100, 100,
                  (v) {
                _mutate(() => _selBright = v);
                _debouncedPreview();
              }),
              _sliderRow(S.get('editor.contrast'), _selContrast, -100, 100,
                  (v) {
                _mutate(() => _selContrast = v);
                _debouncedPreview();
              }),
              _sliderRow(S.get('editor.saturation'), _selSat, -100, 100, (v) {
                _mutate(() => _selSat = v);
                _debouncedPreview();
              }),
              _sliderRow(S.get('editor.radius'), _selRadius, 0.1, 0.8, (v) {
                _mutate(() => _selRadius = v);
                _debouncedPreview();
              }),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(S.get('editor.selective_add_hint'),
                    style: const TextStyle(
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
                  label: Text(S.get('editor.brush_brighten')),
                  selected: _brushMode == 'dodge',
                  onSelected: (selected) {
                    if (selected) _mutate(() => _brushMode = 'dodge');
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
                  label: Text(S.get('editor.brush_darken')),
                  selected: _brushMode == 'burn',
                  onSelected: (selected) {
                    if (selected) _mutate(() => _brushMode = 'burn');
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
            _sliderRow(
                S.get('editor.radius'),
                _brushMode == 'dodge' ? _dodgeRadius : _burnRadius,
                0.05,
                0.5, (v) {
              _mutate(() {
                if (_brushMode == 'dodge') {
                  _dodgeRadius = v;
                } else {
                  _burnRadius = v;
                }
              });
            }),
            _sliderRow(
                S.get('editor.effect_strength'),
                _brushMode == 'dodge' ? _dodgeStrength : _burnStrength,
                0.0,
                1.0, (v) {
              _mutate(() {
                if (_brushMode == 'dodge') {
                  _dodgeStrength = v;
                } else {
                  _burnStrength = v;
                }
              });
            }),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_rounded),
              label: Text(S.get('editor.clear_brush')),
              onPressed: () {
                _mutate(() {
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
            _sliderRow(
                S.get('editor.focus_position'), _tiltFocusCenter, 0.0, 1.0,
                (v) {
              _mutate(() {
                _tiltActive = true;
                _tiltFocusCenter = v;
              });
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.band_width'), _tiltBandWidth, 0.1, 0.6,
                (v) {
              _mutate(() {
                _tiltActive = true;
                _tiltBandWidth = v;
              });
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.max_blur'), _tiltMaxBlur, 0.0, 20.0, (v) {
              _mutate(() {
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
              child: Text(
                S.get('editor.lens_blur_hint'),
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            _sliderRow(S.get('editor.focus_depth'), _lensFocusDepth, 0.0, 1.0,
                (v) {
              _mutate(() {
                _lensActive = _lensMaxRadius > 0;
                _lensFocusDepth = v;
              });
              _debouncedPreview();
            }),
            _sliderRow(S.get('editor.blur_radius'), _lensMaxRadius, 0.0, 20.0,
                (v) {
              _mutate(() {
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
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'grain':
        return GrainPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'split_toning':
        return SplitToningPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'noise':
        return NoisePanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'glow':
        return GlowPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
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
            _mutate(() => _portraitSmooth = v);
            _debouncedPreview();
          },
          onSpotlight: (v) {
            _mutate(() => _portraitSpotlight = v);
            _debouncedPreview();
          },
          onSkinTone: (t) {
            _mutate(() => _skinTone = t);
            _renderPreview();
          },
          onSkinStrength: (v) {
            _mutate(() => _skinToneStrength = v);
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
            _mutate(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            _mutate(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            _mutate(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            _mutate(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            _mutate(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            _mutate(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            _mutate(() => _textFontFamily = font);
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
            _mutate(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            _mutate(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            _mutate(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            _mutate(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            _mutate(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            _mutate(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            _mutate(() => _textFontFamily = font);
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
            _mutate(() => _blendMode = m);
            _renderPreview();
          },
          onBlendOpacity: (o) {
            _mutate(() => _blendOpacity = o);
            _debouncedPreview();
          },
          onFrameIndex: (fi) {
            _mutate(() => _frameIndex = fi);
            _renderPreview();
          },
          onText: (t) {
            _mutate(() => _overlayText = t);
            _debouncedPreview();
          },
          onTextSize: (ts) {
            _mutate(() => _textSize = ts);
            _debouncedPreview();
          },
          onTextColor: (tc) {
            _mutate(() => _textColor = tc);
            _renderPreview();
          },
          onTextFontFamily: (font) {
            _mutate(() => _textFontFamily = font);
            _renderPreview();
          },
        );
      case 'light_leak':
        return LightLeakPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'halation':
        return HalationPanel(
          params: _params,
          onChanged: (p) {
            _mutate(() => _params = p);
            _debouncedPreview();
          },
        );
      case 'drama':
        return _EffectsPanel(
          imagePath: widget.imagePath,
          selected: _effect,
          strength: _effectStrength,
          forceGroup: 'effect.drama',
          onEffect: (e) {
            _mutate(() => _effect = e);
            _renderPreview();
          },
          onStrength: (v) {
            _mutate(() => _effectStrength = v);
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
            _mutate(() => _effect = e);
            _renderPreview();
          },
          onStrength: (v) {
            _mutate(() => _effectStrength = v);
            _debouncedPreview();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
