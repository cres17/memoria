part of '../editor_page.dart';

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
                fontSize: 12,
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
