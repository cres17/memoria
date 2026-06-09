import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';

class PerspectivePanel extends StatelessWidget {
  final double perspH;
  final double perspV;
  final ValueChanged<double> onPerspHChanged;
  final ValueChanged<double> onPerspHEnd;
  final ValueChanged<double> onPerspVChanged;
  final ValueChanged<double> onPerspVEnd;
  final VoidCallback onReset;

  const PerspectivePanel({
    super.key,
    required this.perspH,
    required this.perspV,
    required this.onPerspHChanged,
    required this.onPerspHEnd,
    required this.onPerspVChanged,
    required this.onPerspVEnd,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final hasChanges = perspH != 0.0 || perspV != 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                S.get('perspective.temporary_note'),
                key: const Key('persp_mode_note'),
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 11,
                  color: AppColors.textOnDarkTert,
                ),
              ),
            ),
          ),
          _buildSliderRow(
            context: context,
            sliderKey: const Key('persp_h_slider'),
            decKey: const Key('persp_h_dec'),
            incKey: const Key('persp_h_inc'),
            resetKey: const Key('persp_h_reset_text'),
            label: S.get('perspective.horizontal'),
            value: perspH,
            onChanged: onPerspHChanged,
            onChangeEnd: onPerspHEnd,
          ),
          const SizedBox(height: 12),
          _buildSliderRow(
            context: context,
            sliderKey: const Key('persp_v_slider'),
            decKey: const Key('persp_v_dec'),
            incKey: const Key('persp_v_inc'),
            resetKey: const Key('persp_v_reset_text'),
            label: S.get('perspective.vertical'),
            value: perspV,
            onChanged: onPerspVChanged,
            onChangeEnd: onPerspVEnd,
          ),
          if (hasChanges) ...[
            const SizedBox(height: 12),
            GestureDetector(
              key: const Key('persp_reset_all_btn'),
              onTap: () {
                HapticFeedback.lightImpact();
                onReset();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.oceanNavy.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.oceanNavy),
                ),
                child: Text(
                  S.get('perspective.reset'),
                  style: const TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.oceanTeal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required BuildContext context,
    required Key sliderKey,
    required Key decKey,
    required Key incKey,
    required Key resetKey,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final isNeutral = value.round() == 0;
    final displayValue = '${value.round()}°';

    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'NotoSerif',
              fontSize: 12,
              color: AppColors.textOnDarkSub,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        IconButton(
          key: decKey,
          icon: const Icon(
            Icons.remove_circle_outline_rounded,
            size: 18,
            color: AppColors.textOnDarkTert,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            final nextVal = (value - 1.0).clamp(-45.0, 45.0);
            onChanged(nextVal);
            onChangeEnd(nextVal);
          },
          tooltip: S.get('perspective.decrease'),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.oceanTeal,
              inactiveTrackColor: AppColors.oceanNavy,
              thumbColor: AppColors.oceanTeal,
              overlayColor: AppColors.oceanTeal.withValues(alpha: 0.2),
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              key: sliderKey,
              value: value,
              min: -45,
              max: 45,
              divisions: 90,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        IconButton(
          key: incKey,
          icon: const Icon(
            Icons.add_circle_outline_rounded,
            size: 18,
            color: AppColors.textOnDarkTert,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            final nextVal = (value + 1.0).clamp(-45.0, 45.0);
            onChanged(nextVal);
            onChangeEnd(nextVal);
          },
          tooltip: S.get('perspective.increase'),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          key: resetKey,
          onTap: () {
            if (!isNeutral) {
              HapticFeedback.lightImpact();
              onChanged(0.0);
              onChangeEnd(0.0);
            }
          },
          child: Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isNeutral ? Colors.transparent : AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              displayValue,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color:
                    isNeutral ? AppColors.textOnDarkTert : AppColors.oceanTeal,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
