import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Model descriptors — swap URLs/hashes if you update model files.
class AiModelInfo {
  final String key;
  final String url;
  final String assetPath;
  final String sha256; // empty = skip hash check
  final int sizeBytes;

  const AiModelInfo({
    required this.key,
    required this.url,
    this.assetPath = '',
    required this.sha256,
    required this.sizeBytes,
  });
}

// ─── Model registry ──────────────────────────────────────────────────────────
// MediaPipe Selfie Segmenter (landscape, 256×144 in → 256×144 mask out)
// Input : [1, 144, 256, 3] float32, RGB 0-1
// Output: [1, 144, 256, 1] float32, sigmoid probability
const kModelSelfie = AiModelInfo(
  key: 'selfie_segmenter',
  url: 'https://storage.googleapis.com/mediapipe-models/'
      'image_segmenter/selfie_segmenter/float16/latest/'
      'selfie_segmenter.tflite',
  sha256: '',
  sizeBytes: 614000,
);

// MediaPipe Selfie Multiclass (256×256 → 6-class semantic mask)
// Classes: 0=bg, 1=hair, 2=body-skin, 3=face-skin, 4=clothes, 5=other
// Input : [1, 256, 256, 3] float32
// Output: [1, 256, 256, 6] float32 (softmax per pixel)
const kModelMulticlass = AiModelInfo(
  key: 'selfie_multiclass',
  url: 'https://storage.googleapis.com/mediapipe-models/'
      'image_segmenter/selfie_multiclass_256x256/float32/latest/'
      'selfie_multiclass_256x256.tflite',
  sha256: '',
  sizeBytes: 12600000,
);

// MiDaS Small v2.1 — monocular depth estimation (256×256 → depth map)
// Input : [1, 256, 256, 3] float32, RGB 0-1
// Output: [1, 256, 256]   float32, inverse depth (unnormalized)
const kModelDepth = AiModelInfo(
  key: 'midas_small',
  url: 'https://storage.googleapis.com/tfhub-lite-models/intel/'
      'lite-model/midas/v2_1_small/1/lite/2.tflite',
  sha256: '',
  sizeBytes: 15600000,
);

const kColorTransferModelId = 'direct_mvp_family_holdout_smooth_010_001_fp16';
const kColorTransferModelVersion = '2026-08-04-rc1';
const kColorTransferModelSha256 =
    '4a9439bd65be4d46e9ac4c3cae3d10e49487be42404a2af2beabcb2b415858f3';

// Direct MVP — style encoder + 17³ LUT decoder.
// Input : [1, 3, 256, 256] float32 NCHW, ImageNet normalized
// Output: [1, 17, 17, 17, 3] float32 (upsampled to 65³ in Dart)
// Size  : 36,264,272 bytes (float16 weights, float32 I/O)
const kModelColorTransfer = AiModelInfo(
  key: 'color_transfer',
  url: '',
  assetPath: 'assets/models/direct_mvp_color_transfer_fp16.tflite',
  sha256: kColorTransferModelSha256,
  sizeBytes: 36264272,
);

// ─── Download state ───────────────────────────────────────────────────────────

enum ModelStatus { notDownloaded, downloading, ready, error }

class ModelState {
  final ModelStatus status;
  final double progress; // 0.0–1.0
  final String? error;

  const ModelState({
    required this.status,
    this.progress = 0.0,
    this.error,
  });
}

// ─── Manager ─────────────────────────────────────────────────────────────────

class AiManager extends ChangeNotifier {
  AiManager._();
  static final AiManager instance = AiManager._();

  final _states = <String, ModelState>{};
  final _paths = <String, String>{};
  final _inFlight = <String, Future<String>>{};

  ModelState stateOf(String key) =>
      _states[key] ?? const ModelState(status: ModelStatus.notDownloaded);

  String? pathOf(String key) => _paths[key];

  bool get selfieReady => stateOf(kModelSelfie.key).status == ModelStatus.ready;
  bool get multiclassReady =>
      stateOf(kModelMulticlass.key).status == ModelStatus.ready;
  bool get depthReady => stateOf(kModelDepth.key).status == ModelStatus.ready;
  bool get colorTransferReady =>
      stateOf(kModelColorTransfer.key).status == ModelStatus.ready;

  /// Returns cached path if ready, otherwise downloads then returns path.
  /// Throws [UnsupportedError] if the model URL is empty (not yet deployed).
  Future<String> require(AiModelInfo info) {
    final active = _inFlight[info.key];
    if (active != null) return active;
    final future = _requireOnce(info);
    _inFlight[info.key] = future;
    return future.whenComplete(() => _inFlight.remove(info.key));
  }

  Future<String> _requireOnce(AiModelInfo info) async {
    if (_paths.containsKey(info.key)) return _paths[info.key]!;

    final cached = await _cachedPath(info);
    if (cached != null) {
      _paths[info.key] = cached;
      _setState(
          info.key, const ModelState(status: ModelStatus.ready, progress: 1.0));
      return cached;
    }

    if (info.assetPath.isNotEmpty) {
      return _installBundledAsset(info);
    }

    if (info.url.isEmpty) {
      _setState(
          info.key,
          const ModelState(
              status: ModelStatus.error, error: 'Model not yet deployed'));
      throw UnsupportedError(
          '${info.key}: model URL is empty — deploy model first');
    }

    return _download(info);
  }

  Future<void> preload(AiModelInfo info) async {
    if (stateOf(info.key).status == ModelStatus.ready) return;
    if (stateOf(info.key).status == ModelStatus.downloading) return;
    try {
      await require(info);
    } catch (error) {
      // Preloading is best-effort. The error state remains visible through
      // [stateOf], while a later explicit [require] can retry the download.
      debugPrint('AI model preload failed (${info.key}): $error');
    }
  }

  Future<String> _installBundledAsset(AiModelInfo info) async {
    _setState(
      info.key,
      const ModelState(status: ModelStatus.downloading, progress: 0),
    );
    final destination = File(await _modelPath(info));
    final temporary = File('${destination.path}.installing');
    try {
      final data = await rootBundle.load(info.assetPath);
      await destination.parent.create(recursive: true);
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await _verifyFile(info, temporary);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      _paths[info.key] = destination.path;
      _setState(
        info.key,
        const ModelState(status: ModelStatus.ready, progress: 1.0),
      );
      return destination.path;
    } catch (error) {
      if (await temporary.exists()) await temporary.delete();
      _setState(
        info.key,
        ModelState(status: ModelStatus.error, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<void> _verifyFile(AiModelInfo info, File file) async {
    if (info.sizeBytes > 0 && await file.length() != info.sizeBytes) {
      throw StateError('${info.key}: bundled model size mismatch');
    }
    if (info.sha256.isNotEmpty) {
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (hash != info.sha256) {
        throw StateError('${info.key}: bundled model SHA-256 mismatch');
      }
    }
  }

  @visibleForTesting
  void useLocalModelForTesting(AiModelInfo info, String path) {
    _paths[info.key] = path;
    _setState(
      info.key,
      const ModelState(status: ModelStatus.ready, progress: 1.0),
    );
  }

  @visibleForTesting
  void clearLocalModelForTesting(AiModelInfo info) {
    _paths.remove(info.key);
    _states.remove(info.key);
    notifyListeners();
  }

  // ── internals ──────────────────────────────────────────────────────────────

  Future<String?> _cachedPath(AiModelInfo info) async {
    final p = await _modelPath(info);
    final f = File(p);
    if (!await f.exists()) return null;
    if (info.sizeBytes > 0 && await f.length() != info.sizeBytes) {
      await f.delete();
      return null;
    }
    if (info.sha256.isNotEmpty) {
      final hash = (await sha256.bind(f.openRead()).first).toString();
      if (hash != info.sha256) {
        await f.delete();
        return null;
      }
    }
    return p;
  }

  Future<String> _download(AiModelInfo info) async {
    _setState(info.key,
        const ModelState(status: ModelStatus.downloading, progress: 0));

    try {
      final dest = await _modelPath(info);
      await File(dest).parent.create(recursive: true);

      final client = http.Client();
      final req = http.Request('GET', Uri.parse(info.url));
      final resp = await client.send(req);

      final total = resp.contentLength ?? info.sizeBytes;
      int received = 0;
      final sink = File(dest).openWrite();

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        final progress = total > 0 ? received / total : 0.0;
        _setState(info.key,
            ModelState(status: ModelStatus.downloading, progress: progress));
      }

      await sink.close();
      client.close();

      _paths[info.key] = dest;
      _setState(
          info.key, const ModelState(status: ModelStatus.ready, progress: 1.0));
      return dest;
    } catch (e) {
      _setState(
          info.key, ModelState(status: ModelStatus.error, error: e.toString()));
      rethrow;
    }
  }

  Future<String> _modelPath(AiModelInfo info) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/ai_models/${info.key}.tflite';
  }

  void _setState(String key, ModelState s) {
    _states[key] = s;
    notifyListeners();
  }
}

void unawaited(Future<void> f) => f.ignore();
