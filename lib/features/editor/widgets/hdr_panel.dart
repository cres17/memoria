import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/adjust_params.dart';

class HdrPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const HdrPanel({
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
          _HdrSlider(
            label: S.get('hdr.strength'),
            icon: Icons.hdr_strong_outlined,
            value: params.hdrStrength,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(hdrStrength: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(hdrStrength: v)),
          ),
          _HdrSlider(
            label: S.get('hdr.saturation'),
            icon: Icons.palette_outlined,
            value: params.hdrSaturation,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(hdrSaturation: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(hdrSaturation: v)),
          ),
        ],
      ),
    );
  }
}

class _HdrSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _HdrSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  static const _kAccent = Color(0xFF2E7D95);

  @override
  Widget build(BuildContext context) {
    final isNeutral = value.round() == 0;
    final displayValue = value.round().toString();

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
                  displayValue,
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
              inactiveTrackColor: AppColors.cloudMist.withValues(alpha: 0.55),
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
