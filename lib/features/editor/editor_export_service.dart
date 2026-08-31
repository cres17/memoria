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
    this.blendImageBytes,
    this.frameBytes,
    this.textOverlayBytes,
  });
}

/// Isolate-safe context supplied to an export worker.
class EditorExportWorkerContext {
  final EditorExportRequest request;
  final SendPort sendPort;

  const EditorExportWorkerContext(this.request, this.sendPort);
}

/// Owns one export worker and guarantees a single terminal result.
class EditorExportService {
  static const _exitGracePeriod = Duration(milliseconds: 100);
  static const _cancelExitGracePeriod = Duration(milliseconds: 500);
  static const _defaultProgressPulseInterval = Duration(milliseconds: 200);

  final Duration timeout;
  final Duration progressPulseInterval;
  final EditorExportWorkerEntrypoint _worker;
  _EditorExportJob? _activeJob;

  EditorExportService({
    this.timeout = const Duration(minutes: 2),
    this.progressPulseInterval = _defaultProgressPulseInterval,
    EditorExportWorkerEntrypoint worker = _editorExportWorker,
  }) : _worker = worker;

  Future<EditorExportJobResult> render(
    EditorExportRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (_activeJob != null) {
      throw StateError('An editor export is already running');
    }
    final job = _EditorExportJob(request, onProgress);
    _activeJob = job;
    try {
      _listen(job);
      _startProgressPulse(job);
      job.timeoutTimer = Timer(timeout, () {
        job.completeFailure(
          const EditorExportFailure(
            EditorExportFailureKind.timeout,
            'Export worker exceeded its terminal timeout',
          ),
        );
        job.kill();
      });
      job.isolate = await Isolate.spawn(
        _worker,
        EditorExportWorkerContext(request, job.messagePort.sendPort),
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
      if (message is num) {
        final progress = message.toDouble().clamp(0.0, 0.99).toDouble();
        job.emitProgress(progress);
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

  void _startProgressPulse(_EditorExportJob job) {
    if (job.onProgress == null) return;
    job.emitProgress(0.01);
    job.progressTimer = Timer.periodic(progressPulseInterval, (_) {
      if (job.cancelled || job.terminal.isCompleted) return;
      // Worker milestones remain authoritative. Between CPU-heavy stages,
      // advance conservatively so the UI communicates liveness without ever
      // claiming that encoding or writing has completed.
      const ceiling = 0.949;
      if (job.lastProgress >= ceiling) return;
      final remaining = ceiling - job.lastProgress;
      final step = remaining > 0.02 ? 0.01 : remaining / 2;
      job.emitProgress(job.lastProgress + step);
    });
  }

  Future<void> _dispose(_EditorExportJob job) async {
    job.timeoutTimer?.cancel();
    job.progressTimer?.cancel();
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
  Timer? progressTimer;
  Isolate? isolate;
  bool cancelled = false;
  double lastProgress = 0;
  EditorExportFailure? failure;

  _EditorExportJob(this.request, this.onProgress);

  void emitProgress(double value) {
    if (terminal.isCompleted || value <= lastProgress) return;
    lastProgress = value;
    onProgress?.call(value);
  }

  void complete(EditorExportJobResult result) {
    if (!terminal.isCompleted) {
      progressTimer?.cancel();
      terminal.complete(_EditorExportTerminal.completed(result));
    }
  }

  void completeFailure(EditorExportFailure value) {
    if (terminal.isCompleted) return;
    progressTimer?.cancel();
    failure = value;
    terminal.complete(_EditorExportTerminal.failed(value));
  }

  void kill() => isolate?.kill(priority: Isolate.immediate);
}

Future<void> _editorExportWorker(EditorExportWorkerContext context) async {
  final request = context.request;
  try {
    img.Image? source;
    try {
      final decoded =
          img.decodeImage(File(request.imagePath).readAsBytesSync());
      source = decoded == null ? null : img.bakeOrientation(decoded);
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
    final rendered = await EditorRenderer.renderExport(
      source: source,
      recipe: request.recipe,
      maxDimension: request.maxDimension,
      resources: EditorRenderResources(
        segmentMask: request.segmentMask,
        segmentMaskWidth: request.segmentMaskWidth,
        segmentMaskHeight: request.segmentMaskHeight,
        blendImageBytes: request.blendImageBytes,
        frameBytes: request.frameBytes,
        textOverlayBytes: request.textOverlayBytes,
      ),
      onProgress: context.sendPort.send,
    );
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
    context.sendPort.send('done');
  } catch (error) {
    context.sendPort.send(
      EditorExportFailure.fromError(error).toWorkerMessage(),
    );
  }
}
