import 'package:memoria/features/editor/editor_resource_preparer.dart';

/// Failure contract shared by the export coordinator and its isolate worker.
///
/// The worker message intentionally contains no source path or pixel data. It
/// can be logged safely and gives the UI a stable recovery decision without
/// exposing raw platform exceptions to the user.
enum EditorExportFailureKind {
  inputDecode,
  memoryPressure,
  nativeEncoding,
  outputWrite,
  outputValidation,
  workerTerminated,
  timeout,
  resourcePreparation,
  unexpected,
}

class EditorExportFailure implements Exception {
  final EditorExportFailureKind kind;
  final String diagnostic;

  const EditorExportFailure(this.kind, this.diagnostic);

  bool get canRetryAtLowerResolution =>
      kind == EditorExportFailureKind.memoryPressure;

  String get userMessage {
    switch (kind) {
      case EditorExportFailureKind.inputDecode:
        return '원본 사진을 열 수 없습니다. 사진을 다시 선택해 주세요.';
      case EditorExportFailureKind.memoryPressure:
        return '메모리가 부족합니다. 해상도를 낮춰 다시 시도합니다.';
      case EditorExportFailureKind.nativeEncoding:
        return '이 기기에서 선택한 파일 형식으로 내보낼 수 없습니다.';
      case EditorExportFailureKind.outputWrite:
        return '내보낸 사진 파일을 저장하지 못했습니다.';
      case EditorExportFailureKind.outputValidation:
        return '내보낸 파일을 확인하지 못했습니다. 다시 시도해 주세요.';
      case EditorExportFailureKind.workerTerminated:
        return '내보내기 작업이 예기치 않게 종료되었습니다. 다시 시도해 주세요.';
      case EditorExportFailureKind.timeout:
        return '내보내기 시간이 초과되었습니다. 해상도를 낮춰 다시 시도해 주세요.';
      case EditorExportFailureKind.resourcePreparation:
        return '내보내기에 필요한 편집 리소스를 준비하지 못했습니다. 다시 시도해 주세요.';
      case EditorExportFailureKind.unexpected:
        return '사진을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  Map<String, String> toWorkerMessage() => {
        'type': 'editor_export_failure',
        'kind': kind.name,
        'diagnostic': diagnostic,
      };

  factory EditorExportFailure.fromWorkerMessage(Map<dynamic, dynamic> message) {
    final kindName = message['kind'] as String?;
    final kind = EditorExportFailureKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => EditorExportFailureKind.unexpected,
    );
    return EditorExportFailure(kind, message['diagnostic'] as String? ?? '');
  }

  factory EditorExportFailure.fromError(Object error) {
    if (error is EditorExportFailure) return error;
    if (error is EditorResourcePreparationFailure) {
      return EditorExportFailure(
        EditorExportFailureKind.resourcePreparation,
        error.kind.name,
      );
    }
    final raw = error.toString().toLowerCase();
    final kind = raw.contains('out of memory') ||
            raw.contains('oom') ||
            raw.contains('allocation')
        ? EditorExportFailureKind.memoryPressure
        : EditorExportFailureKind.unexpected;
    return EditorExportFailure(kind, _sanitizeDiagnostic(error.toString()));
  }

  static String _sanitizeDiagnostic(String value) => value
      .replaceAll(RegExp(r'(?:file://)?/(?:[^\s:]+/)+[^\s:]+'), '<path>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  String toString() => 'EditorExportFailure(${kind.name}): $diagnostic';
}
