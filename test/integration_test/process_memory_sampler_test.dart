import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/process_memory_sampler.dart';

void main() {
  test('RSS sampling continues while the calling isolate is blocked', () async {
    final sampler = await ProcessMemorySampler.start();
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < 200) {
      // A UI-isolate Timer cannot run here. The sampler must still collect.
    }
    final result = await sampler.stop();
    // start and stop each take one sample; >2 requires independent sampling.
    expect(result['samples'], greaterThan(2));
    expect(result['peak'], greaterThanOrEqualTo(result['baseline']!));
    expect(result['peakDelta'], greaterThanOrEqualTo(0));
  });

  test('repeated stop calls share the same terminal result', () async {
    final sampler = await ProcessMemorySampler.start();
    final first = sampler.stop();
    final second = sampler.stop();
    expect(identical(first, second), isTrue);
    expect(await first, await second);
  });
}
