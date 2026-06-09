import 'dart:typed_data';

class LutPredictor {
  static Future<LutPredictor> get instance async => LutPredictor._();

  LutPredictor._();

  static Future<LutPredictor> fromPath(String modelPath) async =>
      LutPredictor._();

  Future<Float32List> predict(String styleImagePath) {
    throw UnsupportedError('AI color transfer is not supported on web.');
  }

  void dispose() {}
}
