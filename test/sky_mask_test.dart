import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/sky_mask.dart';

img.Image _scene() {
  const w = 300;
  const h = 200;
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (y < 90) {
        // 푸른 하늘 그라데이션
        image.setPixelRgb(x, y, 100 + y ~/ 3, 150 + y ~/ 3, 235);
      } else {
        // 풀밭
        image.setPixelRgb(x, y, 60 + (x % 7), 120 + (y % 5), 50);
      }
    }
  }
  // 구름(흰색)
  for (var y = 20; y < 45; y++) {
    for (var x = 80; x < 150; x++) {
      image.setPixelRgb(x, y, 245, 245, 248);
    }
  }
  // 아래쪽의 파란 차: 하늘 색이지만 위쪽과 이어져 있지 않다
  for (var y = 140; y < 170; y++) {
    for (var x = 200; x < 260; x++) {
      image.setPixelRgb(x, y, 60, 90, 220);
    }
  }
  return image;
}

void main() {
  test('위쪽과 이어진 하늘만 찾고 같은 색의 차는 제외한다', () {
    final mask = detectSky(_scene());
    expect(mask.sample(0.2, 0.15), greaterThan(0.9), reason: '하늘');
    expect(mask.sample(0.4, 0.17), greaterThan(0.9), reason: '구름');
    expect(mask.sample(0.5, 0.8), lessThan(0.05), reason: '풀밭');
    expect(mask.sample(0.77, 0.77), lessThan(0.05), reason: '아래쪽 파란 차');
  });

  test('하늘만 보정되고 땅은 그대로다', () {
    final scene = _scene();
    final out = applySkyAdjust(
      scene,
      const SkyAdjust(brightness: -50, saturation: 40, warmth: -30),
    );
    final skyBefore = scene.getPixel(30, 20);
    final skyAfter = out.getPixel(30, 20);
    expect(skyAfter.r, lessThan(skyBefore.r), reason: '어두워짐');
    final groundBefore = scene.getPixel(150, 170);
    final groundAfter = out.getPixel(150, 170);
    expect(groundAfter.r, groundBefore.r);
    expect(groundAfter.g, groundBefore.g);
    final carBefore = scene.getPixel(230, 150);
    final carAfter = out.getPixel(230, 150);
    expect(carAfter.b, carBefore.b, reason: '차는 건드리지 않는다');
  });

  test('값이 모두 0이면 원본을 그대로 돌려준다', () {
    final scene = _scene();
    expect(identical(applySkyAdjust(scene, const SkyAdjust()), scene), isTrue);
  });

  test('영역 확인 모드는 하늘을 붉게 표시한다', () {
    final out = applySkyAdjust(_scene(), const SkyAdjust(), showMask: true);
    final p = out.getPixel(30, 20);
    expect(p.r, greaterThan(p.b));
  });

  test('하늘이 없는 사진은 바뀌지 않는다', () {
    final ground = img.Image(width: 120, height: 80);
    for (final p in ground) {
      p.setRgb(70, 120, 50);
    }
    expect(detectSky(ground).isEmpty, isTrue);
    expect(
      identical(
          applySkyAdjust(ground, const SkyAdjust(brightness: 50)), ground),
      isTrue,
    );
  });

  test('실제 사진에서 하늘 영역이 사진 전체로 번지지 않는다', () {
    for (final name in ['test/원본_1.jpg', 'test/원본_2.jpg']) {
      final photo = img.decodeImage(File(name).readAsBytesSync())!;
      final watch = Stopwatch()..start();
      final mask = detectSky(photo);
      watch.stop();
      final coverage =
          mask.data.where((v) => v > 0.5).length / mask.data.length;
      // ignore: avoid_print
      print('sky_detect_12mp_ms=${watch.elapsedMilliseconds} coverage=${coverage.toStringAsFixed(3)} $name');
      expect(coverage, lessThan(0.9));
    }
  });

  test('12MP 사진에 하늘 보정을 적용하는 시간', () {
    final photo =
        img.decodeImage(File('test/원본_1.jpg').readAsBytesSync())!;
    final watch = Stopwatch()..start();
    applySkyAdjust(photo, const SkyAdjust(brightness: -20, warmth: -20),
        mask: SkyMask(Float32List.fromList(List.filled(64 * 64, 1.0)), 64, 64));
    watch.stop();
    // ignore: avoid_print
    print('sky_apply_12mp_full_mask_ms=${watch.elapsedMilliseconds}');
  });
}
