import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/filter_preset.dart';

class FilterStrip extends StatelessWidget {
  final List<FilterPreset> presets;
  final String? selectedId;
  final ValueChanged<FilterPreset?> onSelect;
  final String? previewImagePath;

  const FilterStrip({
    super.key,
    required this.presets,
    required this.selectedId,
    required this.onSelect,
    this.previewImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: presets.length,
        itemBuilder: (ctx, i) {
          final preset = presets[i];
          final selected = preset.id == selectedId;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(selected ? null : preset);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
              width: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.oceanFoam
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _FilterThumbnail(
                        preset: preset,
                        selected: selected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selected
                          ? AppColors.oceanFoam
                          : AppColors.textOnDarkTert,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterThumbnail extends StatelessWidget {
  final FilterPreset preset;
  final bool selected;

  const _FilterThumbnail({required this.preset, required this.selected});

  @override
  Widget build(BuildContext context) {
    final path = preset.thumbnailPath;

    Widget image;
    if (path.startsWith('assets/')) {
      image = Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (path.isNotEmpty) {
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      image = _placeholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (selected)
          Container(
            color: AppColors.oceanFoam.withOpacity(0.15),
          ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.oceanNavy,
      child: const Center(
        child: Icon(Icons.filter_rounded,
            color: AppColors.textOnDarkTert, size: 24),
      ),
    );
  }
}

/// Intensity slider shown below the filter strip
class IntensitySlider extends StatelessWidget {
  final double value; // 0.0 ~ 1.0
  final ValueChanged<double> onChanged;

  const IntensitySlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text(
            '강도',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textOnDarkSub,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                overlayColor: AppColors.oceanFoam.withOpacity(0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.oceanFoam,
            ),
          ),
        ],
      ),
    );
  }
}
