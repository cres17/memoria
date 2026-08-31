import 'package:flutter/material.dart';

class FocusOverlayWidget extends StatefulWidget {
  final Size imageSize;
  final double focusCenter; // 0..1 (vertical)
  final double bandWidth; // 0..1 (relative height)
  final ValueChanged<double>? onFocusCenterChanged;
  final ValueChanged<double>? onBandWidthChanged;
  final VoidCallback? onDragEnd;

  const FocusOverlayWidget({
    super.key,
    required this.imageSize,
    required this.focusCenter,
    required this.bandWidth,
    this.onFocusCenterChanged,
    this.onBandWidthChanged,
    this.onDragEnd,
  });

  @override
  State<FocusOverlayWidget> createState() => _FocusOverlayWidgetState();
}

class _FocusOverlayWidgetState extends State<FocusOverlayWidget> {
  late double _focusCenter;
  late double _bandWidth;
  late double _scaleStartBandWidth;

  @override
  void initState() {
    super.initState();
    _focusCenter = widget.focusCenter.clamp(0.0, 1.0);
    _bandWidth = widget.bandWidth.clamp(0.01, 0.99);
    _scaleStartBandWidth = _bandWidth;
  }

  @override
  void didUpdateWidget(covariant FocusOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusCenter = widget.focusCenter.clamp(0.0, 1.0);
    _bandWidth = widget.bandWidth.clamp(0.01, 0.99);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _scaleStartBandWidth = _bandWidth;
  }

  void _handleScale(ScaleUpdateDetails d) {
    final h = context.size?.height ?? widget.imageSize.height;
    if (h <= 0) return;
    final nextCenter =
        (_focusCenter + d.focalPointDelta.dy / h).clamp(0.0, 1.0);
    final nextBandWidth = (_scaleStartBandWidth * d.scale).clamp(0.01, 0.99);
    setState(() {
      _focusCenter = nextCenter;
      _bandWidth = nextBandWidth;
    });
    widget.onFocusCenterChanged?.call(_focusCenter);
    widget.onBandWidthChanged?.call(_bandWidth);
  }

  void _end() {
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScale,
      onScaleEnd: (_) => _end(),
      child: CustomPaint(
        size: Size.infinite,
        painter: _FocusPainter(
          focusCenter: _focusCenter,
          bandWidth: _bandWidth,
        ),
      ),
    );
  }
}

class _FocusPainter extends CustomPainter {
  final double focusCenter;
  final double bandWidth;

  _FocusPainter({required this.focusCenter, required this.bandWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * focusCenter;
    final bandPx = size.height * bandWidth;
    final topY = (cy - bandPx / 2).clamp(0.0, size.height);
    final botY = (cy + bandPx / 2).clamp(0.0, size.height);

    // Draw dimming overlay
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.18);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, topY), overlay);
    canvas.drawRect(
        Rect.fromLTWH(0, botY, size.width, size.height - botY), overlay);

    // Dual-stroke lines for band edges
    final blackStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, topY), Offset(size.width, topY), blackStroke);
    canvas.drawLine(Offset(0, topY), Offset(size.width, topY), whiteStroke);
    canvas.drawLine(Offset(0, botY), Offset(size.width, botY), blackStroke);
    canvas.drawLine(Offset(0, botY), Offset(size.width, botY), whiteStroke);

    // Draw center circle dual-stroke
    const radius = 22.0;
    final blackCircle = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    final whiteCircle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(Offset(cx, cy), radius, blackCircle);
    canvas.drawCircle(Offset(cx, cy), radius, whiteCircle);

    // Thin center line for visual anchor
    final centerLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(12, cy), Offset(size.width - 12, cy), centerLine);
  }

  @override
  bool shouldRepaint(covariant _FocusPainter oldDelegate) {
    return oldDelegate.focusCenter != focusCenter ||
        oldDelegate.bandWidth != bandWidth;
  }
}
