import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../domain/models/adjust_params.dart';
import '../../../core/theme/app_colors.dart';

class NoisePanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const NoisePanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NoiseSlider(
            label: S.get('noise.luminance'),
            icon: Icons.blur_on_rounded,
            value: params.luminanceNR,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(luminanceNR: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(luminanceNR: v)),
          ),
          _NoiseSlider(
            label: S.get('noise.colour'),
            icon: Icons.color_lens_outlined,
            value: params.colourNR,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(colourNR: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(colourNR: v)),
          ),
          _NoiseSlider(
            label: S.get('noise.detail'),
            icon: Icons.details_rounded,
            value: params.nrDetail,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(nrDetail: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(nrDetail: v)),
          ),
        ],
      ),
    );
  }
}

class _NoiseSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _NoiseSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  static const _kAccent = Color(0xFF8CA6B8);

  @override
  Widget build(BuildContext context) {
    final isNeutral = value <= min + 0.01;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 15, color: _kAccent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              AnimatedOpacity(
                opacity: isNeutral ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Text(
                  value.round().toString(),
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 14,
                    color: _kAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kAccent,
              inactiveTrackColor: AppColors.textTertiary.withValues(alpha: 0.15),
              thumbColor: _kAccent,
              overlayColor: _kAccent.withValues(alpha: 0.15),
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}
