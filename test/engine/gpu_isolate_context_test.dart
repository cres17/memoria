import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/gpu_ops.dart';

void main() {
  test('disabled GPU never captures an isolate token', () {
    final context = GpuIsolateContext.capture(false);
    expect(context.enabled, isFalse);
    expect(context.rootToken, isNull);
  });

  test('Android keeps CPU and does not capture a token', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final context = GpuIsolateContext.capture(true);
    expect(context.enabled, isFalse);
    expect(context.rootToken, isNull);
  });

  test('web keeps CPU before accessing unsupported token API', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final context = GpuIsolateContext.capture(true);
    expect(context.enabled, isFalse);
    expect(context.rootToken, isNull);
  }, skip: !kIsWeb);
}
