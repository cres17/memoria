import 'dart:typed_data';

import 'package:image/image.dart' as img;

class DepthMap {
  final Float32List data;
  final int width;
  final int height;

  const DepthMap(this.data, this.width, this.height);

  double at(int x, int y) => data[y * width + x];

  DepthMap resize(int targetW, int targetH) => this;

  DepthMap smooth(int radius) => this;
}

class DepthEstimator {
  static Future<DepthEstimator> load(String modelPath) async =>
      DepthEstimator._();

  DepthEstimator._();

  DepthMap estimate(img.Image image) {
    throw UnsupportedError('Depth estimation is not supported on web.');
  }

  void dispose() {}
}
