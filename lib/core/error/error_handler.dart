import 'dart:developer' as dev;

sealed class MemoriaException implements Exception {
  final String message;
  final Object? details;

  MemoriaException(this.message, [this.details]);

  @override
  String toString() => '$runtimeType: $message${details != null ? ' ($details)' : ''}';
}

class ImageProcessingException extends MemoriaException {
  ImageProcessingException(super.message, [super.details]);
}

class LutGenerationException extends MemoriaException {
  LutGenerationException(super.message, [super.details]);
}

class ModelInferenceException extends MemoriaException {
  ModelInferenceException(super.message, [super.details]);
}

class AssetIoException extends MemoriaException {
  AssetIoException(super.message, [super.details]);
}

class ErrorLogger {
  static final List<String> _logs = [];

  static void log(String message, [Object? error, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] $message${error != null ? ' | Error: $error' : ''}';
    _logs.add(logLine);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    dev.log(message, error: error, stackTrace: stackTrace, name: 'Memoria');
  }

  static List<String> get logs => List.unmodifiable(_logs);
  static void clear() => _logs.clear();
}
