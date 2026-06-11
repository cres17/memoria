import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../engine/local_adjust.dart';

class BrushOverlayWidget extends StatefulWidget {
  final Size imageSize;
  final List<DodgeBurnStroke> strokes;
  final double brushSize;
  final double hardness;
  final TransformationController transformationController;
  final ValueChanged<DodgeBurnStroke> onStroke;
  final VoidCallback? onStrokeEnd;

  const BrushOverlayWidget({
    super.key,
    required this.imageSize,
    required this.strokes,
    required this.brushSize,
    required this.hardness,
    required this.transformationController,
    required this.onStroke,
    this.onStrokeEnd,
  });

  @override
  State<BrushOverlayWidget> createState() => _BrushOverlayWidgetState();
}

class _BrushOverlayWidgetState extends State<BrushOverlayWidget> {
  Offset? _lastLocal;

  void _addStroke(Offset local, Size size) {
    final scene = widget.transformationController.toScene(local);
    final rect = _containRect(size, widget.imageSize);
    if (!rect.contains(scene)) return;
    final x = ((scene.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final y = ((scene.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    final radius = (widget.brushSize / 2.0 / math.min(rect.width, rect.height))
        .clamp(0.001, 0.5);
    widget.onStroke(DodgeBurnStroke(x: x, y: y, radius: radius, strength: 1.0, isDodge: true));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _lastLocal = details.localPosition;
            _addStroke(details.localPosition, size);
          },
          onPanUpdate: (details) {
            final last = _lastLocal;
            final current = details.localPosition;
            if (last == null) {
              _addStroke(current, size);
            } else {
              final distance = (current - last).distance;
              final step = math.max(6.0, widget.brushSize / 4.0);
              final count = math.max(1, (distance / step).ceil());
              for (var i = 1; i <= count; i++) {
                _addStroke(Offset.lerp(last, current, i / count)!, size);
              }
            }
            _lastLocal = current;
          },
          onPanEnd: (_) {
            _lastLocal = null;
            widget.onStrokeEnd?.call();
          },
          onPanCancel: () {
            _lastLocal = null;
            widget.onStrokeEnd?.call();
          },
          child: AnimatedBuilder(
            animation: widget.transformationController,
            builder: (context, _) => CustomPaint(
              painter: _BrushOverlayPainter(
                imageSize: widget.imageSize,
                strokes: widget.strokes,
                brushSize: widget.brushSize,
                hardness: widget.hardness,
                transform: widget.transformationController.value,
              ),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _BrushOverlayPainter extends CustomPainter {
  final Size imageSize;
  final List<DodgeBurnStroke> strokes;
  final double brushSize;
  final double hardness;
  final Matrix4 transform;

  const _BrushOverlayPainter({
    required this.imageSize,
    required this.strokes,
    required this.brushSize,
    required this.hardness,
    required this.transform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final rect = _containRect(size, imageSize);
    canvas.save();
    canvas.transform(transform.storage);

    final maskPaint = Paint()
      ..color = const Color(0xFFFF4F7A).withOpacity(0.24)
      ..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..color = const Color(0xFFFFD5DD).withOpacity(0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final minSide = math.min(rect.width, rect.height);

    for (final stroke in strokes) {
      final center = Offset(
        rect.left + stroke.x * rect.width,
        rect.top + stroke.y * rect.height,
      );
      final radius = stroke.radius * minSide;
      canvas.drawCircle(center, radius, maskPaint);
      if (hardness > 0.9) {
        canvas.drawCircle(center, radius, edgePaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrushOverlayPainter oldDelegate) =>
      oldDelegate.imageSize != imageSize ||
      oldDelegate.strokes != strokes ||
      oldDelegate.brushSize != brushSize ||
      oldDelegate.hardness != hardness ||
      oldDelegate.transform != transform;
}

Rect _containRect(Size bounds, Size imageSize) {
  if (bounds.width <= 0 ||
      bounds.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return Offset.zero & Size.zero;
  }
  final scale = math.min(
    bounds.width / imageSize.width,
    bounds.height / imageSize.height,
  );
  final width = imageSize.width * scale;
  final height = imageSize.height * scale;
  return Rect.fromLTWH(
    (bounds.width - width) / 2,
    (bounds.height - height) / 2,
    width,
    height,
  );
}
