import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';

class RotateFlipPanel extends StatelessWidget {
  final double rotation;
  final bool flipH;
  final bool flipV;
  final ValueChanged<double> onRotationChanged;
  final ValueChanged<double> onRotationEnd;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onRotate90;
  final VoidCallback onReset;

  const RotateFlipPanel({
    super.key,
    required this.rotation,
    required this.flipH,
    required this.flipV,
    required this.onRotationChanged,
    required this.onRotationEnd,
    required this.onFlipH,
    required this.onFlipV,
    required this.onRotate90,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // 90-degree component
    final Q = (rotation / 90.0).round() * 90;
    // Fine straightening component in [-45, 45]
    final fineRotation = (rotation - Q).clamp(-45.0, 45.0);

    final isNeutral = fineRotation.round() == 0;
    final displayValue = '${fineRotation.round()}°';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider and fine adjustment buttons
          Row(
            children: [
              IconButton(
                key: const Key('rotate_fine_dec'),
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    size: 20, color: AppColors.textOnDarkTert),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final nextS = (fineRotation - 1.0).clamp(-45.0, 45.0);
                  onRotationChanged(Q + nextS);
                  onRotationEnd(Q + nextS);
                },
                tooltip: '1° 줄이기',
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.oceanTeal,
                    inactiveTrackColor: AppColors.oceanNavy,
                    thumbColor: AppColors.oceanTeal,
                    overlayColor: AppColors.oceanTeal.withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    key: const Key('rotate_fine_slider'),
                    value: fineRotation,
                    min: -45,
                    max: 45,
                    divisions: 90,
                    onChanged: (v) {
                      onRotationChanged(Q + v);
                    },
                    onChangeEnd: (v) {
                      onRotationEnd(Q + v);
                    },
                  ),
                ),
              ),
              IconButton(
                key: const Key('rotate_fine_inc'),
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: AppColors.textOnDarkTert),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final nextS = (fineRotation + 1.0).clamp(-45.0, 45.0);
                  onRotationChanged(Q + nextS);
                  onRotationEnd(Q + nextS);
                },
                tooltip: '1° 늘리기',
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: const Key('rotate_fine_reset_text'),
                onTap: () {
                  if (!isNeutral) {
                    HapticFeedback.lightImpact();
                    onRotationChanged(Q.toDouble());
                    onRotationEnd(Q.toDouble());
                  }
                },
                child: Container(
                  width: 44,
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isNeutral ? AppColors.textOnDarkSub : AppColors.oceanTeal,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tool controls (90 deg rotate, Flip Horizontal, Flip Vertical, Reset All)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                key: const Key('rotate_90_btn'),
                icon: Icons.rotate_90_degrees_cw_rounded,
                label: S.get('rotate.rotate_90'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onRotate90();
                },
              ),
              const SizedBox(width: 12),
              _ActionButton(
                key: const Key('rotate_flip_h_btn'),
                icon: Icons.flip_rounded,
                label: S.get('rotate.flip_h'),
                active: flipH,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFlipH();
                },
              ),
              const SizedBox(width: 12),
              _ActionButton(
                key: const Key('rotate_flip_v_btn'),
                icon: Icons.flip_rounded,
                label: S.get('rotate.flip_v'),
                active: flipV,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFlipV();
                },
                rotateIcon: true,
              ),
              const SizedBox(width: 12),
              _ActionButton(
                key: const Key('rotate_reset_all_btn'),
                icon: Icons.refresh_rounded,
                label: S.get('rotate.reset'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onReset();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool rotateIcon;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
    this.rotateIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.oceanTeal : AppColors.oceanNavy.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.oceanTeal : AppColors.oceanNavy,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: rotateIcon ? 1.5708 : 0.0, // 90 degrees in radians
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? AppColors.cloudWhite : AppColors.textOnDarkSub,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? AppColors.cloudWhite : AppColors.textOnDarkSub,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
