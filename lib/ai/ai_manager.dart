import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Model descriptors — swap URLs/hashes if you update model files.
class AiModelInfo {
  final String key;
  final String url;
  final String sha256; // empty = skip hash check
  final int sizeBytes;

  const AiModelInfo({
    required this.key,
    required this.url,
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

// Neural Color Transfer — MobileNetV3-Small + Progressive LUT Decoder
// Input : [1, 256, 256, 3] float32, ImageNet normalized
// Output: [1, 5, 5, 5, 3]  float32, 5³ LUT (upsampled to 65³ in Dart)
// Size  : ~18MB (fp16 quantized TFLite)
const kModelColorTransfer = AiModelInfo(
  key: 'color_transfer',
  // URL은 ml_pipeline/7_export_model.py 실행 후 생성된 파일을 배포한 뒤 채운다.
  url: '',
  sha256: '',
  sizeBytes: 18000000,
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
  final _paths  = <String, String>{};

  ModelState stateOf(String key) =>
      _states[key] ?? const ModelState(status: ModelStatus.notDownloaded);

  String? pathOf(String key) => _paths[key];

  bool get selfieReady          => stateOf(kModelSelfie.key).status == ModelStatus.ready;
  bool get multiclassReady      => stateOf(kModelMulticlass.key).status == ModelStatus.ready;
  bool get depthReady           => stateOf(kModelDepth.key).status == ModelStatus.ready;
  bool get colorTransferReady   => stateOf(kModelColorTransfer.key).status == ModelStatus.ready;

  /// Returns cached path if ready, otherwise downloads then returns path.
  /// Throws [UnsupportedError] if the model URL is empty (not yet deployed).
  Future<String> require(AiModelInfo info) async {
    if (_paths.containsKey(info.key)) return _paths[info.key]!;

    final cached = await _cachedPath(info);
    if (cached != null) {
      _paths[info.key] = cached;
      _setState(info.key, const ModelState(status: ModelStatus.ready, progress: 1.0));
      return cached;
    }

    if (info.url.isEmpty) {
      _setState(info.key, const ModelState(
          status: ModelStatus.error, error: 'Model not yet deployed'));
      throw UnsupportedError('${info.key}: model URL is empty — deploy model first');
    }

    return _download(info);
  }

  Future<void> preload(AiModelInfo info) async {
    if (stateOf(info.key).status == ModelStatus.ready) return;
    if (stateOf(info.key).status == ModelStatus.downloading) return;
    unawaited(require(info));
  }

  // ── internals ──────────────────────────────────────────────────────────────

  Future<String?> _cachedPath(AiModelInfo info) async {
    final p = await _modelPath(info);
    final f = File(p);
    if (!await f.exists()) return null;
    if (info.sizeBytes > 0 && await f.length() < info.sizeBytes * 0.9) {
      await f.delete();
      return null;
    }
    if (info.sha256.isNotEmpty) {
      final bytes = await f.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      if (hash != info.sha256) {
        await f.delete();
        return null;
      }
    }
    return p;
  }

  Future<String> _download(AiModelInfo info) async {
    _setState(info.key, const ModelState(status: ModelStatus.downloading, progress: 0));

    try {
      final dest = await _modelPath(info);
      await File(dest).parent.create(recursive: true);

      final client = http.Client();
      final req    = http.Request('GET', Uri.parse(info.url));
      final resp   = await client.send(req);

      final total  = resp.contentLength ?? info.sizeBytes;
      int received = 0;
      final sink   = File(dest).openWrite();

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        final progress = total > 0 ? received / total : 0.0;
        _setState(info.key, ModelState(
            status: ModelStatus.downloading, progress: progress));
      }

      await sink.close();
      client.close();

      _paths[info.key] = dest;
      _setState(info.key, const ModelState(status: ModelStatus.ready, progress: 1.0));
      return dest;
    } catch (e) {
      _setState(info.key, ModelState(status: ModelStatus.error, error: e.toString()));
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
