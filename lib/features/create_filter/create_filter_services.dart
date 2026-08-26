import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../ai/ai_manager.dart';
import '../../core/error/error_handler.dart';
import '../../domain/models/filter_preset.dart';
import '../../domain/repositories/filter_repository.dart';
import '../../engine/lut_engine.dart';
import '../../engine/personal_filter_core.dart';

typedef CreateFilterProgressCallback = void Function(
  String stage,
  double progress,
);

class CreateFilterCancelledException implements Exception {
  const CreateFilterCancelledException();

  @override
  String toString() => 'Filter generation was cancelled.';
}

class CreateFilterWorkerException implements Exception {
  final String message;

  const CreateFilterWorkerException(this.message);

  @override
  String toString() => message;
}

class CreateFilterPreviewException implements Exception {
  const CreateFilterPreviewException();

  @override
  String toString() => 'Generated filter preview could not be validated.';
}

abstract class CreateFilterGenerator {
  Future<Map<String, dynamic>> generateStyle(
    List<String> styleImagePaths, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  });

  Future<Map<String, dynamic>> generatePair(
    String beforePath,
    String afterPath, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  });

  Future<void> cancel();
}

class _StyleWorkerArgs {
  final List<String> styleImagePaths;
  final String basePath;
  final String? neuralModelPath;
  final SendPort sendPort;

  const _StyleWorkerArgs(
    this.styleImagePaths,
    this.basePath,
    this.neuralModelPath,
    this.sendPort,
  );
}

class _PairWorkerArgs {
  final String beforePath;
  final String afterPath;
  final String basePath;
  final SendPort sendPort;

  const _PairWorkerArgs(
    this.beforePath,
    this.afterPath,
    this.basePath,
    this.sendPort,
  );
}

class _WorkerProgress {
  final String stage;
  final double progress;

  const _WorkerProgress(this.stage, this.progress);
}

Future<void> _styleWorker(_StyleWorkerArgs args) async {
  final result = await generateLutFromStyle(
    args.styleImagePaths,
    basePath: args.basePath,
    neuralModelPath: args.neuralModelPath,
    onProgress: (stage, progress) =>
        args.sendPort.send(_WorkerProgress(stage, progress)),
  );
  args.sendPort.send(result);
}

Future<void> _pairWorker(_PairWorkerArgs args) async {
  final result = await generateLutFromBeforeAfterPair(
    args.beforePath,
    args.afterPath,
    basePath: args.basePath,
    onProgress: (stage, progress) =>
        args.sendPort.send(_WorkerProgress(stage, progress)),
  );
  args.sendPort.send(result);
}

/// Runs filter generation in a worker isolate with one result/error/exit port.
///
/// Using the same receive port ensures the result message sent by the worker is
/// observed before its exit message. A timeout and explicit cancellation keep a
/// worker failure from leaving the creation screen in a permanent busy state.
class IsolateCreateFilterGenerator implements CreateFilterGenerator {
  final Duration timeout;

  IsolateCreateFilterGenerator({
    this.timeout = const Duration(seconds: 45),
  });

  Isolate? _activeIsolate;
  Completer<Map<String, dynamic>>? _activeCompleter;

  @override
  Future<Map<String, dynamic>> generateStyle(
    List<String> styleImagePaths, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) async {
    String? neuralModelPath;
    if (styleImagePaths.length == 1) {
      try {
        neuralModelPath = await AiManager.instance.require(kModelColorTransfer);
      } catch (error, stackTrace) {
        // The engine records the unavailable-model fallback in its recipe.
        ErrorLogger.log(
          'Color-transfer model unavailable; using algorithmic generation',
          error.runtimeType,
          stackTrace,
        );
      }
    }
    return _run(
      basePath: basePath,
      onProgress: onProgress,
      spawn: (port) => Isolate.spawn<_StyleWorkerArgs>(
        _styleWorker,
        _StyleWorkerArgs(
          styleImagePaths,
          basePath,
          neuralModelPath,
          port,
        ),
        onError: port,
        onExit: port,
        errorsAreFatal: true,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> generatePair(
    String beforePath,
    String afterPath, {
    required String basePath,
    required CreateFilterProgressCallback onProgress,
  }) {
    return _run(
      basePath: basePath,
      onProgress: onProgress,
      spawn: (port) => Isolate.spawn<_PairWorkerArgs>(
        _pairWorker,
        _PairWorkerArgs(beforePath, afterPath, basePath, port),
        onError: port,
        onExit: port,
        errorsAreFatal: true,
      ),
    );
  }

  Future<Map<String, dynamic>> _run({
    required String basePath,
    required CreateFilterProgressCallback onProgress,
    required Future<Isolate> Function(SendPort port) spawn,
  }) async {
    if (_activeCompleter != null) {
      throw StateError('A filter generation worker is already active.');
    }

    final existingFilterDirectories = await _filterDirectoryNames(basePath);
    final receivePort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();
    _activeCompleter = completer;

    late final StreamSubscription<dynamic> subscription;
    subscription = receivePort.listen((message) {
      if (message is _WorkerProgress) {
        onProgress(message.stage, message.progress);
        return;
      }
      if (message is Map) {
        if (!completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(message));
        }
        return;
      }
      if (message is List && message.length >= 2) {
        if (!completer.isCompleted) {
          completer.completeError(
            CreateFilterWorkerException(message.first.toString()),
            StackTrace.fromString(message[1].toString()),
          );
        }
        return;
      }
      if (message == null && !completer.isCompleted) {
        completer.completeError(
          const CreateFilterWorkerException(
            'Filter generation worker exited without a result.',
          ),
        );
      }
    });

    var producedResult = false;
    try {
      _activeIsolate = await spawn(receivePort.sendPort);
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'Filter generation exceeded ${timeout.inSeconds} seconds.',
            timeout,
          );
        },
      );
      producedResult = true;
      return result;
    } finally {
      _activeIsolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      receivePort.close();
      _activeIsolate = null;
      _activeCompleter = null;
      if (!producedResult) {
        await _deleteNewFilterDirectories(
          basePath,
          existingFilterDirectories,
        );
      }
    }
  }

  Future<Set<String>> _filterDirectoryNames(String basePath) async {
    final root = Directory('$basePath/filters');
    if (!await root.exists()) return <String>{};
    try {
      return (await root.list().where((entry) => entry is Directory).toList())
          .map((entry) => entry.path)
          .toSet();
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Generated-filter directory snapshot failed',
        error.runtimeType,
        stackTrace,
      );
      return <String>{};
    }
  }

  Future<void> _deleteNewFilterDirectories(
    String basePath,
    Set<String> existingDirectories,
  ) async {
    final root = Directory('$basePath/filters');
    if (!await root.exists()) return;
    try {
      await for (final entry in root.list()) {
        if (entry is Directory &&
            !existingDirectories.contains(entry.path) &&
            await entry.exists()) {
          await entry.delete(recursive: true);
        }
      }
    } catch (error, stackTrace) {
      // Worker failure cleanup is best-effort and never hides the root error.
      ErrorLogger.log(
        'Generated-filter worker cleanup was incomplete',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  @override
  Future<void> cancel() async {
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const CreateFilterCancelledException());
    }
    _activeIsolate?.kill(priority: Isolate.immediate);
  }
}

enum RecentPhotoLoadState { ready, limited, denied, empty, unavailable, error }

class RecentPhotoItem {
  final String assetId;
  final Uint8List thumbnailBytes;

  const RecentPhotoItem({
    required this.assetId,
    required this.thumbnailBytes,
  });
}

class RecentPhotoPage {
  final RecentPhotoLoadState state;
  final List<RecentPhotoItem> items;
  final int page;
  final bool hasMore;
  final int unavailableCount;
  final String? errorMessage;

  const RecentPhotoPage({
    required this.state,
    this.items = const [],
    this.page = 0,
    this.hasMore = false,
    this.unavailableCount = 0,
    this.errorMessage,
  });
}

abstract class RecentPhotoSource {
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30});

  /// Resolves the full local file only after the user chooses an asset.
  Future<String?> resolveOriginalPath(String assetId);
}

class PhotoManagerRecentPhotoSource implements RecentPhotoSource {
  final Map<String, AssetEntity> _assetsById = {};

  @override
  Future<RecentPhotoPage> loadRecent({int page = 0, int size = 30}) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        return RecentPhotoPage(
          state: RecentPhotoLoadState.denied,
          page: page,
        );
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        return RecentPhotoPage(
          state: RecentPhotoLoadState.empty,
          page: page,
        );
      }
      final assets =
          await albums.first.getAssetListPaged(page: page, size: size);
      for (final asset in assets) {
        _assetsById[asset.id] = asset;
      }
      final thumbnails = await Future.wait(
        assets.map(
          (asset) => asset.thumbnailDataWithSize(
            const ThumbnailSize.square(176),
            quality: 82,
          ),
        ),
      );
      final items = <RecentPhotoItem>[];
      var unavailableCount = 0;
      for (var index = 0; index < assets.length; index++) {
        final bytes = thumbnails[index];
        if (bytes == null || bytes.isEmpty) {
          unavailableCount++;
          continue;
        }
        items.add(
          RecentPhotoItem(
            assetId: assets[index].id,
            thumbnailBytes: bytes,
          ),
        );
      }
      return RecentPhotoPage(
        state: assets.isNotEmpty && items.isEmpty
            ? RecentPhotoLoadState.unavailable
            : items.isEmpty
                ? RecentPhotoLoadState.empty
                : permission.isLimited
                    ? RecentPhotoLoadState.limited
                    : RecentPhotoLoadState.ready,
        items: items,
        page: page,
        hasMore: assets.length == size,
        unavailableCount: unavailableCount,
      );
    } catch (error) {
      return RecentPhotoPage(
        state: RecentPhotoLoadState.error,
        page: page,
        errorMessage: error.toString(),
      );
    }
  }

  @override
  Future<String?> resolveOriginalPath(String assetId) async {
    final asset = _assetsById[assetId] ?? await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    _assetsById[assetId] = asset;
    return (await asset.file)?.path;
  }
}

abstract class CreateFilterPreviewRenderer {
  Future<String?> render(FilterPreset preset, String? sourcePath);
}

class FileCreateFilterPreviewRenderer implements CreateFilterPreviewRenderer {
  @override
  Future<String?> render(FilterPreset preset, String? sourcePath) async {
    try {
      if (sourcePath == null) return null;
      final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
      if (decoded == null) return null;
      final source = img.bakeOrientation(decoded);
      final lutBytes = await loadLutBytes(preset.lutPath);
      final preview = applyImagePipeline(
        image: source,
        params: preset.params,
        lutBytes: lutBytes,
        intensity: preset.defaultIntensity,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/filter_preview_${preset.id}.jpg');
      await file.writeAsBytes(img.encodeJpg(preview, quality: 88));
      return file.path;
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Generated-filter preview rendering failed',
        error.runtimeType,
        stackTrace,
      );
      return null;
    }
  }
}

class CommittedFilterResult {
  final FilterPreset preset;
  final String previewPath;

  const CommittedFilterResult({
    required this.preset,
    required this.previewPath,
  });
}

/// Validates the sample render before adding a generated preset to the index.
/// Any failure rolls back repository state and all generated temporary files.
class CreateFilterCommitTransaction {
  final FilterRepository repository;
  final CreateFilterPreviewRenderer previewRenderer;

  const CreateFilterCommitTransaction({
    required this.repository,
    required this.previewRenderer,
  });

  Future<CommittedFilterResult> commit({
    required FilterPreset preset,
    required String? sourcePath,
  }) async {
    String? previewPath;
    try {
      previewPath = await previewRenderer.render(preset, sourcePath);
      if (previewPath == null || !await File(previewPath).exists()) {
        throw const CreateFilterPreviewException();
      }
      await repository.savePreset(preset);
      return CommittedFilterResult(
        preset: preset,
        previewPath: previewPath,
      );
    } catch (error) {
      // Preserve the original commit failure after compensating cleanup.
      await rollback(preset, previewPath: previewPath);
      rethrow;
    }
  }

  Future<void> rollback(
    FilterPreset preset, {
    String? previewPath,
  }) async {
    try {
      await repository.deletePreset(preset.id);
    } catch (error, stackTrace) {
      // Continue with direct artifact cleanup even if repository rollback fails.
      ErrorLogger.log(
        'Generated-filter repository rollback failed',
        error.runtimeType,
        stackTrace,
      );
    }
    await deleteFileIfPresent(previewPath);
    try {
      final generatedDir = File(preset.lutPath).parent;
      if (await generatedDir.exists()) {
        await generatedDir.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      // Cleanup is best-effort; the repository has already been rolled back.
      ErrorLogger.log(
        'Generated-filter artifact cleanup failed',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  static Future<void> deleteFileIfPresent(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error, stackTrace) {
      // Temporary preview cleanup must not crash navigation.
      ErrorLogger.log(
        'Generated-filter temporary preview cleanup failed',
        error.runtimeType,
        stackTrace,
      );
    }
  }
}
