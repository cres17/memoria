part of 'editor_page.dart';

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
      message: S.get('editor.apply'),
      child: Semantics(
        button: true,
        label: S.get('editor.apply'),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(
                    S.get('editor.apply'),
                    style: const TextStyle(
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
                  color: AppColors.oceanFoam.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                S.get(preset.l10nKey),
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
    _EffectGroup('effect.none', [ArtisticEffect.none]),
    _EffectGroup('effect.film', [
      ArtisticEffect.grain,
      ArtisticEffect.grainyFilm,
      ArtisticEffect.vintage,
      ArtisticEffect.retrolux
    ]),
    _EffectGroup('effect.drama', [
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
    _EffectGroup(
        'effect.other', [ArtisticEffect.glamourGlow, ArtisticEffect.grunge]),
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
                    return _GroupDivider(label: S.get(groups[g].label));
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
                Text(
                  S.get('editor.effect_strength'),
                  style: const TextStyle(
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
                      overlayColor: AppColors.oceanFoam.withValues(alpha: 0.2),
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
              S.get(widget.effect.l10nKey),
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
        _row(S.get('editor.portrait_smooth'), smooth, 0, 100, onSmooth),
        _row(S.get('editor.portrait_brighten'), spotlight, 0, 100, onSpotlight),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(S.get('editor.portrait_tone'),
              style: const TextStyle(
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
          _row(S.get('editor.portrait_tone_strength'), skinStrength, 0, 100,
              onSkinStrength),
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
            ? S.get('editor.portrait_on_device')
            : isLoading
                ? S
                    .get('editor.portrait_preparing')
                    .replaceAll('{n}', '${(state.progress * 100).round()}')
                : S.get('editor.portrait_unavailable');
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
                  child: Text(S.get('editor.retry')),
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
                    label: S.get('tool.double_exposure'),
                    icon: Icons.layers_rounded,
                    selected: _sub == _CreativeSubTab.doubleExposure,
                    onTap: () =>
                        setState(() => _sub = _CreativeSubTab.doubleExposure)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: S.get('tool.frame'),
                    icon: Icons.photo_size_select_large_rounded,
                    selected: _sub == _CreativeSubTab.frame,
                    onTap: () => setState(() => _sub = _CreativeSubTab.frame)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: S.get('tool.text'),
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
                border: Border.all(
                    color: AppColors.oceanFoam.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_rounded,
                      size: 18, color: AppColors.oceanFoam),
                  const SizedBox(width: 8),
                  Text(
                    widget.blendImagePath != null
                        ? S.get('editor.change_image')
                        : S.get('editor.select_image'),
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
          SizedBox(
              width: 56,
              child: Text(S.get('editor.opacity'),
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
                          : AppColors.oceanFoam.withValues(alpha: 0.15)),
                ),
                child: Center(
                    child: Text(S.get('editor.none'),
                        style: const TextStyle(
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
              hintText: S.get('editor.text_input_hint'),
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
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              S.get('editor.text_overlay_hint'),
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 11,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                  width: 48,
                  child: Text(S.get('editor.size'),
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
              SizedBox(
                  width: 48,
                  child: Text(S.get('editor.font'),
                      style: const TextStyle(
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
              Text(S.get('editor.color'),
                  style: const TextStyle(
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
