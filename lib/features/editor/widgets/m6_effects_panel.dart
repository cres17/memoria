import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/adjust_params.dart';

class LightLeakPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const LightLeakPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return _M6Panel(
      sliders: [
        _M6SliderSpec(
          label: S.get('light_leak.strength'),
          icon: Icons.flare_rounded,
          value: params.lightLeakStrength,
          min: 0,
          max: 100,
          onChanged: (v) => onChanged(params.copyWith(lightLeakStrength: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(lightLeakStrength: v)),
        ),
        _M6SliderSpec(
          label: S.get('light_leak.angle'),
          icon: Icons.rotate_right_rounded,
          value: params.lightLeakAngle,
          min: 0,
          max: 360,
          onChanged: (v) => onChanged(params.copyWith(lightLeakAngle: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(lightLeakAngle: v)),
        ),
        _M6SliderSpec(
          label: S.get('light_leak.warmth'),
          icon: Icons.thermostat_rounded,
          value: params.lightLeakWarmth,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(params.copyWith(lightLeakWarmth: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(lightLeakWarmth: v)),
        ),
      ],
    );
  }
}

class HalationPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const HalationPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return _M6Panel(
      sliders: [
        _M6SliderSpec(
          label: S.get('halation.strength'),
          icon: Icons.wb_incandescent_rounded,
          value: params.halationStrength,
          min: 0,
          max: 100,
          onChanged: (v) => onChanged(params.copyWith(halationStrength: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(halationStrength: v)),
        ),
        _M6SliderSpec(
          label: S.get('halation.threshold'),
          icon: Icons.tonality_rounded,
          value: params.halationThreshold,
          min: 25,
          max: 95,
          onChanged: (v) => onChanged(params.copyWith(halationThreshold: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(halationThreshold: v)),
        ),
        _M6SliderSpec(
          label: S.get('halation.warmth'),
          icon: Icons.local_fire_department_rounded,
          value: params.halationWarmth,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(params.copyWith(halationWarmth: v)),
          onChangeEnd: (v) =>
              onChangeEnd?.call(params.copyWith(halationWarmth: v)),
        ),
      ],
    );
  }
}

class _M6Panel extends StatelessWidget {
  final List<_M6SliderSpec> sliders;

  const _M6Panel({required this.sliders});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: sliders.map((s) => _M6Slider(spec: s)).toList(),
      ),
    );
  }
}

class _M6SliderSpec {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _M6SliderSpec({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });
}

class _M6Slider extends StatelessWidget {
  final _M6SliderSpec spec;

  const _M6Slider({required this.spec});

  static const _accent = Color(0xFFD0784F);

  @override
  Widget build(BuildContext context) {
    final value = spec.value.clamp(spec.min, spec.max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                      color: _accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(spec.icon, size: 15, color: _accent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    spec.label,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Text(
                value.round().toString(),
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 14,
                  color: _accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accent,
              inactiveTrackColor: AppColors.cloudMist.withOpacity(0.55),
              thumbColor: _accent,
              overlayColor: _accent.withOpacity(0.15),
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: spec.min,
              max: spec.max,
              onChanged: spec.onChanged,
              onChangeEnd: spec.onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}
