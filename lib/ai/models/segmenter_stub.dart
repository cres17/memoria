import 'dart:typed_data';

import 'package:image/image.dart' as img;

class SegmentMask {
  final Float32List data;
  final int width;
  final int height;

  const SegmentMask(this.data, this.width, this.height);

  double at(int x, int y) => data[y * width + x];

  SegmentMask resize(int targetW, int targetH) => this;

  SegmentMask feather(int radius) => this;
}

class SelfieSegmenter {
  static Future<SelfieSegmenter> load(String modelPath) async =>
      SelfieSegmenter._();

  SelfieSegmenter._();

  SegmentMask segment(img.Image image) {
    throw UnsupportedError('Selfie segmentation is not supported on web.');
  }

  void dispose() {}
}

enum SemanticClass {
  background,
  hair,
  bodySkin,
  faceSkin,
  clothes,
  other,
}

class SemanticMasks {
  final Map<SemanticClass, SegmentMask> masks;
  final int width;
  final int height;

  const SemanticMasks(this.masks, this.width, this.height);

  SegmentMask operator [](SemanticClass c) =>
      masks[c] ?? SegmentMask(Float32List(width * height), width, height);
}

class MulticlassSegmenter {
  static Future<MulticlassSegmenter> load(String modelPath) async =>
      MulticlassSegmenter._();

  MulticlassSegmenter._();

  SemanticMasks segment(img.Image image) {
    throw UnsupportedError('Semantic segmentation is not supported on web.');
  }

  void dispose() {}
}
