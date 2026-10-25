import 'package:image/image.dart' as img;

import 'fast_blur.dart';

/// One operation in a shared CPU/GPU recipe. Input stays owned by Dart until
/// a complete native result has been validated; failure uses the same input.
class ImageOperation {
  final String kind;
  final img.Image input;
  final Map<String, num> parameters;
  final img.Image Function() _cpu;
  img.Image? result;

  ImageOperation.blur(this.input, int radius)
      : kind = 'blur',
        parameters = {'radius': radius},
        _cpu = (() => fastGaussianBlur(input, radius: radius));

  ImageOperation.noise(this.input, double luma, double chroma, double detail,
      img.Image Function() cpu)
      : kind = 'noise',
        parameters = {'luma': luma, 'chroma': chroma, 'detail': detail},
        _cpu = cpu;

  void resolveCpu() => result = _cpu();
}

class ImagePipelineResult {
  late img.Image image;
}
