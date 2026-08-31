import 'dart:async';

typedef EditorPreviewWorker<Request, Result> = Future<Result> Function(
  Request request,
);

abstract interface class EditorPreviewScheduledTask {
  void cancel();
}

abstract interface class EditorPreviewClock {
  EditorPreviewScheduledTask schedule(Duration delay, void Function() action);
}

class SystemEditorPreviewClock implements EditorPreviewClock {
  const SystemEditorPreviewClock();

  @override
  EditorPreviewScheduledTask schedule(
    Duration delay,
    void Function() action,
  ) =>
      _TimerPreviewTask(Timer(delay, action));
}

class _TimerPreviewTask implements EditorPreviewScheduledTask {
  final Timer _timer;

  _TimerPreviewTask(this._timer);

  @override
  void cancel() => _timer.cancel();
}

class EditorPreviewExecution<Result> {
  final Result value;
  final bool isLatest;

  const EditorPreviewExecution({
    required this.value,
    required this.isLatest,
  });
}

/// Owns preview debounce timing and latest-request-wins sequencing.
///
/// The clock and isolate worker are injectable so races can be reproduced
/// deterministically without relying on wall-clock delays.
class EditorPreviewScheduler<Request, Result> {
  final EditorPreviewWorker<Request, Result> _worker;
  final EditorPreviewClock _clock;
  EditorPreviewScheduledTask? _debouncedTask;
  int _latestToken = 0;
  bool _disposed = false;

  EditorPreviewScheduler({
    required EditorPreviewWorker<Request, Result> worker,
    EditorPreviewClock clock = const SystemEditorPreviewClock(),
  })  : _worker = worker,
        _clock = clock;

  int beginRequest() {
    if (_disposed) return _latestToken;
    return ++_latestToken;
  }

  bool isLatest(int token) => !_disposed && token == _latestToken;

  void debounce(Duration delay, void Function() request) {
    if (_disposed) return;
    _debouncedTask?.cancel();
    _debouncedTask = _clock.schedule(delay, () {
      _debouncedTask = null;
      if (!_disposed) request();
    });
  }

  Future<EditorPreviewExecution<Result>> execute(
    Request request, {
    required int token,
  }) async {
    final value = await _worker(request);
    return EditorPreviewExecution(value: value, isLatest: isLatest(token));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _latestToken++;
    _debouncedTask?.cancel();
    _debouncedTask = null;
  }
}
