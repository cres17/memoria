import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';

class AdjustSliderItem {
  final String label;
  final dynamic icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? accent;

  const AdjustSliderItem({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    this.onChangeStart,
    required this.onChanged,
    this.onChangeEnd,
    this.accent,
  });
}

class AdjustSlider extends StatelessWidget {
  final AdjustSliderItem item;

  const AdjustSlider({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isNeutral = item.value.abs() < 0.5;
    final trackColor = item.accent ?? AppColors.oceanFoam;

    Widget iconWidget;
    if (item.icon is IconData) {
      iconWidget = Icon(
        item.icon as IconData,
        size: 18,
        color: item.accent ?? AppColors.textOnDarkSub,
      );
    } else {
      iconWidget = Text(
        item.icon.toString(),
        style: const TextStyle(fontSize: 16),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textOnDarkSub,
                    ),
                  ),
                ],
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isNeutral
                      ? AppColors.oceanNavy
                      : trackColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isNeutral
                        ? Colors.transparent
                        : trackColor.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _formatValue(item.value),
                  style: TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isNeutral ? AppColors.textOnDarkTert : trackColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: trackColor,
            inactiveTrackColor: AppColors.oceanNavy,
            thumbColor: trackColor,
            overlayColor: trackColor.withValues(alpha: 0.15),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: item.value.clamp(item.min, item.max),
            min: item.min,
            max: item.max,
            onChangeStart: item.onChangeStart,
            onChanged: (v) {
              hapticLight();
              item.onChanged(v);
            },
            onChangeEnd: item.onChangeEnd != null
                ? (v) {
                    item.onChangeEnd!(v);
                  }
                : null,
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
                  hapticLight();
                  onSelectIndex(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.oceanTeal : AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (items[i].icon.isNotEmpty) ...[
                        Text(items[i].icon,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontFamily: 'NotoSerif',
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
