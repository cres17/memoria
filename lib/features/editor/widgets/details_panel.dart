import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../domain/models/adjust_params.dart';
import '../../../core/theme/app_colors.dart';

class DetailsPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const DetailsPanel({
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
          _DetailsSlider(
            label: S.get('details.structure'),
            icon: Icons.grid_on_outlined,
            value: params.structure,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(structure: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(structure: v)),
          ),
          _DetailsSlider(
            label: S.get('details.clarity'),
            icon: Icons.details_outlined,
            value: params.clarity,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(clarity: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(clarity: v)),
          ),
          _DetailsSlider(
            label: S.get('details.sharpen'),
            icon: Icons.filter_center_focus_outlined,
            value: params.sharpen,
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(sharpen: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(sharpen: v)),
          ),
        ],
      ),
    );
  }
}

class _DetailsSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _DetailsSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  static const _kAccent = Color(0xFF2E7D95);

  void _reset() {
    onChanged(0.0);
    onChangeEnd?.call(0.0);
  }

  @override
  Widget build(BuildContext context) {
    final prefix = value > 0 ? '+' : '';
    final displayValue = value == 0 ? '0%' : '$prefix${value.round()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onDoubleTap: _reset,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _kAccent.withOpacity(0.14),
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
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: '두 번 탭하여 초기화',
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
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kAccent,
              inactiveTrackColor: AppColors.textTertiary.withOpacity(0.15),
              thumbColor: _kAccent,
              overlayColor: _kAccent.withOpacity(0.15),
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
