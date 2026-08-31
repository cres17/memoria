import 'package:memoria/features/editor/editor_resource_preparer.dart';
import 'package:memoria/core/l10n/strings.dart';

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
  permissionDenied,
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
        return S.get('export.input_decode');
      case EditorExportFailureKind.memoryPressure:
        return S.get('export.memory_pressure');
      case EditorExportFailureKind.nativeEncoding:
        return S.get('export.native_encoding');
      case EditorExportFailureKind.outputWrite:
        return S.get('export.output_write');
      case EditorExportFailureKind.outputValidation:
        return S.get('export.output_validation');
      case EditorExportFailureKind.permissionDenied:
        return S.get('export.permission_denied');
      case EditorExportFailureKind.workerTerminated:
        return S.get('export.worker_terminated');
      case EditorExportFailureKind.timeout:
        return S.get('export.timeout');
      case EditorExportFailureKind.resourcePreparation:
        return S.get('export.resource_preparation');
      case EditorExportFailureKind.unexpected:
        return S.get('export.unexpected');
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
