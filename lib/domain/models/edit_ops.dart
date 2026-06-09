import 'adjust_params.dart';

class CropRect {
  final double x, y, width, height;
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};

  factory CropRect.fromJson(Map<String, dynamic> j) => CropRect(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

enum ExportFormat { jpeg, png }

class EditOps {
  final CropRect? cropRect;
  final double rotateAngle;   // degrees
  final String? presetId;
  final double intensity;     // 0.0 ~ 1.0
  final AdjustParams params;
  final int? outputWidth;
  final int? outputHeight;
  final ExportFormat format;
  final int quality;          // 1-100 for JPEG

  const EditOps({
    this.cropRect,
    this.rotateAngle = 0.0,
    this.presetId,
    this.intensity = 1.0,
    this.params = AdjustParams.zero,
    this.outputWidth,
    this.outputHeight,
    this.format = ExportFormat.jpeg,
    this.quality = 90,
  });

  EditOps copyWith({
    CropRect? cropRect,
    double? rotateAngle,
    String? presetId,
    double? intensity,
    AdjustParams? params,
    int? outputWidth,
    int? outputHeight,
    ExportFormat? format,
    int? quality,
  }) {
    return EditOps(
      cropRect:     cropRect     ?? this.cropRect,
      rotateAngle:  rotateAngle  ?? this.rotateAngle,
      presetId:     presetId     ?? this.presetId,
      intensity:    intensity    ?? this.intensity,
      params:       params       ?? this.params,
      outputWidth:  outputWidth  ?? this.outputWidth,
      outputHeight: outputHeight ?? this.outputHeight,
      format:       format       ?? this.format,
      quality:      quality      ?? this.quality,
    );
  }

  Map<String, dynamic> toJson() => {
    if (cropRect != null) 'crop_rect': cropRect!.toJson(),
    'rotate_angle':  rotateAngle,
    if (presetId != null) 'preset_id': presetId,
    'intensity':     intensity,
    'params':        params.toJson(),
    if (outputWidth  != null) 'output_width':  outputWidth,
    if (outputHeight != null) 'output_height': outputHeight,
    'format':        format.name,
    'quality':       quality,
  };
}
