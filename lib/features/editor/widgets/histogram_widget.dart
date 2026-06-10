import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../engine/histogram_engine.dart';

enum HistogramChannel { luminance, red, green, blue, rgb }

/// 56dp-tall histogram overlay with per-channel toggle.
/// Pass [data] null to show a loading/empty state.
class HistogramWidget extends StatefulWidget {
  final HistogramData? data;

  const HistogramWidget({super.key, required this.data});

  @override
  State<HistogramWidget> createState() => _HistogramWidgetState();
}

class _HistogramWidgetState extends State<HistogramWidget> {
  HistogramChannel _channel = HistogramChannel.luminance;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Channel toggle chips (compact)
          SizedBox(
            height: 20,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _chip('L', HistogramChannel.luminance, Colors.white70),
                _chip('RGB', HistogramChannel.rgb, Colors.white70),
                _chip('R', HistogramChannel.red, Colors.redAccent),
                _chip('G', HistogramChannel.green, Colors.greenAccent),
                _chip('B', HistogramChannel.blue, Colors.lightBlueAccent),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Histogram bars
          Expanded(
            child: widget.data == null
                ? const SizedBox()
                : CustomPaint(
                    painter: _HistogramPainter(
                      data: widget.data!,
                      channel: _channel,
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, HistogramChannel ch, Color color) {
    final selected = _channel == ch;
    return GestureDetector(
      onTap: () => setState(() => _channel = ch),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: selected ? color : color.withOpacity(0.5),
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final HistogramData data;
  final HistogramChannel channel;

  const _HistogramPainter({required this.data, required this.channel});

  @override
  void paint(Canvas canvas, Size size) {
    final peak = data.peak;
    if (peak == 0) return;

    final w = size.width;
    final h = size.height;
    final barW = w / 256;

    void drawBars(Uint32List bins, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final path = Path();
      for (int i = 0; i < 256; i++) {
        final barH = bins[i] / peak * h;
        final x = i * barW;
        path.addRect(Rect.fromLTWH(x, h - barH, barW + 0.5, barH));
      }
      canvas.drawPath(path, paint);
    }

    switch (channel) {
      case HistogramChannel.luminance:
        drawBars(data.luminance, Colors.white.withOpacity(0.7));
      case HistogramChannel.red:
        drawBars(data.r, Colors.red.withOpacity(0.7));
      case HistogramChannel.green:
        drawBars(data.g, Colors.green.withOpacity(0.7));
      case HistogramChannel.blue:
        drawBars(data.b, Colors.blue.withOpacity(0.7));
      case HistogramChannel.rgb:
        drawBars(data.r, Colors.red.withOpacity(0.5));
        drawBars(data.g, Colors.green.withOpacity(0.5));
        drawBars(data.b, Colors.blue.withOpacity(0.5));
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.data != data || old.channel != channel;
}
