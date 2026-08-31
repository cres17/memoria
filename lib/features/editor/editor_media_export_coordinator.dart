import 'dart:async';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:memoria/core/error/error_handler.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/core/services/media_permission_service.dart';
import 'package:memoria/engine/engine_channel.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Stable inputs for one output-resolution attempt.
///
/// The page prepares rendering resources from this value; this coordinator owns
/// all temporary paths, native codec work, publishing, retries, and cleanup.
class EditorMediaExportAttempt {
  final String outputPath;
  final ExportFormat renderFormat;
  final int quality;
  final int? maxDimension;

  const EditorMediaExportAttempt({
    required this.outputPath,
    required this.renderFormat,
    required this.quality,
    required this.maxDimension,
  });
}

class EditorMediaExportResult {
  final bool cancelled;
  final bool shared;
  final ExportFormat format;

  const EditorMediaExportResult._({
    required this.cancelled,
    required this.shared,
    required this.format,
  });

  const EditorMediaExportResult.completed({
    required bool shared,
    required ExportFormat format,
  }) : this._(cancelled: false, shared: shared, format: format);

  const EditorMediaExportResult.cancelled({required ExportFormat format})
      : this._(cancelled: true, shared: false, format: format);
}

typedef EditorExportRequestBuilder = Future<EditorExportRequest> Function(
  EditorMediaExportAttempt attempt,
);

typedef EditorExportRunner = Future<EditorExportJobResult> Function(
  EditorExportRequest request, {
  void Function(double progress)? onProgress,
});

typedef EditorExportSettingsLoader = Future<ExportSettings> Function(
  bool allowWebp,
);

/// Owns the media side of an editor export after the page has prepared pixels.
///
/// It deliberately does not depend on widget state. This keeps temporary file
/// lifecycle, codec validation, publish behavior, retry policy, and cancellation
/// testable without an `EditorPage` widget test.
class EditorMediaExportCoordinator {
  late final EditorExportService _exportService;
  late final EditorExportRunner _render;
  final EditorExportSettingsLoader _loadSettings;
  final Future<bool> Function() _supportsWebp;
  final Future<bool> Function({
    required String inputPath,
    required String outputPath,
    required int quality,
  }) _encodeWebp;
  final bool Function() _isIos;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(String path) _saveToGallery;
  final Future<bool> Function() _ensureGalleryWriteAccess;
  final Future<void> Function(String path) _share;
  final void Function(String path) _scheduleSharedCleanup;

  bool _exporting = false;
  bool _cancelled = false;

  EditorMediaExportCoordinator({
    EditorExportService? exportService,
    EditorExportRunner? render,
    EditorExportSettingsLoader? loadSettings,
    Future<bool> Function()? supportsWebp,
    Future<bool> Function({
      required String inputPath,
      required String outputPath,
      required int quality,
    })? encodeWebp,
    bool Function()? isIos,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(String path)? saveToGallery,
    Future<bool> Function()? ensureGalleryWriteAccess,
    Future<void> Function(String path)? share,
    void Function(String path)? scheduleSharedCleanup,
  })  : _loadSettings = loadSettings ??
            ((allowWebp) => ExportPreferences.load(allowWebp: allowWebp)),
        _supportsWebp = supportsWebp ?? EngineChannel.supportsWebPEncoding,
        _encodeWebp = encodeWebp ?? EngineChannel.encodeWebP,
        _isIos = isIos ?? (() => Platform.isIOS),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _saveToGallery = saveToGallery ?? Gal.putImage,
        _ensureGalleryWriteAccess = ensureGalleryWriteAccess ??
            (saveToGallery == null
                ? MediaPermissionService.ensurePhotoLibraryWriteAccess
                : () async => true),
        _share = share ??
            ((path) async {
              await Share.shareXFiles([XFile(path)]);
            }),
        _scheduleSharedCleanup =
            scheduleSharedCleanup ?? _scheduleDefaultSharedCleanup {
    _exportService = exportService ?? EditorExportService();
    _render = render ?? _exportService.render;
  }

  bool get isExporting => _exporting;

  Future<EditorMediaExportResult> export({
    required bool share,
    required EditorExportRequestBuilder buildRequest,
    required void Function(double progress) onProgress,
    void Function(int maxDimension)? onRetryAtLowerResolution,
  }) async {
    if (_exporting) {
      throw StateError('An editor media export is already running');
    }
    _exporting = true;
    _cancelled = false;
    try {
      final supportsWebp = _isIos() && await _supportsWebp();
      final settings = await _loadSettings(supportsWebp);
      final format = settings.format;
      const attempts = <int?>[null, 4096, 2048];

      for (var attemptIndex = 0;
          attemptIndex < attempts.length;
          attemptIndex++) {
        if (_cancelled) {
          return EditorMediaExportResult.cancelled(format: format);
        }
        final finalPath = await _newOutputPath(format);
        final intermediatePath = format == ExportFormat.webp
            ? '${finalPath.substring(0, finalPath.length - format.extension.length)}render.png'
            : null;
        var preserveFinalFile = false;
        try {
          final renderPath = intermediatePath ?? finalPath;
          final request = await buildRequest(EditorMediaExportAttempt(
            outputPath: renderPath,
            renderFormat:
                format == ExportFormat.webp ? ExportFormat.png : format,
            quality: settings.quality,
            maxDimension: attempts[attemptIndex],
          ));
          if (_cancelled) {
            return EditorMediaExportResult.cancelled(format: format);
          }
          final jobResult = await _render(request, onProgress: onProgress);
          if (_cancelled || jobResult == EditorExportJobResult.cancelled) {
            return EditorMediaExportResult.cancelled(format: format);
          }

          if (format == ExportFormat.webp) {
            final encoded = await _encodeWebp(
              inputPath: renderPath,
              outputPath: finalPath,
              quality: settings.quality,
            );
            if (!encoded) {
              throw const EditorExportFailure(
                EditorExportFailureKind.nativeEncoding,
                'Native WebP encoder returned false',
              );
            }
          }

          if (_cancelled) {
            return EditorMediaExportResult.cancelled(format: format);
          }
          await _validateOutput(finalPath, format);

          if (share) {
            await _share(finalPath);
            preserveFinalFile = true;
            _scheduleSharedCleanup(finalPath);
          } else {
            final granted = await _ensureGalleryWriteAccess();
            if (!granted) {
              throw const EditorExportFailure(
                EditorExportFailureKind.permissionDenied,
                'Photo-library add-only access was denied',
              );
            }
            await _saveToGallery(finalPath);
          }
          return EditorMediaExportResult.completed(
              shared: share, format: format);
        } catch (error) {
          final failure = EditorExportFailure.fromError(error);
          if (failure.canRetryAtLowerResolution &&
              attemptIndex < attempts.length - 1) {
            final nextDimension = attempts[attemptIndex + 1]!;
            onRetryAtLowerResolution?.call(nextDimension);
            continue;
          }
          throw failure;
        } finally {
          if (!preserveFinalFile) {
            await _deleteIfPresent(finalPath);
          }
          if (intermediatePath != null) {
            await _deleteIfPresent(intermediatePath);
          }
        }
      }

      throw const EditorExportFailure(
        EditorExportFailureKind.unexpected,
        'Export exhausted all resolution attempts',
      );
    } finally {
      _exporting = false;
    }
  }

  /// Requests cancellation and waits until the worker has released resources.
  Future<void> cancel() async {
    _cancelled = true;
    await _exportService.cancel();
  }

  Future<String> _newOutputPath(ExportFormat format) async {
    final directory = await _temporaryDirectory();
    final id = DateTime.now().microsecondsSinceEpoch;
    return '${directory.path}/memoria_$id.${format.extension}';
  }

  Future<void> _validateOutput(String path, ExportFormat format) async {
    final bytes = await File(path).readAsBytes();
    if (!ExportEncoder.matchesSignature(format, bytes)) {
      throw EditorExportFailure(
        EditorExportFailureKind.outputValidation,
        '${format.name.toUpperCase()} signature validation failed',
      );
    }
  }

  static Future<void> _deleteIfPresent(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static void _scheduleDefaultSharedCleanup(String path) {
    unawaited(Future<void>.delayed(const Duration(minutes: 5), () async {
      try {
        await _deleteIfPresent(path);
      } catch (error, stackTrace) {
        ErrorLogger.log(
          'Deferred shared-export cleanup failed',
          error.runtimeType,
          stackTrace,
        );
      }
    }));
  }
}
