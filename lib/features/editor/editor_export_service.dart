import 'package:flutter/services.dart';
import '../../engine/gpu_ops.dart';
import '../../core/remote_config/remote_config.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';

enum EditorExportJobResult { completed, cancelled }

typedef EditorExportWorkerEntrypoint = Future<void> Function(
  EditorExportWorkerContext context,
);

class EditorExportRequest {
  final String imagePath;
  final String outputPath;
  final ExportFormat format;
  final int quality;
  final int? maxDimension;
  final EditorRenderRecipe recipe;
  final Float32List? segmentMask;
  final int segmentMaskWidth;
  final int segmentMaskHeight;
  final Float32List? skyMask;
  final int skyMaskWidth;
  final int skyMaskHeight;
  final Uint8List? blendImageBytes;
  final Uint8List? frameBytes;
  final Uint8List? textOverlayBytes;

  const EditorExportRequest({
    required this.imagePath,
    required this.outputPath,
    required this.format,
    required this.quality,
    this.maxDimension,
    required this.recipe,
    this.segmentMask,
    this.segmentMaskWidth = 0,
    this.segmentMaskHeight = 0,
    this.skyMask,
    this.skyMaskWidth = 0,
    this.skyMaskHeight = 0,
    this.blendImageBytes,
    this.frameBytes,
    this.textOverlayBytes,
  });
}

/// Isolate-safe context supplied to an export worker.
class EditorExportWorkerContext {
  final EditorExportRequest request;
  final SendPort sendPort;
  final RootIsolateToken? rootIsolateToken;
  final bool gpuOpsEnabled;
  final bool collectTiming;

  const EditorExportWorkerContext(this.request, this.sendPort,
      [this.rootIsolateToken,
      this.gpuOpsEnabled = false,
      this.collectTiming = false]);
}

/// Owns one export worker and guarantees a single terminal result.
class EditorExportService {
  static const _exitGracePeriod = Duration(milliseconds: 100);
  static const _cancelExitGracePeriod = Duration(milliseconds: 500);

  final Duration timeout;
  final EditorExportWorkerEntrypoint _worker;
  _EditorExportJob? _activeJob;

  EditorExportService({
    this.timeout = const Duration(minutes: 2),
    EditorExportWorkerEntrypoint worker = _editorExportWorker,
  }) : _worker = worker;

  Future<EditorExportJobResult> render(
    EditorExportRequest request, {
    void Function(double progress)? onProgress,
    void Function(Map<String, dynamic> timing)? onTiming,
  }) async {
    if (_activeJob != null) {
      throw StateError('An editor export is already running');
    }
    final job = _EditorExportJob(request, onProgress, onTiming);
    _activeJob = job;
    try {
      _listen(job);
      job.timeoutTimer = Timer(timeout, () {
        job.completeFailure(
          const EditorExportFailure(
            EditorExportFailureKind.timeout,
            'Export worker exceeded its terminal timeout',
          ),
        );
        job.kill();
      });
      final gpuContext = GpuIsolateContext.capture(
          RemoteConfigService.instance.gpuOpsIosEnabled);
      job.isolate = await Isolate.spawn(
        _worker,
        EditorExportWorkerContext(request, job.messagePort.sendPort,
            gpuContext.rootToken, gpuContext.enabled, onTiming != null),
        onExit: job.exitPort.sendPort,
        onError: job.errorPort.sendPort,
        errorsAreFatal: true,
      );
      if (job.cancelled) {
        job.complete(EditorExportJobResult.cancelled);
        job.kill();
      }
      final terminal = await job.terminal.future;
      if (terminal.failure != null) throw terminal.failure!;
      return terminal.result!;
    } on EditorExportFailure {
      rethrow;
    } catch (error) {
      throw EditorExportFailure.fromError(error);
    } finally {
      await _dispose(job);
      if (identical(_activeJob, job)) _activeJob = null;
      if (!job.cleanup.isCompleted) job.cleanup.complete();
    }
  }

  void _listen(_EditorExportJob job) {
    job.messageSubscription = job.messagePort.listen((message) {
      if (message == 'gpu_interrupted') {
        job.cancelled = true;
        job.completeFailure(const EditorExportFailure(
          EditorExportFailureKind.systemInterrupted,
          'GPU foreground permission was withdrawn',
        ));
        return;
      }
      if (message is Map && message['type'] == 'render_timing') {
        job.onTiming?.call(Map<String, dynamic>.from(message['data'] as Map));
        return;
      }
      if (message is num) {
        final progress = message.toDouble().clamp(0.0, 0.99).toDouble();
        if (progress > job.lastProgress) {
          job.lastProgress = progress;
          job.onProgress?.call(progress);
        }
        return;
      }
      if (message == 'done') {
        job.complete(EditorExportJobResult.completed);
        return;
      }
      if (message is Map && message['type'] == 'editor_export_failure') {
        job.completeFailure(EditorExportFailure.fromWorkerMessage(message));
      }
    });
    job.errorSubscription = job.errorPort.listen((_) {
      job.completeFailure(
        const EditorExportFailure(
          EditorExportFailureKind.workerTerminated,
          'Export worker reported an unhandled isolate error',
        ),
      );
    });
    job.exitSubscription = job.exitPort.listen((_) async {
      if (!job.exitObserved.isCompleted) job.exitObserved.complete();
      if (job.terminal.isCompleted) return;
      await Future<void>.delayed(_exitGracePeriod);
      if (!job.terminal.isCompleted) {
        job.completeFailure(
          const EditorExportFailure(
            EditorExportFailureKind.workerTerminated,
            'Export worker exited without a terminal message',
          ),
        );
      }
    });
  }

  Future<void> _dispose(_EditorExportJob job) async {
    job.timeoutTimer?.cancel();
    if (job.cancelled || !job.terminal.isCompleted) job.kill();
    if (job.isolate != null && !job.exitObserved.isCompleted) {
      await Future.any<void>([
        job.exitObserved.future,
        Future<void>.delayed(_cancelExitGracePeriod),
      ]);
    }
    await job.messageSubscription?.cancel();
    await job.errorSubscription?.cancel();
    await job.exitSubscription?.cancel();
    job.messagePort.close();
    job.errorPort.close();
    job.exitPort.close();
    if (job.cancelled || job.failure != null) {
      await _removeIncompleteOutput(job.request.outputPath);
    }
  }

  Future<void> _removeIncompleteOutput(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Requests cancellation and resolves only after isolate/port cleanup.
  Future<void> cancel() {
    final job = _activeJob;
    if (job == null) return Future<void>.value();
    job.cancelled = true;
    job.complete(EditorExportJobResult.cancelled);
    job.kill();
    return job.cleanup.future;
  }
}

class _EditorExportTerminal {
  final EditorExportJobResult? result;
  final EditorExportFailure? failure;

  const _EditorExportTerminal._({this.result, this.failure});

  const _EditorExportTerminal.completed(EditorExportJobResult result)
      : this._(result: result);

  const _EditorExportTerminal.failed(EditorExportFailure failure)
      : this._(failure: failure);
}

class _EditorExportJob {
  final EditorExportRequest request;
  final void Function(double progress)? onProgress;
  final void Function(Map<String, dynamic> timing)? onTiming;
  final ReceivePort messagePort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();
  final ReceivePort errorPort = ReceivePort();
  final Completer<_EditorExportTerminal> terminal = Completer();
  final Completer<void> exitObserved = Completer();
  final Completer<void> cleanup = Completer();
  StreamSubscription<dynamic>? messageSubscription;
  StreamSubscription<dynamic>? exitSubscription;
  StreamSubscription<dynamic>? errorSubscription;
  Timer? timeoutTimer;
  Isolate? isolate;
  bool cancelled = false;
  double lastProgress = 0;
  EditorExportFailure? failure;

  _EditorExportJob(this.request, this.onProgress, this.onTiming);

  void complete(EditorExportJobResult result) {
    if (!terminal.isCompleted) {
      terminal.complete(_EditorExportTerminal.completed(result));
    }
  }

  void completeFailure(EditorExportFailure value) {
    if (terminal.isCompleted) return;
    failure = value;
    terminal.complete(_EditorExportTerminal.failed(value));
  }

  void kill() => isolate?.kill(priority: Isolate.immediate);
}

Future<void> _editorExportWorker(EditorExportWorkerContext context) async {
  final request = context.request;
  final phase = Stopwatch()..start();
  void timing(Map<String, Object?> data) {
    if (context.collectTiming) {
      context.sendPort.send({'type': 'render_timing', 'data': data});
    }
  }

  try {
    // 원본 디코딩은 큰 사진에서 수 초 걸릴 수 있다. 그동안 0%에 멈춰 보이지 않도록
    // 작업 시작과 디코딩 완료 시점에도 진행률을 보낸다.
    context.sendPort.send(0.02);
    img.Image? source;
    try {
      final decoded =
          img.decodeImage(File(request.imagePath).readAsBytesSync());
      source = decoded == null ? null : img.bakeOrientation(decoded);
      timing({
        'phase': 'read_decode_orientation',
        'ms': phase.elapsedMicroseconds / 1000
      });
      context.sendPort.send(0.10);
    } catch (error) {
      context.sendPort.send(
        EditorExportFailure(
          EditorExportFailureKind.inputDecode,
          'Image input failed (${error.runtimeType})',
        ).toWorkerMessage(),
      );
      return;
    }
    if (source == null) {
      context.sendPort.send(
        const EditorExportFailure(
          EditorExportFailureKind.inputDecode,
          'Image decoder returned null',
        ).toWorkerMessage(),
      );
      return;
    }
    if (context.gpuOpsEnabled) {
      GpuOps.initializeBackground(context.rootIsolateToken);
    }
    phase.reset();
    final rendered = await EditorRenderer.renderExport(
      gpu: GpuOps(
          enabled: context.gpuOpsEnabled,
          onTiming: timing,
          onFallback: () => timing({'phase': 'gpu_fallback'})),
      source: source,
      recipe: request.recipe,
      maxDimension: request.maxDimension,
      resources: EditorRenderResources(
        segmentMask: request.segmentMask,
        segmentMaskWidth: request.segmentMaskWidth,
        segmentMaskHeight: request.segmentMaskHeight,
        skyMask: request.skyMask,
        skyMaskWidth: request.skyMaskWidth,
        skyMaskHeight: request.skyMaskHeight,
        blendImageBytes: request.blendImageBytes,
        frameBytes: request.frameBytes,
        textOverlayBytes: request.textOverlayBytes,
      ),
      onProgress: context.sendPort.send,
    );
    timing({
      'phase': 'spatial_visual_pipeline',
      'ms': phase.elapsedMicroseconds / 1000
    });
    phase.reset();
    context.sendPort.send(0.85);
    final encoded = ExportEncoder.encode(
      rendered,
      format: request.format,
      quality: request.quality,
    );
    try {
      await File(request.outputPath).writeAsBytes(encoded);
    } catch (error) {
      context.sendPort.send(
        EditorExportFailure(
          EditorExportFailureKind.outputWrite,
          'Output write failed (${error.runtimeType})',
        ).toWorkerMessage(),
      );
      return;
    }
    context.sendPort.send(0.95);
    timing({'phase': 'encode_write', 'ms': phase.elapsedMicroseconds / 1000});
    context.sendPort.send('done');
  } on GpuWorkInterrupted {
    context.sendPort.send('gpu_interrupted');
  } catch (error) {
    context.sendPort.send(
      EditorExportFailure.fromError(error).toWorkerMessage(),
    );
  }
}
