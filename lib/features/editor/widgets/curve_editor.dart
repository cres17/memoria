import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../domain/models/curve_data.dart';

class CurveEditor extends StatefulWidget {
  final CurveData curve;
  final ValueChanged<CurveData> onChanged;
  final ValueChanged<CurveData>? onChangeEnd;

  const CurveEditor({
    super.key,
    required this.curve,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  static const double _canvasSize = 240.0;
  static const double _hitRadius  = 32.0;

  int? _draggingIndex;
  late List<CurvePoint> _points;

  @override
  void initState() {
    super.initState();
    _points = [...widget.curve.points];
  }

  @override
  void didUpdateWidget(CurveEditor old) {
    super.didUpdateWidget(old);
    if (old.curve != widget.curve) {
      setState(() => _points = [...widget.curve.points]);
    }
  }

  Offset _toCanvas(CurvePoint p) =>
      Offset(p.x * _canvasSize, (1.0 - p.y) * _canvasSize);

  CurvePoint _fromCanvas(Offset o) => CurvePoint(
    (o.dx / _canvasSize).clamp(0.0, 1.0),
    (1.0 - o.dy / _canvasSize).clamp(0.0, 1.0),
  );

  int? _hitTest(Offset pos) {
    for (int i = 0; i < _points.length; i++) {
      if ((_toCanvas(_points[i]) - pos).distance < _hitRadius) return i;
    }
    return null;
  }

  void _onPanStart(DragStartDetails d) {
    final hit = _hitTest(d.localPosition);
    if (hit != null) {
      hapticLight();
      setState(() => _draggingIndex = hit);
    } else {
      // 새 포인트 추가 (가장자리 포인트는 제외)
      final p = _fromCanvas(d.localPosition);
      if (p.x > 0.02 && p.x < 0.98) {
        hapticLight();
        final newPoints = [..._points, p]
          ..sort((a, b) => a.x.compareTo(b.x));
        setState(() {
          _points = newPoints;
          _draggingIndex = newPoints.indexOf(p);
        });
        _notify();
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_draggingIndex == null) return;
    final idx = _draggingIndex!;
    final raw = _fromCanvas(d.localPosition);

    // 가장자리 포인트는 X 고정
    double newX = raw.x;
    if (idx == 0) newX = 0.0;
    if (idx == _points.length - 1) newX = 1.0;

    // 인접 포인트 사이로 X 제한
    final minX = idx > 0 ? _points[idx - 1].x + 0.01 : 0.0;
    final maxX = idx < _points.length - 1 ? _points[idx + 1].x - 0.01 : 1.0;

    setState(() {
      _points[idx] = CurvePoint(
        newX.clamp(minX, maxX),
        raw.y.clamp(0.0, 1.0),
      );
    });
    _notify();
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _draggingIndex = null);
    if (widget.onChangeEnd != null) {
      widget.onChangeEnd!(widget.curve.copyWith(points: [..._points]));
    }
  }

  void _onDoubleTap(TapDownDetails d) {
    final hit = _hitTest(d.localPosition);
    // 가장자리 2개 포인트는 삭제 불가
    if (hit != null && hit > 0 && hit < _points.length - 1) {
      hapticMedium();
      setState(() => _points.removeAt(hit));
      _notify();
      if (widget.onChangeEnd != null) {
        widget.onChangeEnd!(widget.curve.copyWith(points: [..._points]));
      }
    }
  }

  void _notify() {
    widget.onChanged(widget.curve.copyWith(points: [..._points]));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 커브 캔버스
        Container(
          width: _canvasSize,
          height: _canvasSize,
          decoration: BoxDecoration(
            color: AppColors.oceanNavy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: GestureDetector(
            onPanStart:      _onPanStart,
            onPanUpdate:     _onPanUpdate,
            onPanEnd:        _onPanEnd,
            onDoubleTapDown: _onDoubleTap,
            child: CustomPaint(
              size: const Size(_canvasSize, _canvasSize),
              painter: _CurvePainter(
                points:        _points,
                channel:       widget.curve.channel,
                draggingIndex: _draggingIndex,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 프리셋 버튼 행
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: CurvePresets.presetNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final name = CurvePresets.presetNames[i];
              String displayName = name;
              switch (name) {
                case 'Neutral': displayName = '기본'; break;
                case 'Brighten': displayName = '밝게'; break;
                case 'Darken': displayName = '어둡게'; break;
                case 'Faded': displayName = '바랜 느낌'; break;
                case 'Soft Contrast': displayName = '부드러운 대비'; break;
                case 'Hard Contrast': displayName = '강한 대비'; break;
              }
              return GestureDetector(
                onTap: () {
                  hapticLight();
                  final newCurve = CurvePresets.fromPresetName(name, widget.curve.channel);
                  setState(() => _points = [...newCurve.points]);
                  widget.onChanged(newCurve);
                  if (widget.onChangeEnd != null) {
                    widget.onChangeEnd!(newCurve);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.oceanMid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.oceanFoam.withOpacity(0.2)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Custom Painter ────────────────────────────────────────

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> points;
  final CurveChannel channel;
  final int? draggingIndex;

  const _CurvePainter({
    required this.points,
    required this.channel,
    required this.draggingIndex,
  });

  Color get _curveColor {
    switch (channel) {
      case CurveChannel.red:       return const Color(0xFFFF6B6B);
      case CurveChannel.green:     return const Color(0xFF6BFF8E);
      case CurveChannel.blue:      return const Color(0xFF6BB5FF);
      case CurveChannel.rgb:       return AppColors.cloudWhite;
      case CurveChannel.luminance: return AppColors.oceanFoam;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 0.0;
    final W = size.width  - pad * 2;
    final H = size.height - pad * 2;

    // 격자
    final gridPaint = Paint()
      ..color = AppColors.oceanFoam.withOpacity(0.08)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(W * i / 4, 0), Offset(W * i / 4, H), gridPaint);
      canvas.drawLine(Offset(0, H * i / 4), Offset(W, H * i / 4), gridPaint);
    }

    // 대각선 기준선
    canvas.drawLine(
      Offset(0, H),
      Offset(W, 0),
      gridPaint..color = AppColors.oceanFoam.withOpacity(0.18),
    );

    if (points.isEmpty) return;

    final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));

    Offset toC(CurvePoint p) => Offset(p.x * W, (1 - p.y) * H);

    // 커브 경로 (Catmull-Rom spline 근사)
    final curvePaint = Paint()
      ..color = _curveColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 200;
    final lut = CurveData(points: sorted, channel: channel).toLut();

    path.moveTo(0, (1 - lut[0] / 255.0) * H);
    for (int i = 1; i <= steps; i++) {
      final t   = i / steps;
      final idx = (t * 255).round().clamp(0, 255);
      path.lineTo(t * W, (1 - lut[idx] / 255.0) * H);
    }
    canvas.drawPath(path, curvePaint);

    // 컨트롤 포인트
    for (int i = 0; i < sorted.length; i++) {
      final isDragging = i == draggingIndex;
      final center     = toC(sorted[i]);
      final fillPaint  = Paint()
        ..color = isDragging ? _curveColor : AppColors.cloudWhite
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = _curveColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, isDragging ? 8.0 : 6.0, fillPaint);
      canvas.drawCircle(center, isDragging ? 8.0 : 6.0, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.draggingIndex != draggingIndex;
}

// ── 채널 탭 + 커브 에디터 통합 위젯 ─────────────────────

class CurveEditorPanel extends StatefulWidget {
  final Map<CurveChannel, CurveData> curves;
  final void Function(CurveChannel channel, CurveData data) onChanged;
  final void Function(CurveChannel channel, CurveData data)? onChangeEnd;

  const CurveEditorPanel({
    super.key,
    required this.curves,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<CurveEditorPanel> createState() => _CurveEditorPanelState();
}

class _CurveEditorPanelState extends State<CurveEditorPanel> {
  CurveChannel _activeChannel = CurveChannel.luminance;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 채널 탭
        SizedBox(
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: CurveChannel.values.map((ch) {
                    final selected = ch == _activeChannel;
                    final label = _channelLabel(ch);
                    return GestureDetector(
                      onTap: () {
                        hapticLight();
                        setState(() => _activeChannel = ch);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: selected ? _channelColor(ch) : AppColors.oceanNavy,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.replay_rounded, color: AppColors.textOnDarkSub),
                onPressed: () {
                  hapticLight();
                  final cleanCurve = CurveData.linear(_activeChannel);
                  widget.onChanged(_activeChannel, cleanCurve);
                  if (widget.onChangeEnd != null) {
                    widget.onChangeEnd!(_activeChannel, cleanCurve);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 현재 채널 커브 에디터
        CurveEditor(
          curve: widget.curves[_activeChannel] ??
              CurveData.linear(_activeChannel),
          onChanged: (data) => widget.onChanged(_activeChannel, data),
          onChangeEnd: widget.onChangeEnd != null
              ? (data) => widget.onChangeEnd!(_activeChannel, data)
              : null,
        ),
      ],
    );
  }

  String _channelLabel(CurveChannel ch) {
    switch (ch) {
      case CurveChannel.luminance:
        return 'L';
      case CurveChannel.rgb:
        return 'RGB';
      case CurveChannel.red:
        return 'R';
      case CurveChannel.green:
        return 'G';
      case CurveChannel.blue:
        return 'B';
    }
  }

  Color _channelColor(CurveChannel ch) {
    switch (ch) {
      case CurveChannel.red:       return const Color(0xFFD94F4F);
      case CurveChannel.green:     return const Color(0xFF3D9B5A);
      case CurveChannel.blue:      return const Color(0xFF3A72C8);
      case CurveChannel.rgb:       return AppColors.textOnDarkSub;
      case CurveChannel.luminance: return AppColors.oceanTeal;
    }
  }
}
