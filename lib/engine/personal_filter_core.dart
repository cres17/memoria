import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/adjust_params.dart';
import '../domain/models/filter_recipe.dart';
import 'color_utils.dart';
import 'custom_lut_core.dart';

typedef PersonalFilterProgressCallback = void Function(
    String stage, double progress);

/// Fits a personalized filter from a single before/after pair.
///
/// The output matches the app's existing custom-filter contract:
/// - lut.bin: safe 65^3 float16 LUT
/// - recipe.json: portable render metadata
/// - fit_report.json: compact diagnostics with no source paths
Future<Map<String, dynamic>> generateLutFromBeforeAfterPair(
  String beforePath,
  String afterPath, {
  String? basePath,
  PersonalFilterProgressCallback? onProgress,
  int lutDim = customLutDim,
  int residualDim = 17,
  int sampleLimitPerPair = 50000,
  double ridge = 0.01,
  int smoothPasses = 2,
  double residualClip = 0.35,
}) async {
  final id = const Uuid().v4();
  final base = basePath != null
      ? Directory(basePath)
      : await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/filters/$id')..createSync(recursive: true);

  onProgress?.call('pair_loading', 0.10);
  final before = _decodeImage(beforePath);
  final afterRaw = _decodeImage(afterPath);
  final after = before.width == afterRaw.width && before.height == afterRaw.height
      ? afterRaw
      : img.copyResize(
          afterRaw,
          width: before.width,
          height: before.height,
          interpolation: img.Interpolation.linear,
        );

  onProgress?.call('pair_analyze', 0.22);
  final samples = _collectSamples(
    before: before,
    after: after,
    sampleLimitPerPair: sampleLimitPerPair,
  );

  onProgress?.call('global_fit', 0.38);
  final affine = _fitAffine(
    samples.x,
    samples.y,
    samples.weights,
    ridge: ridge,
  );
  final affinePred = _predictAffine(samples.x, affine);
  final residual = _subtract(samples.y, affinePred);

  onProgress?.call('residual_fit', 0.58);
  final residualFit = _fitResidualGrid(
    samples.x,
    residual,
    samples.weights,
    residualDim: residualDim,
    smoothPasses: smoothPasses,
    residualClip: residualClip,
  );

  onProgress?.call('lut_encode', 0.74);
  final lut = _buildLut(affine.matrix, affine.bias, residualFit, lutDim);
  final constrained = constrainCustomLut(
    _encodeLut(lut).buffer.asUint8List(),
    dim: lutDim,
  );
  final constrainedLut = _decodeLut(constrained.bytes);
  final fitMetrics = _evaluateFit(samples.x, samples.y, affine, constrainedLut);

  onProgress?.call('thumbnail', 0.90);
  final thumb = img.copyResizeCropSquare(after, size: 256);
  final lutPath = '${dir.path}/lut.bin';
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(lutPath).writeAsBytesSync(constrained.bytes);
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 88));

  final recipe = FilterRecipe(
    lutDimension: lutDim,
    engineVersion: 'personal_filter_fit_v1',
    generatorType: 'personalized_pair_fit',
    lutStrength: constrained.appliedStrength,
    referenceCount: 1,
    safetyMetrics: constrained.report.toJson(),
    fallbackReason: constrained.fallbackReason,
    modelId: 'affine_plus_residual_lut',
    modelVersion: 'v1',
  ).toJson();

  final report = <String, dynamic>{
    'fitMode': 'paired_before_after',
    'pairCount': 1,
    'sampleCount': samples.count,
    'beforeSize': [before.width, before.height],
    'afterSize': [after.width, after.height],
    'affineMatrix': affine.matrix,
    'affineBias': affine.bias,
    'ridge': ridge,
    'smoothPasses': smoothPasses,
    'residualClip': residualClip,
    'residualDim': residualDim,
    'lutDim': lutDim,
    'coverage': residualFit.coverage,
    'meanSamplesPerCell': residualFit.meanSamplesPerCell,
    'maxSamplesPerCell': residualFit.maxSamplesPerCell,
    'fitMetrics': fitMetrics,
    'safetyMetrics': constrained.report.toJson(),
    'appliedStrength': constrained.appliedStrength,
    'fallbackReason': constrained.fallbackReason,
  };

  File('${dir.path}/recipe.json').writeAsStringSync(_prettyJson(recipe));
  File('${dir.path}/fit_report.json').writeAsStringSync(_prettyJson(report));

  onProgress?.call('saving', 0.97);
  return {
    'presetId': id,
    'lutPath': lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': AdjustParams.zero.toJson(),
    'generatorType': 'personalized_pair_fit',
    'lutStrength': constrained.appliedStrength,
    'safetyMetrics': constrained.report.toJson(),
    'fallbackReason': constrained.fallbackReason,
    'fitReport': report,
    'filterRecipe': recipe,
  };
}

String _prettyJson(Map<String, dynamic> value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

img.Image _decodeImage(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Failed to decode image: $path');
  }
  return img.bakeOrientation(decoded);
}

class _SampleBatch {
  final Float32List x;
  final Float32List y;
  final Float32List weights;
  final int count;

  const _SampleBatch({
    required this.x,
    required this.y,
    required this.weights,
    required this.count,
  });
}

_SampleBatch _collectSamples({
  required img.Image before,
  required img.Image after,
  required int sampleLimitPerPair,
}) {
  final total = before.width * before.height;
  final take = math.min(total, sampleLimitPerPair);
  final indices = List<int>.generate(total, (i) => i);
  if (take < total) {
    indices.shuffle(math.Random(20260721));
  }

  final xs = <double>[];
  final ys = <double>[];
  final ws = <double>[];

  for (var i = 0; i < take; i++) {
    final index = indices[i];
    final x = index % before.width;
    final y = index ~/ before.width;
    final beforePixel = before.getPixel(x, y);
    final afterPixel = after.getPixel(x, y);

    final br = beforePixel.rNormalized.toDouble();
    final bg = beforePixel.gNormalized.toDouble();
    final bb = beforePixel.bNormalized.toDouble();
    final ar = afterPixel.rNormalized.toDouble();
    final ag = afterPixel.gNormalized.toDouble();
    final ab = afterPixel.bNormalized.toDouble();
    final chroma = math.max(br, math.max(bg, bb)) - math.min(br, math.min(bg, bb));
    final weight = 0.65 + 0.35 * chroma;

    xs.addAll([br, bg, bb]);
    ys.addAll([ar, ag, ab]);
    ws.add(weight);
  }

  return _SampleBatch(
    x: Float32List.fromList(xs),
    y: Float32List.fromList(ys),
    weights: Float32List.fromList(ws),
    count: take,
  );
}

class _AffineFit {
  final List<List<double>> matrix;
  final List<double> bias;

  const _AffineFit({required this.matrix, required this.bias});
}

_AffineFit _fitAffine(
  Float32List x,
  Float32List y,
  Float32List weights, {
  required double ridge,
}) {
  final sampleCount = x.length ~/ 3;
  final gram = List.generate(4, (_) => List<double>.filled(4, 0.0));
  final rhs = List.generate(4, (_) => List<double>.filled(3, 0.0));

  for (var i = 0; i < sampleCount; i++) {
    final xi = i * 3;
    final r = x[xi];
    final g = x[xi + 1];
    final b = x[xi + 2];
    final d = [r, g, b, 1.0];
    final w = weights[i];
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        gram[row][col] += w * d[row] * d[col];
      }
      rhs[row][0] += w * d[row] * y[xi];
      rhs[row][1] += w * d[row] * y[xi + 1];
      rhs[row][2] += w * d[row] * y[xi + 2];
    }
  }

  for (var i = 0; i < 4; i++) {
    gram[i][i] += i == 3 ? ridge * 0.1 : ridge;
  }

  final theta = _solveAugmented4x7(gram, rhs);
  final matrix = List.generate(3, (_) => List<double>.filled(3, 0.0));
  for (var channel = 0; channel < 3; channel++) {
    matrix[channel][0] = theta[0][channel];
    matrix[channel][1] = theta[1][channel];
    matrix[channel][2] = theta[2][channel];
  }
  return _AffineFit(
    matrix: matrix,
    bias: [theta[3][0], theta[3][1], theta[3][2]],
  );
}

List<List<double>> _solveAugmented4x7(
  List<List<double>> gram,
  List<List<double>> rhs,
) {
  final aug = List.generate(4, (row) {
    return <double>[
      ...gram[row],
      rhs[row][0],
      rhs[row][1],
      rhs[row][2],
    ];
  });

  for (var col = 0; col < 4; col++) {
    var pivot = col;
    for (var row = col + 1; row < 4; row++) {
      if (aug[row][col].abs() > aug[pivot][col].abs()) {
        pivot = row;
      }
    }
    if (pivot != col) {
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;
    }

    final pivotValue = aug[col][col].abs() < 1e-12 ? 1e-12 : aug[col][col];
    for (var j = col; j < 7; j++) {
      aug[col][j] /= pivotValue;
    }
    for (var row = 0; row < 4; row++) {
      if (row == col) continue;
      final factor = aug[row][col];
      if (factor == 0.0) continue;
      for (var j = col; j < 7; j++) {
        aug[row][j] -= factor * aug[col][j];
      }
    }
  }

  return List.generate(4, (row) => aug[row].sublist(4, 7));
}

Float32List _predictAffine(Float32List x, _AffineFit fit) {
  final sampleCount = x.length ~/ 3;
  final out = Float32List(sampleCount * 3);
  for (var i = 0; i < sampleCount; i++) {
    final xi = i * 3;
    final r = x[xi];
    final g = x[xi + 1];
    final b = x[xi + 2];
    out[xi] = r * fit.matrix[0][0] +
        g * fit.matrix[0][1] +
        b * fit.matrix[0][2] +
        fit.bias[0];
    out[xi + 1] = r * fit.matrix[1][0] +
        g * fit.matrix[1][1] +
        b * fit.matrix[1][2] +
        fit.bias[1];
    out[xi + 2] = r * fit.matrix[2][0] +
        g * fit.matrix[2][1] +
        b * fit.matrix[2][2] +
        fit.bias[2];
  }
  return out;
}

Float32List _subtract(Float32List a, Float32List b) {
  final out = Float32List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] - b[i];
  }
  return out;
}

class _ResidualGridFit {
  final Float32List values;
  final int dim;
  final double coverage;
  final double meanSamplesPerCell;
  final double maxSamplesPerCell;

  const _ResidualGridFit({
    required this.values,
    required this.dim,
    required this.coverage,
    required this.meanSamplesPerCell,
    required this.maxSamplesPerCell,
  });
}

_ResidualGridFit _fitResidualGrid(
  Float32List x,
  Float32List residual,
  Float32List weights, {
  required int residualDim,
  required int smoothPasses,
  required double residualClip,
}) {
  final cellCount = residualDim * residualDim * residualDim;
  var sumGrid = Float64List(cellCount * 3);
  var weightGrid = Float64List(cellCount);

  final sampleCount = x.length ~/ 3;
  for (var i = 0; i < sampleCount; i++) {
    final xi = i * 3;
    final r = x[xi];
    final g = x[xi + 1];
    final b = x[xi + 2];
    final scaled = [
      b * (residualDim - 1),
      g * (residualDim - 1),
      r * (residualDim - 1),
    ];
    final base = scaled.map((v) => v.floor()).toList();
    final frac = [
      scaled[0] - base[0],
      scaled[1] - base[1],
      scaled[2] - base[2],
    ];
    final upper = [
      math.min(base[0] + 1, residualDim - 1),
      math.min(base[1] + 1, residualDim - 1),
      math.min(base[2] + 1, residualDim - 1),
    ];
    final sampleWeight = weights[i];

    for (final db in [0, 1]) {
      final ib = db == 1 ? upper[0] : base[0];
      final wb = db == 1 ? frac[0] : 1.0 - frac[0];
      for (final dg in [0, 1]) {
        final ig = dg == 1 ? upper[1] : base[1];
        final wg = dg == 1 ? frac[1] : 1.0 - frac[1];
        for (final dr in [0, 1]) {
          final ir = dr == 1 ? upper[2] : base[2];
          final wr = dr == 1 ? frac[2] : 1.0 - frac[2];
          final cornerWeight = sampleWeight * wb * wg * wr;
          final cell = _cellIndex(residualDim, ib, ig, ir);
          weightGrid[cell] += cornerWeight;
          final offset = cell * 3;
          sumGrid[offset] += residual[xi] * cornerWeight;
          sumGrid[offset + 1] += residual[xi + 1] * cornerWeight;
          sumGrid[offset + 2] += residual[xi + 2] * cornerWeight;
        }
      }
    }
  }

  for (var pass = 0; pass < smoothPasses; pass++) {
    for (var axis = 0; axis < 3; axis++) {
      sumGrid = _blurVectorGrid(sumGrid, residualDim, axis);
      weightGrid = _blurScalarGrid(weightGrid, residualDim, axis);
    }
  }

  final out = Float32List(cellCount * 3);
  for (var cell = 0; cell < cellCount; cell++) {
    final weight = math.max(weightGrid[cell], 1e-8);
    final offset = cell * 3;
    out[offset] = (sumGrid[offset] / weight).clamp(-residualClip, residualClip).toDouble();
    out[offset + 1] =
        (sumGrid[offset + 1] / weight).clamp(-residualClip, residualClip).toDouble();
    out[offset + 2] =
        (sumGrid[offset + 2] / weight).clamp(-residualClip, residualClip).toDouble();
  }

  final coverage = weightGrid.where((value) => value > 0).length / cellCount;
  final meanSamplesPerCell =
      weightGrid.fold<double>(0.0, (sum, value) => sum + value) / cellCount;
  final maxSamplesPerCell =
      weightGrid.fold<double>(0.0, (current, value) => math.max(current, value));

  return _ResidualGridFit(
    values: out,
    dim: residualDim,
    coverage: coverage,
    meanSamplesPerCell: meanSamplesPerCell,
    maxSamplesPerCell: maxSamplesPerCell,
  );
}

int _cellIndex(int dim, int b, int g, int r) => (b * dim + g) * dim + r;

Float64List _blurScalarGrid(Float64List input, int dim, int axis) {
  final out = Float64List(input.length);
  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        final current = _gridScalarAt(input, dim, b, g, r);
        final prev = _gridScalarAt(
          input,
          dim,
          axis == 0 ? math.max(b - 1, 0) : b,
          axis == 1 ? math.max(g - 1, 0) : g,
          axis == 2 ? math.max(r - 1, 0) : r,
        );
        final next = _gridScalarAt(
          input,
          dim,
          axis == 0 ? math.min(b + 1, dim - 1) : b,
          axis == 1 ? math.min(g + 1, dim - 1) : g,
          axis == 2 ? math.min(r + 1, dim - 1) : r,
        );
        out[_cellIndex(dim, b, g, r)] = (prev + 2.0 * current + next) / 4.0;
      }
    }
  }
  return out;
}

Float64List _blurVectorGrid(Float64List input, int dim, int axis) {
  final out = Float64List(input.length);
  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        final cell = _cellIndex(dim, b, g, r);
        final prev = _cellVectorAt(
          input,
          dim,
          axis == 0 ? math.max(b - 1, 0) : b,
          axis == 1 ? math.max(g - 1, 0) : g,
          axis == 2 ? math.max(r - 1, 0) : r,
        );
        final current = _cellVectorAt(input, dim, b, g, r);
        final next = _cellVectorAt(
          input,
          dim,
          axis == 0 ? math.min(b + 1, dim - 1) : b,
          axis == 1 ? math.min(g + 1, dim - 1) : g,
          axis == 2 ? math.min(r + 1, dim - 1) : r,
        );
        final offset = cell * 3;
        for (var channel = 0; channel < 3; channel++) {
          out[offset + channel] =
              (prev[channel] + 2.0 * current[channel] + next[channel]) / 4.0;
        }
      }
    }
  }
  return out;
}

double _gridScalarAt(Float64List grid, int dim, int b, int g, int r) =>
    grid[_cellIndex(dim, b, g, r)];

List<double> _cellVectorAt(Float64List grid, int dim, int b, int g, int r) {
  final offset = _cellIndex(dim, b, g, r) * 3;
  return [grid[offset], grid[offset + 1], grid[offset + 2]];
}

Float32List _buildLut(
  List<List<double>> matrix,
  List<double> bias,
  _ResidualGridFit residualFit,
  int lutDim,
) {
  final out = Float32List(lutDim * lutDim * lutDim * 3);
  final maxIndex = (lutDim - 1).toDouble();
  var offset = 0;
  for (var b = 0; b < lutDim; b++) {
    for (var g = 0; g < lutDim; g++) {
      for (var r = 0; r < lutDim; r++) {
        final rgb = RgbColor(r / maxIndex, g / maxIndex, b / maxIndex);
        final affine = RgbColor(
          rgb.r * matrix[0][0] +
              rgb.g * matrix[0][1] +
              rgb.b * matrix[0][2] +
              bias[0],
          rgb.r * matrix[1][0] +
              rgb.g * matrix[1][1] +
              rgb.b * matrix[1][2] +
              bias[1],
          rgb.r * matrix[2][0] +
              rgb.g * matrix[2][1] +
              rgb.b * matrix[2][2] +
              bias[2],
        ).clamp01();
        final residual = _sampleResidual(
          residualFit.values,
          residualFit.dim,
          rgb,
        );
        final output = RgbColor(
          (affine.r + residual.r).clamp(0.0, 1.0),
          (affine.g + residual.g).clamp(0.0, 1.0),
          (affine.b + residual.b).clamp(0.0, 1.0),
        ).clamp01();
        out[offset++] = output.r;
        out[offset++] = output.g;
        out[offset++] = output.b;
      }
    }
  }
  return out;
}

RgbColor _sampleResidual(Float32List residualGrid, int residualDim, RgbColor rgb) {
  final coords = [rgb.b, rgb.g, rgb.r];
  final scaled = coords.map((c) => c.clamp(0.0, 1.0) * (residualDim - 1)).toList();
  final base = scaled.map((value) => value.floor()).toList();
  final frac = [
    scaled[0] - base[0],
    scaled[1] - base[1],
    scaled[2] - base[2],
  ];
  final upper = [
    math.min(base[0] + 1, residualDim - 1),
    math.min(base[1] + 1, residualDim - 1),
    math.min(base[2] + 1, residualDim - 1),
  ];

  double channelAt(int b, int g, int r, int c) =>
      residualGrid[_cellIndex(residualDim, b, g, r) * 3 + c];

  final values = List<double>.filled(3, 0.0);
  for (final db in [0, 1]) {
    final ib = db == 1 ? upper[0] : base[0];
    final wb = db == 1 ? frac[0] : 1.0 - frac[0];
    for (final dg in [0, 1]) {
      final ig = dg == 1 ? upper[1] : base[1];
      final wg = dg == 1 ? frac[1] : 1.0 - frac[1];
      for (final dr in [0, 1]) {
        final ir = dr == 1 ? upper[2] : base[2];
        final wr = dr == 1 ? frac[2] : 1.0 - frac[2];
        final w = wb * wg * wr;
        for (var channel = 0; channel < 3; channel++) {
          values[channel] += channelAt(ib, ig, ir, channel) * w;
        }
      }
    }
  }
  return RgbColor(values[0], values[1], values[2]);
}

Uint8List _encodeLut(Float32List lut) {
  final values = Uint16List(lut.length);
  for (var i = 0; i < lut.length; i++) {
    values[i] = floatToHalf(lut[i]);
  }
  return values.buffer.asUint8List();
}

Float32List _decodeLut(Uint8List bytes) {
  final values = bytes.buffer.asUint16List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 2,
  );
  final out = Float32List(values.length);
  for (var i = 0; i < values.length; i++) {
    out[i] = halfToFloat(values[i]);
  }
  return out;
}

Map<String, dynamic> _evaluateFit(
  Float32List x,
  Float32List y,
  _AffineFit affine,
  Float32List lut,
) {
  final sampleCount = x.length ~/ 3;
  var affineSq = 0.0;
  var lutSq = 0.0;
  var affineAbs = 0.0;
  var lutAbs = 0.0;

  for (var i = 0; i < sampleCount; i++) {
    final xi = i * 3;
    final r = x[xi];
    final g = x[xi + 1];
    final b = x[xi + 2];
    final affinePred = [
      r * affine.matrix[0][0] +
          g * affine.matrix[0][1] +
          b * affine.matrix[0][2] +
          affine.bias[0],
      r * affine.matrix[1][0] +
          g * affine.matrix[1][1] +
          b * affine.matrix[1][2] +
          affine.bias[1],
      r * affine.matrix[2][0] +
          g * affine.matrix[2][1] +
          b * affine.matrix[2][2] +
          affine.bias[2],
    ];
    final lutPred = _sampleLut(lut, RgbColor(r, g, b));
    final target = [y[xi], y[xi + 1], y[xi + 2]];

    affineSq += math.pow(affinePred[0] - target[0], 2).toDouble();
    affineSq += math.pow(affinePred[1] - target[1], 2).toDouble();
    affineSq += math.pow(affinePred[2] - target[2], 2).toDouble();
    lutSq += math.pow(lutPred.r - target[0], 2).toDouble();
    lutSq += math.pow(lutPred.g - target[1], 2).toDouble();
    lutSq += math.pow(lutPred.b - target[2], 2).toDouble();
    affineAbs += (affinePred[0] - target[0]).abs() +
        (affinePred[1] - target[1]).abs() +
        (affinePred[2] - target[2]).abs();
    lutAbs += (lutPred.r - target[0]).abs() +
        (lutPred.g - target[1]).abs() +
        (lutPred.b - target[2]).abs();
  }

  final denom = sampleCount * 3.0;
  return {
    'sampleCount': sampleCount,
    'affineRMSE': math.sqrt(affineSq / denom),
    'affineMAE': affineAbs / denom,
    'lutRMSE': math.sqrt(lutSq / denom),
    'lutMAE': lutAbs / denom,
    'rmseImprovement':
        math.sqrt(affineSq / denom) - math.sqrt(lutSq / denom),
  };
}

RgbColor _sampleLut(Float32List lut, RgbColor rgb) {
  final dim = (math.pow(lut.length / 3, 1.0 / 3.0)).round();
  final coords = [rgb.b, rgb.g, rgb.r];
  final scaled = coords.map((c) => c.clamp(0.0, 1.0) * (dim - 1)).toList();
  final base = scaled.map((value) => value.floor()).toList();
  final frac = [
    scaled[0] - base[0],
    scaled[1] - base[1],
    scaled[2] - base[2],
  ];
  final upper = [
    math.min(base[0] + 1, dim - 1),
    math.min(base[1] + 1, dim - 1),
    math.min(base[2] + 1, dim - 1),
  ];

  List<double> cornerAt(int b, int g, int r) {
    final offset = _cellIndex(dim, b, g, r) * 3;
    return [lut[offset], lut[offset + 1], lut[offset + 2]];
  }

  final values = List<double>.filled(3, 0.0);
  for (final db in [0, 1]) {
    final ib = db == 1 ? upper[0] : base[0];
    final wb = db == 1 ? frac[0] : 1.0 - frac[0];
    for (final dg in [0, 1]) {
      final ig = dg == 1 ? upper[1] : base[1];
      final wg = dg == 1 ? frac[1] : 1.0 - frac[1];
      for (final dr in [0, 1]) {
        final ir = dr == 1 ? upper[2] : base[2];
        final wr = dr == 1 ? frac[2] : 1.0 - frac[2];
        final w = wb * wg * wr;
        final corner = cornerAt(ib, ig, ir);
        for (var channel = 0; channel < 3; channel++) {
          values[channel] += corner[channel] * w;
        }
      }
    }
  }
  return RgbColor(values[0], values[1], values[2]);
}
