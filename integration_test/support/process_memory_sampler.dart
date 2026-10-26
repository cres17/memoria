import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Samples process-wide RSS independently of synchronous work on the UI isolate.
/// RSS includes the test runner and is not an iOS physical-footprint measurement.
class ProcessMemorySampler {
  final ReceivePort _events = ReceivePort();
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Completer<Map<String, int>> _result = Completer<Map<String, int>>();
  late final Isolate _worker;
  late final SendPort _commands;
  Future<Map<String, int>>? _stopping;
  StateError? _workerError;

  ProcessMemorySampler._();

  static Future<ProcessMemorySampler> start() async {
    final sampler = ProcessMemorySampler._();
    sampler._events.listen((message) {
      if (message is SendPort) {
        sampler._ready.complete(message);
      } else if (message is Map) {
        sampler._result.complete(Map<String, int>.from(message));
      } else if (message is List) {
        final error = StateError('Memory sampler failed: ${message.first}');
        sampler._workerError = error;
        if (!sampler._ready.isCompleted) {
          sampler._ready.completeError(error);
        } else if (!sampler._result.isCompleted) {
          sampler._result.complete({});
        }
      }
    });
    sampler._worker = await Isolate.spawn(
      _sampleProcessMemory,
      sampler._events.sendPort,
      onError: sampler._events.sendPort,
      errorsAreFatal: true,
    );
    try {
      sampler._commands = await sampler._ready.future.timeout(
        const Duration(seconds: 10),
      );
      return sampler;
    } catch (_) {
      sampler._worker.kill(priority: Isolate.immediate);
      sampler._events.close();
      rethrow;
    }
  }

  Future<Map<String, int>> stop() => _stopping ??= _stopOnce();

  Future<Map<String, int>> _stopOnce() async {
    _commands.send('stop');
    try {
      final result = await _result.future.timeout(const Duration(seconds: 10));
      if (_workerError != null) throw _workerError!;
      return result;
    } finally {
      _worker.kill(priority: Isolate.immediate);
      _events.close();
    }
  }
}

void _sampleProcessMemory(SendPort results) {
  final commands = ReceivePort();
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  var samples = 0;
  void sample() {
    final rss = ProcessInfo.currentRss;
    if (rss > peak) peak = rss;
    samples++;
  }

  sample();
  final timer =
      Timer.periodic(const Duration(milliseconds: 10), (_) => sample());
  results.send(commands.sendPort);
  commands.listen((message) {
    if (message != 'stop') return;
    timer.cancel();
    sample();
    results.send(<String, int>{
      'baseline': baseline,
      'peak': peak,
      'after': ProcessInfo.currentRss,
      'peakDelta': peak - baseline,
      'samples': samples,
      'intervalMs': 10,
    });
    commands.close();
  });
}
