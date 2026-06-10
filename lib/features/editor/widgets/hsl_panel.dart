import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/adjust_params.dart';

class HslPanel extends StatefulWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const HslPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<HslPanel> createState() => _HslPanelState();
}

class _HslPanelState extends State<HslPanel> {
  HslBand _selectedBand = HslBand.red;

  static const _kBandColors = <HslBand, Color>{
    HslBand.red: Color(0xFFFF5252),
    HslBand.orange: Color(0xFFFF9800),
    HslBand.yellow: Color(0xFFFFEB3B),
    HslBand.green: Color(0xFF4CAF50),
    HslBand.cyan: Color(0xFF00BCD4),
    HslBand.blue: Color(0xFF2196F3),
    HslBand.purple: Color(0xFF9C27B0),
    HslBand.magenta: Color(0xFFE91E63),
  };

  String _bandLabel(HslBand band) {
    switch (band) {
      case HslBand.red:
        return S.get('hsl.red');
      case HslBand.orange:
        return S.get('hsl.orange');
      case HslBand.yellow:
        return S.get('hsl.yellow');
      case HslBand.green:
        return S.get('hsl.green');
      case HslBand.cyan:
        return S.get('hsl.cyan');
      case HslBand.blue:
        return S.get('hsl.blue');
      case HslBand.purple:
        return S.get('hsl.purple');
      case HslBand.magenta:
        return S.get('hsl.magenta');
    }
  }

  HslBandParams get _currentBand =>
      widget.params.hsl[_selectedBand] ?? HslBandParams.zero;

  void _update(HslBandParams bp) {
    widget.onChanged(widget.params.withHslBand(_selectedBand, bp));
  }

  @override
  Widget build(BuildContext context) {
    final color = _kBandColors[_selectedBand]!;
    final displayColor = _selectedBand == HslBand.yellow
        ? const Color(0xFFD4B106)
        : (_selectedBand == HslBand.cyan
            ? const Color(0xFF0097A7)
            : color);
    final bp = _currentBand;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Band selector chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: HslBand.values.map((band) {
                final selected = band == _selectedBand;
                final c = _kBandColors[band]!;
                final bandParams = widget.params.hsl[band] ?? HslBandParams.zero;
                final isModified = bandParams.hue != 0.0 ||
                    bandParams.saturation != 0.0 ||
                    bandParams.luminance != 0.0;

                return GestureDetector(
                  onTap: () => setState(() => _selectedBand = band),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? c.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? (band == HslBand.yellow
                                ? const Color(0xFFD4B106)
                                : (band == HslBand.cyan
                                    ? const Color(0xFF0097A7)
                                    : c))
                            : AppColors.textSecondary.withOpacity(0.18),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _bandLabel(band),
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'NotoSerif',
                            color: selected
                                ? Colors.black
                                : Colors.black54,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        if (isModified) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: selected
                                  ? (band == HslBand.yellow
                                      ? const Color(0xFFD4B106)
                                      : (band == HslBand.cyan
                                          ? const Color(0xFF0097A7)
                                          : c))
                                  : AppColors.textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Three sliders: Hue / Saturation / Luminance
          _HslSlider(
            label: S.get('hsl.hue'),
            icon: Icons.colorize_rounded,
            color: displayColor,
            value: bp.hue,
            min: -180,
            max: 180,
            onChanged: (v) => _update(bp.copyWith(hue: v)),
            onChangeEnd: (v) => widget.onChangeEnd?.call(
                widget.params.withHslBand(_selectedBand, bp.copyWith(hue: v))),
          ),
          _HslSlider(
            label: S.get('hsl.saturation'),
            icon: Icons.water_drop_rounded,
            color: displayColor,
            value: bp.saturation,
            min: -100,
            max: 100,
            onChanged: (v) => _update(bp.copyWith(saturation: v)),
            onChangeEnd: (v) => widget.onChangeEnd?.call(widget.params
                .withHslBand(_selectedBand, bp.copyWith(saturation: v))),
          ),
          _HslSlider(
            label: S.get('hsl.luminance'),
            icon: Icons.brightness_6_rounded,
            color: displayColor,
            value: bp.luminance,
            min: -100,
            max: 100,
            onChanged: (v) => _update(bp.copyWith(luminance: v)),
            onChangeEnd: (v) => widget.onChangeEnd?.call(widget.params
                .withHslBand(_selectedBand, bp.copyWith(luminance: v))),
          ),
        ],
      ),
    );
  }
}

class _HslSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _HslSlider({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isNeutral = value.abs() < 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 15, color: color),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                value.round().toString(),
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 14,
                  color: isNeutral ? Colors.black54 : color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: AppColors.textSecondary.withOpacity(0.12),
              thumbColor: color,
              overlayColor: color.withOpacity(0.15),
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
