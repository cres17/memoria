import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';

void main() {
  test('system interruption requests retry without a resolution retry', () {
    const failure = EditorExportFailure(
        EditorExportFailureKind.systemInterrupted, 'GPU interrupted');
    final restored =
        EditorExportFailure.fromWorkerMessage(failure.toWorkerMessage());
    expect(restored.kind, EditorExportFailureKind.systemInterrupted);
    expect(restored.canRetryAtLowerResolution, isFalse);
    expect(restored.userMessage, contains('사진이 저장되지 않았습니다'));
    expect(restored.userMessage, contains('다시 시도'));
  });

  test('worker failure round-trips its category without a source path', () {
    const failure = EditorExportFailure(
      EditorExportFailureKind.inputDecode,
      'Image codec rejected the input',
    );

    final restored = EditorExportFailure.fromWorkerMessage(
      failure.toWorkerMessage(),
    );

    expect(restored.kind, EditorExportFailureKind.inputDecode);
    expect(restored.userMessage, contains('원본 사진'));
    expect(restored.canRetryAtLowerResolution, isFalse);
  });

  test('maps memory errors to the resolution fallback path', () {
    final failure = EditorExportFailure.fromError(
      Exception('Out of memory while allocating output buffer'),
    );

    expect(failure.kind, EditorExportFailureKind.memoryPressure);
    expect(failure.canRetryAtLowerResolution, isTrue);
  });

  test('redacts local source paths from diagnostics', () {
    final failure = EditorExportFailure.fromError(
      Exception('Cannot read /private/var/mobile/DCIM/private-photo.jpg'),
    );

    expect(failure.diagnostic, isNot(contains('private-photo.jpg')));
    expect(failure.diagnostic, contains('<path>'));
  });
}
