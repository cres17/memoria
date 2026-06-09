import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CropGridMode {
  none,
  thirds,
  grid4x4,
  diagonals,
}

enum _CropHandle {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
  inside,
}

class CropOverlayWidget extends StatefulWidget {
  final Size imageSize; // Visual width/height of the image on screen
  final double cropLeft; // Normalized [0..1]
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double? aspectRatio; // Aspect ratio to lock (null = free)
  final CropGridMode gridMode;
  final Function(double left, double top, double right, double bottom)
      onCropChanged;
  final VoidCallback? onDragEnd;

  const CropOverlayWidget({
    super.key,
    required this.imageSize,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    this.aspectRatio,
    required this.gridMode,
    required this.onCropChanged,
    this.onDragEnd,
  });

  @override
  State<CropOverlayWidget> createState() => _CropOverlayWidgetState();
}

class _CropOverlayWidgetState extends State<CropOverlayWidget> {
  _CropHandle _activeHandle = _CropHandle.none;
  Offset _dragStartOffset = Offset.zero;

  // Normalized bounds at start of drag
  double _startLeft = 0.0;
  double _startTop = 0.0;
  double _startRight = 1.0;
  double _startBottom = 1.0;

  static const double _hitSlop =
      28.0; // Total hit area around a boundary is ~56px (> 44px)
  static const double _minSize = 44.0; // Minimum size of the crop box in pixels

  void _onPanStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(details.globalPosition);

    final W = widget.imageSize.width;
    final H = widget.imageSize.height;

    // Convert crop normalized coordinates to pixel coordinates
    final leftPx = widget.cropLeft * W;
    final topPx = widget.cropTop * H;
    final rightPx = widget.cropRight * W;
    final bottomPx = widget.cropBottom * H;

    _startLeft = widget.cropLeft;
    _startTop = widget.cropTop;
    _startRight = widget.cropRight;
    _startBottom = widget.cropBottom;

    _dragStartOffset = localPos;

    // Detect which handle was touched
    final x = localPos.dx;
    final y = localPos.dy;

    // 1. Corners
    if ((x - leftPx).abs() <= _hitSlop && (y - topPx).abs() <= _hitSlop) {
      _activeHandle = _CropHandle.topLeft;
    } else if ((x - rightPx).abs() <= _hitSlop &&
        (y - topPx).abs() <= _hitSlop) {
      _activeHandle = _CropHandle.topRight;
    } else if ((x - leftPx).abs() <= _hitSlop &&
        (y - bottomPx).abs() <= _hitSlop) {
      _activeHandle = _CropHandle.bottomLeft;
    } else if ((x - rightPx).abs() <= _hitSlop &&
        (y - bottomPx).abs() <= _hitSlop) {
      _activeHandle = _CropHandle.bottomRight;
    }
    // 2. Edges (only active in Free mode or if mapped to resize proportionally)
    else if ((y - topPx).abs() <= _hitSlop && x >= leftPx && x <= rightPx) {
      _activeHandle = _CropHandle.top;
    } else if ((y - bottomPx).abs() <= _hitSlop &&
        x >= leftPx &&
        x <= rightPx) {
      _activeHandle = _CropHandle.bottom;
    } else if ((x - leftPx).abs() <= _hitSlop && y >= topPx && y <= bottomPx) {
      _activeHandle = _CropHandle.left;
    } else if ((x - rightPx).abs() <= _hitSlop && y >= topPx && y <= bottomPx) {
      _activeHandle = _CropHandle.right;
    }
    // 3. Inside
    else if (x > leftPx && x < rightPx && y > topPx && y < bottomPx) {
      _activeHandle = _CropHandle.inside;
    } else {
      _activeHandle = _CropHandle.none;
    }

    if (_activeHandle != _CropHandle.none) {
      HapticFeedback.selectionClick();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == _CropHandle.none) return;

    final W = widget.imageSize.width;
    final H = widget.imageSize.height;
    if (W <= 0 || H <= 0) return;

    final currentPos = details.localPosition;
    final delta = currentPos - _dragStartOffset;

    // Start pixel coordinates
    final startLeftPx = _startLeft * W;
    final startTopPx = _startTop * H;
    final startRightPx = _startRight * W;
    final startBottomPx = _startBottom * H;

    double newLeftPx = startLeftPx;
    double newTopPx = startTopPx;
    double newRightPx = startRightPx;
    double newBottomPx = startBottomPx;

    final targetRatio = widget.aspectRatio;

    if (targetRatio != null && targetRatio > 0) {
      // ──────────────── Aspect Ratio Locked Drag ────────────────
      switch (_activeHandle) {
        case _CropHandle.topLeft:
          {
            final anchorX = startRightPx;
            final anchorY = startBottomPx;
            final targetX = startLeftPx + delta.dx;
            final newW = (anchorX - targetX).clamp(_minSize, anchorX);
            final newH = newW / targetRatio;
            newLeftPx = anchorX - newW;
            newTopPx = anchorY - newH;

            if (newTopPx < 0) {
              newTopPx = 0;
              final maxH = anchorY;
              final maxW = maxH * targetRatio;
              newLeftPx = anchorX - maxW;
            }
            if (newLeftPx < 0) {
              newLeftPx = 0;
              final maxW = anchorX;
              final maxH = maxW / targetRatio;
              newTopPx = anchorY - maxH;
            }
          }
          break;

        case _CropHandle.topRight:
          {
            final anchorX = startLeftPx;
            final anchorY = startBottomPx;
            final targetX = startRightPx + delta.dx;
            final newW = (targetX - anchorX).clamp(_minSize, W - anchorX);
            final newH = newW / targetRatio;
            newRightPx = anchorX + newW;
            newTopPx = anchorY - newH;

            if (newTopPx < 0) {
              newTopPx = 0;
              final maxH = anchorY;
              final maxW = maxH * targetRatio;
              newRightPx = anchorX + maxW;
            }
            if (newRightPx > W) {
              newRightPx = W;
              final maxW = W - anchorX;
              final maxH = maxW / targetRatio;
              newTopPx = anchorY - maxH;
            }
          }
          break;

        case _CropHandle.bottomLeft:
          {
            final anchorX = startRightPx;
            final anchorY = startTopPx;
            final targetX = startLeftPx + delta.dx;
            final newW = (anchorX - targetX).clamp(_minSize, anchorX);
            final newH = newW / targetRatio;
            newLeftPx = anchorX - newW;
            newBottomPx = anchorY + newH;

            if (newBottomPx > H) {
              newBottomPx = H;
              final maxH = H - anchorY;
              final maxW = maxH * targetRatio;
              newLeftPx = anchorX - maxW;
            }
            if (newLeftPx < 0) {
              newLeftPx = 0;
              final maxW = anchorX;
              final maxH = maxW / targetRatio;
              newBottomPx = anchorY + maxH;
            }
          }
          break;

        case _CropHandle.bottomRight:
          {
            final anchorX = startLeftPx;
            final anchorY = startTopPx;
            final targetX = startRightPx + delta.dx;
            final newW = (targetX - anchorX).clamp(_minSize, W - anchorX);
            final newH = newW / targetRatio;
            newRightPx = anchorX + newW;
            newBottomPx = anchorY + newH;

            if (newBottomPx > H) {
              newBottomPx = H;
              final maxH = H - anchorY;
              final maxW = maxH * targetRatio;
              newRightPx = anchorX + maxW;
            }
            if (newRightPx > W) {
              newRightPx = W;
              final maxW = W - anchorX;
              final maxH = maxW / targetRatio;
              newBottomPx = anchorY + maxH;
            }
          }
          break;

        case _CropHandle.top:
        case _CropHandle.bottom:
        case _CropHandle.left:
        case _CropHandle.right:
          // In locked ratio mode, dragging an edge scales the box uniformly from center or is treated as TL/BR drag.
          // For simplicity, lock edge handles in aspect mode, or scale from center:
          {
            // Simple approach: map edge to corner drags for consistent UX
            final scale = (1.0 + delta.dy / H).clamp(0.2, 2.0);
            final currentW = startRightPx - startLeftPx;
            final center = Offset((startLeftPx + startRightPx) / 2,
                (startTopPx + startBottomPx) / 2);

            final newW = (currentW * scale).clamp(_minSize, W);
            final newH = newW / targetRatio;

            newLeftPx = (center.dx - newW / 2).clamp(0.0, W - newW);
            newRightPx = newLeftPx + newW;
            newTopPx = (center.dy - newH / 2).clamp(0.0, H - newH);
            newBottomPx = newTopPx + newH;
          }
          break;

        case _CropHandle.inside:
          _panBox(delta.dx, delta.dy, startLeftPx, startTopPx, startRightPx,
              startBottomPx, W, H, (l, t, r, b) {
            newLeftPx = l;
            newTopPx = t;
            newRightPx = r;
            newBottomPx = b;
          });
          break;
        default:
          break;
      }
    } else {
      // ──────────────── Free Drag (Unconstrained) ────────────────
      switch (_activeHandle) {
        case _CropHandle.topLeft:
          newLeftPx =
              (startLeftPx + delta.dx).clamp(0.0, startRightPx - _minSize);
          newTopPx =
              (startTopPx + delta.dy).clamp(0.0, startBottomPx - _minSize);
          break;
        case _CropHandle.topRight:
          newRightPx =
              (startRightPx + delta.dx).clamp(startLeftPx + _minSize, W);
          newTopPx =
              (startTopPx + delta.dy).clamp(0.0, startBottomPx - _minSize);
          break;
        case _CropHandle.bottomLeft:
          newLeftPx =
              (startLeftPx + delta.dx).clamp(0.0, startRightPx - _minSize);
          newBottomPx =
              (startBottomPx + delta.dy).clamp(startTopPx + _minSize, H);
          break;
        case _CropHandle.bottomRight:
          newRightPx =
              (startRightPx + delta.dx).clamp(startLeftPx + _minSize, W);
          newBottomPx =
              (startBottomPx + delta.dy).clamp(startTopPx + _minSize, H);
          break;
        case _CropHandle.top:
          newTopPx =
              (startTopPx + delta.dy).clamp(0.0, startBottomPx - _minSize);
          break;
        case _CropHandle.bottom:
          newBottomPx =
              (startBottomPx + delta.dy).clamp(startTopPx + _minSize, H);
          break;
        case _CropHandle.left:
          newLeftPx =
              (startLeftPx + delta.dx).clamp(0.0, startRightPx - _minSize);
          break;
        case _CropHandle.right:
          newRightPx =
              (startRightPx + delta.dx).clamp(startLeftPx + _minSize, W);
          break;
        case _CropHandle.inside:
          _panBox(delta.dx, delta.dy, startLeftPx, startTopPx, startRightPx,
              startBottomPx, W, H, (l, t, r, b) {
            newLeftPx = l;
            newTopPx = t;
            newRightPx = r;
            newBottomPx = b;
          });
          break;
        default:
          break;
      }
    }

    // Call callback with normalized bounds
    widget.onCropChanged(
      (newLeftPx / W).clamp(0.0, 1.0),
      (newTopPx / H).clamp(0.0, 1.0),
      (newRightPx / W).clamp(0.0, 1.0),
      (newBottomPx / H).clamp(0.0, 1.0),
    );
  }

  void _panBox(
    double dx,
    double dy,
    double startL,
    double startT,
    double startR,
    double startB,
    double W,
    double H,
    Function(double l, double t, double r, double b) update,
  ) {
    final boxW = startR - startL;
    final boxH = startB - startT;

    double newL = startL + dx;
    double newT = startT + dy;

    if (newL < 0) newL = 0;
    if (newT < 0) newT = 0;
    if (newL + boxW > W) newL = W - boxW;
    if (newT + boxH > H) newT = H - boxH;

    update(newL, newT, newL + boxW, newT + boxH);
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = _CropHandle.none;
    if (widget.onDragEnd != null) {
      widget.onDragEnd!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: () {
        _activeHandle = _CropHandle.none;
        if (widget.onDragEnd != null) {
          widget.onDragEnd!();
        }
      },
      child: CustomPaint(
        size: widget.imageSize,
        painter: _CropPainter(
          left: widget.cropLeft,
          top: widget.cropTop,
          right: widget.cropRight,
          bottom: widget.cropBottom,
          gridMode: widget.gridMode,
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final double left;
  final double top;
  final double right;
  final double bottom;
  final CropGridMode gridMode;

  _CropPainter({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.gridMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    final leftPx = left * W;
    final topPx = top * H;
    final rightPx = right * W;
    final bottomPx = bottom * H;

    // 1. Draw outer dimmed mask
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, W, H))
      ..addRect(Rect.fromLTRB(leftPx, topPx, rightPx, bottomPx));
    outerPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(outerPath, maskPaint);

    // 2. Draw border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
        Rect.fromLTRB(leftPx, topPx, rightPx, bottomPx), borderPaint);

    // 3. Draw Grid Lines
    _drawGrid(canvas, leftPx, topPx, rightPx, bottomPx);

    // 4. Draw Thick Corner L-Handles and Edge Center Bars
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square;

    const handleLength = 18.0;

    // Corners
    // Top Left
    canvas.drawPath(
      Path()
        ..moveTo(leftPx, topPx + handleLength)
        ..lineTo(leftPx, topPx)
        ..lineTo(leftPx + handleLength, topPx),
      handlePaint,
    );
    // Top Right
    canvas.drawPath(
      Path()
        ..moveTo(rightPx - handleLength, topPx)
        ..lineTo(rightPx, topPx)
        ..lineTo(rightPx, topPx + handleLength),
      handlePaint,
    );
    // Bottom Left
    canvas.drawPath(
      Path()
        ..moveTo(leftPx, bottomPx - handleLength)
        ..lineTo(leftPx, bottomPx)
        ..lineTo(leftPx + handleLength, bottomPx),
      handlePaint,
    );
    // Bottom Right
    canvas.drawPath(
      Path()
        ..moveTo(rightPx - handleLength, bottomPx)
        ..lineTo(rightPx, bottomPx)
        ..lineTo(rightPx, bottomPx - handleLength),
      handlePaint,
    );

    // Edges
    final midX = (leftPx + rightPx) / 2;
    final midY = (topPx + bottomPx) / 2;

    // Top edge
    canvas.drawLine(Offset(midX - handleLength / 2, topPx),
        Offset(midX + handleLength / 2, topPx), handlePaint);
    // Bottom edge
    canvas.drawLine(Offset(midX - handleLength / 2, bottomPx),
        Offset(midX + handleLength / 2, bottomPx), handlePaint);
    // Left edge
    canvas.drawLine(Offset(leftPx, midY - handleLength / 2),
        Offset(leftPx, midY + handleLength / 2), handlePaint);
    // Right edge
    canvas.drawLine(Offset(rightPx, midY - handleLength / 2),
        Offset(rightPx, midY + handleLength / 2), handlePaint);
  }

  void _drawGrid(Canvas canvas, double l, double t, double r, double b) {
    if (gridMode == CropGridMode.none) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final w = r - l;
    final h = b - t;

    if (gridMode == CropGridMode.thirds) {
      // 2 horizontal and 2 vertical lines
      canvas.drawLine(Offset(l + w / 3, t), Offset(l + w / 3, b), gridPaint);
      canvas.drawLine(
          Offset(l + 2 * w / 3, t), Offset(l + 2 * w / 3, b), gridPaint);
      canvas.drawLine(Offset(l, t + h / 3), Offset(r, t + h / 3), gridPaint);
      canvas.drawLine(
          Offset(l, t + 2 * h / 3), Offset(r, t + 2 * h / 3), gridPaint);
    } else if (gridMode == CropGridMode.grid4x4) {
      // 3 horizontal and 3 vertical lines
      for (int i = 1; i <= 3; i++) {
        canvas.drawLine(
            Offset(l + i * w / 4, t), Offset(l + i * w / 4, b), gridPaint);
        canvas.drawLine(
            Offset(l, t + i * h / 4), Offset(r, t + i * h / 4), gridPaint);
      }
    } else if (gridMode == CropGridMode.diagonals) {
      // Corner to corner
      canvas.drawLine(Offset(l, t), Offset(r, b), gridPaint);
      canvas.drawLine(Offset(r, t), Offset(l, b), gridPaint);

      // Midpoints diagonals (X-like secondary patterns)
      final midX = (l + r) / 2;
      final midY = (t + b) / 2;
      canvas.drawLine(Offset(midX, t), Offset(r, midY), gridPaint);
      canvas.drawLine(Offset(r, midY), Offset(midX, b), gridPaint);
      canvas.drawLine(Offset(midX, b), Offset(l, midY), gridPaint);
      canvas.drawLine(Offset(l, midY), Offset(midX, t), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return oldDelegate.left != left ||
        oldDelegate.top != top ||
        oldDelegate.right != right ||
        oldDelegate.bottom != bottom ||
        oldDelegate.gridMode != gridMode;
  }
}
