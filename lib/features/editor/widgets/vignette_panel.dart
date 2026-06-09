import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/adjust_params.dart';

class VignettePanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const VignettePanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.onChangeEnd,
  });

  static const _kAccent = Color(0xFF2E7D95);

  @override
  Widget build(BuildContext context) {
    final isNeutral = params.vignette.round() == 0;
    final displayValue = params.vignette.round().toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    child: const Icon(Icons.blur_circular_outlined, size: 15, color: _kAccent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.get('vignette.strength'),
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
              value: params.vignette.clamp(0, 100),
              min: 0,
              max: 100,
              onChanged: (v) => onChanged(params.copyWith(vignette: v)),
              onChangeEnd: (v) => onChangeEnd?.call(params.copyWith(vignette: v)),
            ),
          ),
        ],
      ),
    );
  }
}
