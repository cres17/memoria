import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../domain/models/adjust_params.dart';
import '../../../core/theme/app_colors.dart';

class GrainPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const GrainPanel({
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
          _GrainSlider(
            label: S.get('grain.strength'),
            icon: Icons.grain_rounded,
            value: params.grainStrength,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(grainStrength: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(grainStrength: v)),
          ),
          _GrainSlider(
            label: S.get('grain.size'),
            icon: Icons.texture_rounded,
            value: params.grainSize,
            min: 0.5,
            max: 3.0,
            decimals: 1,
            onChanged: (v) => onChanged(params.copyWith(grainSize: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(grainSize: v)),
          ),
          const SizedBox(height: 8),
          _SeedRow(
            seed: params.grainSeed,
            onRandomize: () {
              final rng = DateTime.now().millisecondsSinceEpoch & 0xFFFF;
              onChanged(params.copyWith(grainSeed: rng));
            },
          ),
        ],
      ),
    );
  }
}

// ?? Slider ????????????????????????????????????????????????

class _GrainSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _GrainSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.decimals = 0,
  });

  static const _kAccent = Color(0xFFB8A68C);

  @override
  Widget build(BuildContext context) {
    final isNeutral = value <= min + 0.01;
    final displayValue = decimals > 0
        ? value.toStringAsFixed(decimals)
        : value.round().toString();

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

// ?? Seed randomizer row ???????????????????????????????????

class _SeedRow extends StatelessWidget {
  final int seed;
  final VoidCallback onRandomize;

  const _SeedRow({required this.seed, required this.onRandomize});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${S.get('grain.seed')}  $seed',
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        TextButton.icon(
          onPressed: onRandomize,
          icon: const Icon(Icons.shuffle_rounded,
              size: 15, color: Color(0xFFB8A68C)),
          label: Text(
            S.get('grain.randomize'),
            style: const TextStyle(
              fontFamily: 'NotoSerif',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFFB8A68C),
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
