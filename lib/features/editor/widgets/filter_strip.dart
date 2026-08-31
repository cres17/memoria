import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../../core/theme/app_colors.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../domain/models/filter_preset.dart';

class FilterStrip extends StatelessWidget {
  final List<FilterPreset> presets;
  final String? selectedId;
  final ValueChanged<FilterPreset?> onSelect;
  final String? previewImagePath;
  final Set<String>? favoriteIds;
  final ValueChanged<String>? onFavoriteToggle;

  const FilterStrip({
    super.key,
    required this.presets,
    required this.selectedId,
    required this.onSelect,
    this.previewImagePath,
    this.favoriteIds,
    this.onFavoriteToggle,
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
          final isFavorite = favoriteIds?.contains(preset.id) ?? false;

          return GestureDetector(
            onTap: () {
              hapticLight();
              onSelect(selected ? null : preset);
            },
            onLongPress: () {
              if (onFavoriteToggle != null) {
                hapticLight();
                onFavoriteToggle!(preset.id);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
              width: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.oceanFoam : Colors.transparent,
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
                        isFavorite: isFavorite,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
  final bool isFavorite;

  const _FilterThumbnail({
    required this.preset,
    required this.selected,
    required this.isFavorite,
  });

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
            color: AppColors.oceanFoam.withValues(alpha: 0.15),
          ),
        if (preset.brand != null)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              key: ValueKey('filter-brand-${preset.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Text(
                preset.brand!.wordmark,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.35,
                ),
              ),
            ),
          ),
        if (isFavorite)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Colors.amber,
                size: 12,
              ),
            ),
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
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const IntensitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            S.get('editor.effect_strength'),
            style: const TextStyle(
              fontFamily: 'NotoSerif',
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
                overlayColor: AppColors.oceanFoam.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                onChangeStart: onChangeStart,
                onChanged: (v) {
                  hapticLight();
                  onChanged(v);
                },
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontFamily: 'NotoSerif',
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

img.Image fixedFilterSampleForTest() {
  final image = img.Image(width: 72, height: 72);
  for (int y = 0; y < 72; y++) {
    for (int x = 0; x < 72; x++) {
      // simple non-solid gradient
      final v = (x + y) * 255 ~/ 142;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}
