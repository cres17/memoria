import 'dart:async';

typedef StartupTaskBody = FutureOr<void> Function();
typedef StartupFailureHandler = void Function(
  String taskName,
  Object error,
  StackTrace stackTrace,
);

/// One independently recoverable post-frame initialization step.
class StartupTask {
  final String name;
  final StartupTaskBody run;

  const StartupTask(this.name, this.run);
}

/// Runs startup work in deterministic order while isolating every failure.
///
/// A locale, renderer, model, or platform-service failure must never prevent
/// later initialization steps from running. The app has already rendered its
/// first frame when this function is used, so failures are reported locally
/// and the usable parts of the app remain available.
Future<void> runStartupTasks(
  Iterable<StartupTask> tasks, {
  required StartupFailureHandler onFailure,
}) async {
  for (final task in tasks) {
    try {
      await task.run();
    } catch (error, stackTrace) {
      onFailure(task.name, error, stackTrace);
    }
  }
}
