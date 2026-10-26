import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/startup/app_startup.dart';

void main() {
  test('a failed startup task does not skip later tasks', () async {
    final completed = <String>[];
    final failures = <String>[];

    await runStartupTasks(
      [
        StartupTask('diagnostics', () => completed.add('diagnostics')),
        StartupTask('gpu', () => throw StateError('GPU unavailable')),
        StartupTask('locale', () async => completed.add('locale')),
        StartupTask('models', () => completed.add('models')),
      ],
      onFailure: (name, error, stackTrace) => failures.add(name),
    );

    expect(completed, ['diagnostics', 'locale', 'models']);
    expect(failures, ['gpu']);
  });

  test('startup tasks run sequentially in declaration order', () async {
    final events = <String>[];

    await runStartupTasks(
      [
        StartupTask('first', () async {
          events.add('first:start');
          await Future<void>.delayed(Duration.zero);
          events.add('first:end');
        }),
        StartupTask('second', () => events.add('second')),
      ],
      onFailure: (_, __, ___) => fail('no failure expected'),
    );

    expect(events, ['first:start', 'first:end', 'second']);
  });
}
