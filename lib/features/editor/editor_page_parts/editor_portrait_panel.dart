part of '../editor_page.dart';

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
                    fontSize: 12,
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
                      fontSize: 12,
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
