import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

sealed class MemoriaException implements Exception {
  final String message;
  final Object? details;

  MemoriaException(this.message, [this.details]);

  @override
  String toString() =>
      '$runtimeType: $message${details != null ? ' ($details)' : ''}';
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
  static File? _file;
  static Future<void> _writeChain = Future<void>.value();
  static int _writesSinceCompaction = 0;

  static Future<void> initialize({File? file}) async {
    try {
      _file = file ??
          File(
            '${(await getApplicationSupportDirectory()).path}/diagnostics/memoria.log',
          );
      await _file!.parent.create(recursive: true);
      _logs.clear();
      if (await _file!.exists()) {
        final existing = await _file!.readAsLines();
        _logs
          ..clear()
          ..addAll(existing.length > 500
              ? existing.sublist(existing.length - 500)
              : existing);
        if (existing.length > 500) await _compact();
      }
    } catch (error, stackTrace) {
      _file = null;
      dev.log(
        'Persistent diagnostics unavailable',
        error: error,
        stackTrace: stackTrace,
        name: 'Memoria',
      );
    }
  }

  static void log(String message, [Object? error, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine =
        '[$timestamp] $message${error != null ? ' | Error: $error' : ''}';
    _logs.add(logLine);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    dev.log(message, error: error, stackTrace: stackTrace, name: 'Memoria');
    final file = _file;
    if (file == null) return;
    _writeChain = _writeChain.then((_) async {
      _writesSinceCompaction++;
      if (_writesSinceCompaction >= 100) {
        await _compact();
      } else {
        await file.writeAsString(
          '$logLine\n',
          mode: FileMode.append,
          flush: true,
        );
      }
    }).catchError((Object writeError, StackTrace writeStack) {
      dev.log(
        'Failed to persist diagnostics',
        error: writeError,
        stackTrace: writeStack,
        name: 'Memoria',
      );
    });
  }

  static List<String> get logs => List.unmodifiable(_logs);

  static void clear() {
    _logs.clear();
    final file = _file;
    if (file == null) return;
    _writeChain = _writeChain.then((_) => file.writeAsString('', flush: true));
  }

  static Future<void> flush() => _writeChain;

  static Future<void> _compact() async {
    final file = _file;
    if (file == null) return;
    await file.writeAsString(
      _logs.isEmpty ? '' : '${_logs.join('\n')}\n',
      flush: true,
    );
    _writesSinceCompaction = 0;
  }
}
