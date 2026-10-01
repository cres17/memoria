import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ai/models/segmenter.dart';

void main() {
  final mask = SegmentMask(Float32List.fromList([0, 0.2, 0.6, 1]), 2, 2);

  test('one-pixel axes sample the source center without NaN', () {
    expect(mask.resize(1, 2).data, closeToList([0.1, 0.8]));
    expect(mask.resize(2, 1).data, closeToList([0.3, 0.6]));
    expect(mask.resize(1, 1).data.single, closeTo(0.45, 1e-6));
  });

  test('a single-pixel source expands to a constant mask', () {
    final single = SegmentMask(Float32List.fromList([0.7]), 1, 1);
    expect(single.resize(4, 3).data, everyElement(closeTo(0.7, 1e-6)));
  });

  test('rejects nonpositive target dimensions', () {
    expect(() => mask.resize(0, 2), throwsArgumentError);
    expect(() => mask.resize(2, 0), throwsArgumentError);
    expect(() => mask.resize(-1, 2), throwsArgumentError);
  });
}

Matcher closeToList(List<double> values) =>
    orderedEquals(values.map((value) => closeTo(value, 1e-6)));
