import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class AdjustSliderItem {
  final String label;
  final String icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const AdjustSliderItem({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
}

class AdjustSlider extends StatelessWidget {
  final AdjustSliderItem item;

  const AdjustSlider({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final pct = ((item.value - item.min) / (item.max - item.min)).clamp(0.0, 1.0);
    final isNeutral = item.value.abs() < 0.5;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    item.icon,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textOnDarkSub,
                    ),
                  ),
                ],
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isNeutral
                      ? AppColors.oceanNavy
                      : AppColors.oceanTeal.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isNeutral
                        ? Colors.transparent
                        : AppColors.oceanFoam.withOpacity(0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _formatValue(item.value),
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isNeutral
                        ? AppColors.textOnDarkTert
                        : AppColors.oceanFoam,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.oceanFoam,
            inactiveTrackColor: AppColors.oceanNavy,
            thumbColor: AppColors.cloudWhite,
            overlayColor: AppColors.oceanFoam.withOpacity(0.15),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: item.value.clamp(item.min, item.max),
            min: item.min,
            max: item.max,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              item.onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

/// Horizontal scrollable list of adjust parameter cards
class AdjustParamsPanel extends StatelessWidget {
  final List<AdjustSliderItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const AdjustParamsPanel({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Param selector tabs
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final selected = i == selectedIndex;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelectIndex(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.oceanTeal
                        : AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(items[i].icon,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? AppColors.cloudWhite
                              : AppColors.textOnDarkTert,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Active slider
        AdjustSlider(item: items[selectedIndex]),
      ],
    );
  }
}
