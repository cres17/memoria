import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/l10n/strings.dart';
import '../../../domain/models/adjust_params.dart';
import '../../../core/theme/app_colors.dart';

class SplitToningPanel extends StatelessWidget {
  final AdjustParams params;
  final ValueChanged<AdjustParams> onChanged;
  final ValueChanged<AdjustParams>? onChangeEnd;

  const SplitToningPanel({
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
          _SectionHeader(label: S.get('split.shadows')),
          _HueWheel(
            hue: params.splitShadowHue,
            sat: params.splitShadowSat,
            onHueChanged: (v) => onChanged(params.copyWith(splitShadowHue: v)),
            onSatChanged: (v) => onChanged(params.copyWith(splitShadowSat: v)),
            onHueChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(splitShadowHue: v)),
            onSatChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(splitShadowSat: v)),
            accentColor: const Color(0xFF6E8EBF),
          ),
          const SizedBox(height: 10),
          _SectionHeader(label: S.get('split.highlights')),
          _HueWheel(
            hue: params.splitHighHue,
            sat: params.splitHighSat,
            onHueChanged: (v) => onChanged(params.copyWith(splitHighHue: v)),
            onSatChanged: (v) => onChanged(params.copyWith(splitHighSat: v)),
            onHueChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(splitHighHue: v)),
            onSatChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(splitHighSat: v)),
            accentColor: const Color(0xFFD4A96A),
          ),
          const SizedBox(height: 10),
          _SplitSlider(
            label: S.get('split.balance'),
            value: params.splitBalance,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(params.copyWith(splitBalance: v)),
            onChangeEnd: (v) =>
                onChangeEnd?.call(params.copyWith(splitBalance: v)),
          ),
        ],
      ),
    );
  }
}

// ?? Section header ?????????????????????????????????????????

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ?? Hue wheel + saturation slider ?????????????????????????

class _HueWheel extends StatelessWidget {
  final double hue;
  final double sat;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSatChanged;
  final ValueChanged<double>? onHueChangeEnd;
  final ValueChanged<double>? onSatChangeEnd;
  final Color accentColor;

  const _HueWheel({
    required this.hue,
    required this.sat,
    required this.onHueChanged,
    required this.onSatChanged,
    this.onHueChangeEnd,
    this.onSatChangeEnd,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Compact hue ring picker (80횞80 touch target)
        GestureDetector(
          onPanUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            const center = Offset(40, 40);
            final local = box.globalToLocal(d.globalPosition);
            final angle =
                (math.atan2(local.dy - center.dy, local.dx - center.dx) *
                            180.0 /
                            math.pi +
                        360) %
                    360;
            onHueChanged(angle);
          },
          onPanEnd: (_) => onHueChangeEnd?.call(hue),
          child: SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: _HueRingPainter(hue: hue),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _SplitSlider(
            label: S.get('split.saturation'),
            value: sat,
            min: 0,
            max: 100,
            onChanged: onSatChanged,
            onChangeEnd: onSatChangeEnd,
            accentColor: accentColor,
          ),
        ),
      ],
    );
  }
}

// ?? Hue ring painter ???????????????????????????????????????

class _HueRingPainter extends CustomPainter {
  final double hue;
  const _HueRingPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 4;
    const strokeW = 12.0;

    // Spectrum ring
    const steps = 360;
    const sweep = 2 * math.pi / steps;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW;

    for (int i = 0; i < steps; i++) {
      final angle = i * sweep - math.pi / 2;
      paint.color = HSVColor.fromAHSV(1.0, i.toDouble(), 1.0, 1.0).toColor();
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        angle,
        sweep + 0.01,
        false,
        paint,
      );
    }

    // Current hue indicator dot
    final rad = (hue - 90) * math.pi / 180.0;
    final dx = cx + r * math.cos(rad);
    final dy = cy + r * math.sin(rad);
    canvas.drawCircle(
        Offset(dx, dy),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        Offset(dx, dy),
        7,
        Paint()
          ..color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_HueRingPainter old) => old.hue != hue;
}

// ?? Shared slider for split toning params ?????????????????

class _SplitSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? accentColor;

  const _SplitSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? const Color(0xFF8EB4E3);
    final isNeutral = value.abs() < 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            AnimatedOpacity(
              opacity: isNeutral ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                value.round().toString(),
                style: TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: AppColors.textTertiary.withOpacity(0.15),
            thumbColor: color,
            overlayColor: color.withOpacity(0.15),
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
    );
  }
}
