import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/raw_import.dart';

/// 바깥 JPEG의 APP1(EXIF) 안에 작은 썸네일 JPEG가 중첩된 실제 카메라 파일 구조를 흉내 낸다.
Uint8List _jpegWithNestedThumbnail(img.Image main, img.Image thumb) {
  final mainBytes = img.encodeJpg(main, quality: 90);
  final thumbBytes = img.encodeJpg(thumb, quality: 80);
  final exif = <int>[
    ...'Exif'.codeUnits,
    0,
    0,
    ...thumbBytes,
  ];
  final segmentLength = exif.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8,
    0xFF, 0xE1, (segmentLength >> 8) & 0xFF, segmentLength & 0xFF,
    ...exif,
    ...mainBytes.sublist(2),
  ]);
}

img.Image _photo(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return image;
}

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('raw_import'));
  tearDown(() => out.deleteSync(recursive: true));

  Uint8List fakeRaw(Uint8List embedded) => Uint8List.fromList([
        // TIFF 헤더와 센서 데이터 자리(JPEG처럼 보이지 않는 바이트)
        0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
        ...List<int>.generate(5000, (i) => (i * 7) % 200),
        ...embedded,
        ...List<int>.filled(300, 0),
      ]);

  test('확장자로 RAW를 구분한다', () {
    expect(RawImport.isRawPath('/a/b/IMG_0001.DNG'), isTrue);
    expect(RawImport.isRawPath('/a/b/x.cr2'), isTrue);
    expect(RawImport.isRawPath('/a/b/x.jpg'), isFalse);
    expect(RawImport.isRawPath('/a/b/noext'), isFalse);
  });

  test('RAW가 아니면 경로를 그대로 쓴다', () async {
    final result = await RawImport.prepare('/a/b/x.jpg', outputDirectory: out);
    expect(result.source, RawImportSource.notRaw);
    expect(result.path, '/a/b/x.jpg');
  });

  test('중첩된 썸네일이 있어도 바깥 큰 JPEG를 통째로 꺼낸다', () {
    final embedded = _jpegWithNestedThumbnail(_photo(640, 480), _photo(64, 48));
    final extracted = RawImport.extractLargestJpeg(fakeRaw(embedded));

    expect(extracted, isNotNull);
    expect(extracted!.length, embedded.length);
    final decoded = img.decodeJpg(extracted)!;
    expect(decoded.width, 640);
    expect(decoded.height, 480);
  });

  test('네이티브 현상이 없으면 내장 미리보기로 열고 알려 준다', () async {
    final embedded = _jpegWithNestedThumbnail(_photo(320, 200), _photo(32, 20));
    final rawFile = File('${out.path}/sample.dng')
      ..writeAsBytesSync(fakeRaw(embedded));

    final result = await RawImport.prepare(
      rawFile.path,
      outputDirectory: out,
      nativeDecoder: ({required inputPath, required outputPath}) async => null,
    );

    expect(result.source, RawImportSource.embeddedPreview);
    expect(result.isPreviewOnly, isTrue);
    expect(result.width, 320);
    expect(img.decodeJpg(File(result.path).readAsBytesSync())!.height, 200);
  });

  test('네이티브 현상이 성공하면 그 결과를 쓴다', () async {
    final rawFile = File('${out.path}/sample.dng')
      ..writeAsBytesSync(fakeRaw(Uint8List(0)));

    final result = await RawImport.prepare(
      rawFile.path,
      outputDirectory: out,
      nativeDecoder: ({required inputPath, required outputPath}) async {
        File(outputPath).writeAsBytesSync(img.encodeJpg(_photo(40, 30)));
        return {'path': outputPath, 'width': 4032, 'height': 3024};
      },
    );

    expect(result.source, RawImportSource.developed);
    expect(result.width, 4032);
  });

  test('열 이미지가 없는 RAW는 안내 예외를 던진다', () async {
    final rawFile = File('${out.path}/empty.dng')
      ..writeAsBytesSync(fakeRaw(Uint8List(0)));
    expect(
      () => RawImport.prepare(
        rawFile.path,
        outputDirectory: out,
        nativeDecoder: ({required inputPath, required outputPath}) async =>
            null,
      ),
      throwsA(isA<RawImportException>()),
    );
  });

  test('실제 사진 JPEG 12MP에서 추출 속도', () {
    final bytes = File('test/원본_1.jpg').readAsBytesSync();
    final blob = Uint8List.fromList([
      ...List<int>.filled(20 * 1024 * 1024, 3),
      ...bytes,
    ]);
    final watch = Stopwatch()..start();
    final extracted = RawImport.extractLargestJpeg(blob);
    watch.stop();
    // ignore: avoid_print
    print('raw_extract_24mb_ms=${watch.elapsedMilliseconds}');
    expect(extracted!.length, bytes.length);
  });
}
