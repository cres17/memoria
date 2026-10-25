import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'image_operation.dart';

/// Foreground permission was withdrawn. Do not start a long CPU retry while the
/// app is resigning active; the export boundary treats this as cancellation.
class GpuWorkInterrupted implements Exception {}

/// Capture policy and token together on the root isolate. Web cannot access
/// RootIsolateToken.instance at all, even when no platform channel is invoked.
class GpuIsolateContext {
  final bool enabled;
  final RootIsolateToken? rootToken;
  const GpuIsolateContext._(this.enabled, this.rootToken);

  factory GpuIsolateContext.capture(bool requested) {
    final enabled =
        requested && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return GpuIsolateContext._(
        enabled, enabled ? RootIsolateToken.instance : null);
  }
}

/// A request-scoped policy snapshot. Android and disabled recipes do not invoke
/// the native channel, including capability queries.
class GpuOps {
  static const channel = MethodChannel('com.memoria/lut_engine');
  final bool enabled;
  final void Function(Map<String, Object?> timing)? onTiming;
  final VoidCallback? onFallback;
  final Duration operationTimeout;

  const GpuOps(
      {this.enabled = false,
      this.onTiming,
      this.onFallback,
      this.operationTimeout = const Duration(seconds: 30)});

  static void initializeBackground(RootIsolateToken? token) {
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
  }

  void _event(String reason, {String? blockedReason}) {
    // Structured, pixel/path-free events are collected by the same per-request
    // timing sink used by device tests. No remote reporting is enabled here.
    onTiming?.call({
      'phase': 'gpu_recovery',
      'reason': reason,
      if (blockedReason != null) 'blocked_reason': blockedReason
    });
  }

  Future<img.Image?> _run(ImageOperation op) async {
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    final image = op.input;
    if (image.format != img.Format.uint8 ||
        image.hasPalette ||
        image.numFrames != 1 ||
        (image.numChannels != 3 && image.numChannels != 4)) {
      return null;
    }
    final radius = op.parameters['radius']?.toInt() ?? 0;
    if (op.kind == 'blur' &&
        (radius <= 0 || radius >= image.width || radius >= image.height)) {
      return null;
    }
    final watch = Stopwatch()..start();
    String? lease;
    var timedOut = false;
    try {
      // Persist before allocating a packed request, including possible OOM here.
      lease = await channel
          .invokeMethod<String>('gpuBegin')
          .timeout(operationTimeout);
      if (lease == null) return null;
      final packing = Stopwatch()..start();
      final bytes = image.toUint8List();
      final packUs = packing.elapsedMicroseconds;
      final reply = await channel.invokeMapMethod<String, dynamic>('gpuOp', {
        'op': op.kind,
        'lease': lease,
        'width': image.width,
        'height': image.height,
        'channels': image.numChannels,
        'bytes': bytes,
        ...op.parameters,
      }).timeout(operationTimeout);
      final output = reply?['bytes'];
      if (output is! Uint8List || output.length != bytes.length) {
        _event('invalid_reply');
        return null;
      }
      final unpack = Stopwatch()..start();
      var result = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: output.buffer,
          bytesOffset: output.offsetInBytes,
          numChannels: image.numChannels);
      // The CPU NR primitive returns RGB. The pipeline restores source alpha
      // after all image effects; keep that contract at intermediate stages.
      if (op.kind == 'noise' && image.numChannels == 4) {
        result = result.convert(numChannels: 3);
      }
      onTiming?.call({
        'op': op.kind,
        'pack_ms': packUs / 1000,
        'unpack_ms': unpack.elapsedMicroseconds / 1000,
        'roundtrip_ms': watch.elapsedMicroseconds / 1000,
        'bytes_each_way': bytes.length,
        'native': reply?['timing'],
      });
      return result;
    } on TimeoutException {
      timedOut = true;
      _event('timeout');
      await _disable('timeout');
      return null;
    } on PlatformException catch (error) {
      final reason = switch (error.code) {
        'GPU_BUSY' => 'busy',
        'GPU_TIMEOUT' => 'timeout',
        'GPU_INTERRUPTED' => 'interrupted',
        'GPU_BLOCKED' => 'blocked',
        _ => 'failed',
      };
      final details = error.details;
      final blockedReason = details is Map ? details['blocked_reason'] : null;
      _event(reason,
          blockedReason: blockedReason is String ? blockedReason : null);
      if (error.code == 'GPU_INTERRUPTED') throw GpuWorkInterrupted();
      return null;
    } on MissingPluginException {
      _event('failed');
      return null;
    } on TypeError {
      _event('failed');
      // A broken native protocol must not bypass the CPU recovery path.
      return null;
    } on FormatException {
      _event('failed');
      return null;
    } finally {
      if (lease != null && !timedOut) {
        try {
          await channel.invokeMethod<void>(
              'gpuEnd', {'lease': lease}).timeout(const Duration(seconds: 1));
        } on Object {
          _event('cleanup_failed');
          await _disable('cleanup_failed');
        }
      }
    }
  }

  Future<void> _disable(String reason) async {
    try {
      await channel.invokeMethod<void>(
          'gpuDisable', {'reason': reason}).timeout(const Duration(seconds: 1));
    } on Object {
      // The on-disk active marker remains if the native channel cannot respond.
    }
  }

  Future<void> resolve(ImageOperation op) async {
    final output = await _run(op);
    if (output == null) {
      if (enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        onFallback?.call();
      }
      op.resolveCpu();
    } else {
      if (op.kind == 'blur') {
        // fastGaussianBlur mutates its argument. Preserve object identity and
        // existing compositing behavior after a validated successful reply.
        final commit = Stopwatch()..start();
        op.input.toUint8List().setAll(0, output.toUint8List());
        onTiming?.call({
          'phase': 'dart_blur_copy_back',
          'ms': commit.elapsedMicroseconds / 1000,
          'bytes': output.toUint8List().length
        });
        op.result = op.input;
      } else {
        op.result = output;
      }
    }
  }

  Future<img.Image?> gpuNoiseReduction(
          img.Image input, double luma, double chroma, double detail) =>
      _run(ImageOperation.noise(input, luma, chroma, detail, () => input));

  Future<img.Image?> gpuGaussianBlur(img.Image input, int radius) =>
      _run(ImageOperation.blur(input, radius));
}
