import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/engine/engine_channel.dart';
import 'package:path_provider/path_provider.dart';

enum RawImportSource {
  /// 사진이 RAW가 아니라 그대로 쓴다.
  notRaw,

  /// 플랫폼의 RAW 현상(iOS Core Image)으로 전체 해상도를 만들었다.
  developed,

  /// 파일에 들어 있는 미리보기 JPEG만 꺼냈다. 해상도가 낮을 수 있다.
  embeddedPreview,
}

class RawImportResult {
  final String path;
  final RawImportSource source;
  final int? width;
  final int? height;

  const RawImportResult(this.path, this.source, {this.width, this.height});

  bool get isPreviewOnly => source == RawImportSource.embeddedPreview;
}

class RawImportException implements Exception {
  final String message;

  const RawImportException(this.message);

  @override
  String toString() => message;
}

typedef NativeRawDecoder = Future<Map<String, dynamic>?> Function({
  required String inputPath,
  required String outputPath,
});

/// 카메라 RAW(DNG 등)를 편집 화면이 열 수 있는 JPEG로 바꾼다.
///
/// 1순위는 플랫폼 RAW 현상이다. 지원하지 않으면 파일 안의 가장 큰 미리보기
/// JPEG를 꺼내 쓴다(센서 원본이 아니라서 보정 여유와 해상도가 줄어든다).
class RawImport {
  RawImport._();

  static const Set<String> rawExtensions = {
    'dng', 'cr2', 'cr3', 'nef', 'nrw', 'arw', 'sr2', 'raf', 'orf', 'rw2',
    'pef', 'srw',
  };

  static bool isRawPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return rawExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  static Future<RawImportResult> prepare(
    String path, {
    Directory? outputDirectory,
    NativeRawDecoder? nativeDecoder,
  }) async {
    if (!isRawPath(path)) return RawImportResult(path, RawImportSource.notRaw);

    final directory = outputDirectory ?? await getTemporaryDirectory();
    final id = DateTime.now().microsecondsSinceEpoch;
    final outputPath = '${directory.path}/memoria_raw_$id.jpg';

    final decode = nativeDecoder ?? EngineChannel.decodeRaw;
    final native = await decode(inputPath: path, outputPath: outputPath);
    if (native != null && await File(outputPath).exists()) {
      return RawImportResult(
        outputPath,
        RawImportSource.developed,
        width: (native['width'] as num?)?.toInt(),
        height: (native['height'] as num?)?.toInt(),
      );
    }

    final bytes = await File(path).readAsBytes();
    final preview = extractLargestJpeg(bytes);
    if (preview == null) {
      throw const RawImportException('이 RAW 파일에서 열 수 있는 이미지를 찾지 못했어요.');
    }
    await File(outputPath).writeAsBytes(preview, flush: true);
    final info = img.JpegDecoder().startDecode(preview);
    return RawImportResult(
      outputPath,
      RawImportSource.embeddedPreview,
      width: info?.width,
      height: info?.height,
    );
  }

  /// 파일 안에 들어 있는 JPEG 중 가장 큰 것을 돌려준다. 없으면 null.
  ///
  /// JPEG 세그먼트를 따라가 정확한 끝(EOI)을 찾으므로, EXIF 안에 작은 썸네일
  /// JPEG가 중첩되어 있어도 바깥 JPEG를 자르지 않는다.
  static Uint8List? extractLargestJpeg(Uint8List bytes) {
    Uint8List? best;
    var i = 0;
    while (i < bytes.length - 3) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
        final end = _jpegEnd(bytes, i);
        if (end > i) {
          final length = end - i;
          if (best == null || length > best.length) {
            final candidate = Uint8List.sublistView(bytes, i, end);
            if (img.JpegDecoder().isValidFile(candidate)) {
              best = candidate;
            }
          }
          i = end;
          continue;
        }
      }
      i++;
    }
    return best == null ? null : Uint8List.fromList(best);
  }

  /// [start]의 SOI부터 이어지는 JPEG의 마지막 바이트 다음 위치. 실패하면 -1.
  static int _jpegEnd(Uint8List bytes, int start) {
    var p = start + 2;
    while (p + 2 <= bytes.length) {
      if (bytes[p] != 0xFF) return -1;
      var marker = bytes[p + 1];
      while (marker == 0xFF && p + 2 < bytes.length) {
        p++;
        marker = bytes[p + 1];
      }
      if (marker == 0xD9) return p + 2;
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        p += 2;
        continue;
      }
      if (p + 4 > bytes.length) return -1;
      final length = (bytes[p + 2] << 8) | bytes[p + 3];
      if (length < 2) return -1;
      p += 2 + length;
      if (marker == 0xDA) {
        // 엔트로피 부호화 데이터: FF00과 RSTn은 건너뛰고 다음 마커까지 간다.
        while (p + 1 < bytes.length) {
          if (bytes[p] == 0xFF) {
            final next = bytes[p + 1];
            if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
              p += 2;
              continue;
            }
            break;
          }
          p++;
        }
      }
    }
    return -1;
  }
}
