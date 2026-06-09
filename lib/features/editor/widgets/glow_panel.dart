import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/adjust_params.dart';

class GlowPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const GlowPanel({
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
          _GlowSlider(
            label: S.get('glow.strength'),
            icon: Icons.wb_twilight_outlined,
            value: params.glowStrength,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(glowStrength: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(glowStrength: v)),
          ),
          _GlowSlider(
            label: S.get('glow.saturation'),
            icon: Icons.palette_outlined,
            value: params.glowSaturation,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(glowSaturation: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(glowSaturation: v)),
          ),
          _GlowSlider(
            label: S.get('glow.warmth'),
            icon: Icons.thermostat_outlined,
            value: params.glowWarmth,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(glowWarmth: v)),
            onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(glowWarmth: v)),
          ),
        ],
      ),
    );
  }
}

class _GlowSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _GlowSlider({
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
