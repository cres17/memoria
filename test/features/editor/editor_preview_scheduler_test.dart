import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/editor_preview_scheduler.dart';

void main() {
  test('WB-ASYNC-01 stale worker result cannot win over the latest request',
      () async {
    final completions = <String, Completer<String>>{};
    final scheduler = EditorPreviewScheduler<String, String>(
      worker: (request) => (completions[request] = Completer<String>()).future,
    );

    final oldToken = scheduler.beginRequest();
    final oldResult = scheduler.execute('old', token: oldToken);
    final newToken = scheduler.beginRequest();
    final newResult = scheduler.execute('new', token: newToken);

    completions['new']!.complete('new-result');
    expect(await newResult, const _ExecutionMatcher('new-result', true));

    completions['old']!.complete('old-result');
    expect(await oldResult, const _ExecutionMatcher('old-result', false));
  });

  test('WB-ASYNC-01 injected clock cancels superseded debounce', () {
    final clock = _ManualPreviewClock();
    final calls = <String>[];
    final scheduler = EditorPreviewScheduler<String, String>(
      worker: (request) async => request,
      clock: clock,
    );

    scheduler.debounce(
        const Duration(milliseconds: 32), () => calls.add('old'));
    scheduler.debounce(
        const Duration(milliseconds: 32), () => calls.add('new'));
    clock.fireAll();

    expect(calls, ['new']);
  });
}

class _ExecutionMatcher extends Matcher {
  final String value;
  final bool isLatest;

  const _ExecutionMatcher(this.value, this.isLatest);

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is EditorPreviewExecution<String> &&
      item.value == value &&
      item.isLatest == isLatest;

  @override
  Description describe(Description description) => description.add(
        'execution(value: $value, isLatest: $isLatest)',
      );
}

class _ManualPreviewClock implements EditorPreviewClock {
  final _tasks = <_ManualPreviewTask>[];

  @override
  EditorPreviewScheduledTask schedule(
    Duration delay,
    void Function() action,
  ) {
    final task = _ManualPreviewTask(action);
    _tasks.add(task);
    return task;
  }

  void fireAll() {
    for (final task in List<_ManualPreviewTask>.from(_tasks)) {
      task.fire();
    }
  }
}

class _ManualPreviewTask implements EditorPreviewScheduledTask {
  final void Function() _action;
  bool _cancelled = false;

  _ManualPreviewTask(this._action);

  void fire() {
    if (!_cancelled) _action();
  }

  @override
  void cancel() => _cancelled = true;
}
