import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class BrushToolSpec {
  final String id;
  final String label;
  final IconData icon;

  const BrushToolSpec(this.id, this.label, this.icon);
}

const brushToolSpecs = [
  BrushToolSpec('exposure+', 'Dodge', Icons.light_mode_rounded),
  BrushToolSpec('exposure-', 'Burn', Icons.dark_mode_rounded),
  BrushToolSpec('saturation+', 'Sat+', Icons.palette_rounded),
  BrushToolSpec('saturation-', 'Sat-', Icons.format_color_reset_rounded),
  BrushToolSpec('temperature+', 'Warm', Icons.wb_sunny_rounded),
  BrushToolSpec('temperature-', 'Cool', Icons.ac_unit_rounded),
  BrushToolSpec('clarity+', 'Clarity', Icons.texture_rounded),
  BrushToolSpec('eraser', 'Eraser', Icons.cleaning_services_rounded),
];

class BrushToolbar extends StatelessWidget {
  final String selectedTool;
  final double brushSize;
  final double hardness;
  final int strokeCount;
  final ValueChanged<String> onToolChanged;
  final ValueChanged<double> onBrushSizeChanged;
  final ValueChanged<double> onHardnessChanged;
  final VoidCallback onClear;

  const BrushToolbar({
    super.key,
    required this.selectedTool,
    required this.brushSize,
    required this.hardness,
    required this.strokeCount,
    required this.onToolChanged,
    required this.onBrushSizeChanged,
    required this.onHardnessChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final spec = brushToolSpecs[index];
              final selected = spec.id == selectedTool;
              return Tooltip(
                message: spec.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onToolChanged(spec.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.oceanFoam
                          : AppColors.oceanNavy,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.cloudWhite
                            : AppColors.oceanFoam.withOpacity(0.18),
                      ),
                    ),
                    child: Icon(
                      spec.icon,
                      size: 19,
                      color: selected
                          ? AppColors.oceanDeep
                          : AppColors.textOnDarkSub,
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: brushToolSpecs.length,
          ),
        ),
        _BrushSlider(
          icon: Icons.circle_outlined,
          value: brushSize,
          min: 20,
          max: 300,
          label: 'Size',
          onChanged: onBrushSizeChanged,
        ),
        _BrushSlider(
          icon: Icons.blur_circular_rounded,
          value: hardness,
          min: 0,
          max: 1,
          label: 'Hardness',
          onChanged: onHardnessChanged,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$strokeCount strokes',
                style: const TextStyle(
                  color: AppColors.textOnDarkTert,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Clear brush',
                onPressed: strokeCount == 0 ? null : onClear,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: AppColors.textOnDarkSub,
                disabledColor: AppColors.textOnDarkTert.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrushSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _BrushSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Tooltip(
            message: label,
            child: Icon(icon, size: 17, color: AppColors.textOnDarkTert),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                overlayColor: AppColors.oceanFoam.withOpacity(0.16),
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              max == 1 ? '${(value * 100).round()}' : value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textOnDarkSub,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

