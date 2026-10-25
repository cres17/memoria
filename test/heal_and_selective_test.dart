import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/inpainting.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';

img.Image _gradient({int w = 400, int h = 300}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, 60 + (x * 120 ~/ w), 90 + (y * 100 ~/ h), 140);
    }
  }
  return image;
}

void _paintSpot(img.Image image, int cx, int cy, int r) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
        image.setPixelRgb(x, y, 10, 10, 10);
      }
    }
  }
}

double _meanError(img.Image a, img.Image b, int cx, int cy, int r) {
  var sum = 0.0;
  var n = 0;
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      sum += ((pa.r - pb.r).abs() + (pa.g - pb.g).abs() + (pa.b - pb.b).abs()) /
          3;
      n++;
    }
  }
  return sum / n;
}

void main() {
  test('지우개는 잡티를 주변과 이어지게 채우고 원본은 바꾸지 않는다', () {
    final clean = _gradient();
    final dirty = img.Image.from(clean);
    _paintSpot(dirty, 200, 150, 10);
    final before = dirty.getPixel(200, 150).r;

    final healed = applyHealSpots(
      dirty,
      const [HealSpot(x: 200 / 399, y: 150 / 299, radius: 12 / 300)],
    );

    final errorBefore = _meanError(dirty, clean, 200, 150, 10);
    final errorAfter = _meanError(healed, clean, 200, 150, 10);
    expect(errorBefore, greaterThan(60));
    expect(errorAfter, lessThan(8), reason: '채운 뒤 원래 배경과 가까워야 한다');
    expect(dirty.getPixel(200, 150).r, before, reason: '입력 이미지 불변');
  });

  test('사진 가장자리 획도 예외 없이 처리된다', () {
    final image = _gradient();
    final healed = applyHealSpots(image, const [
      HealSpot(x: 0, y: 0, radius: 0.05),
      HealSpot(x: 1, y: 1, radius: 0.05),
      HealSpot(x: 0.5, y: 0.5, radius: 0.9),
    ]);
    expect(healed.width, image.width);
  });

  test('12MP 사진의 지우개 1회 처리 시간', () {
    final image = _gradient(w: 4000, h: 3000);
    _paintSpot(image, 2000, 1500, 40);
    final watch = Stopwatch()..start();
    applyHealSpots(
      image,
      const [HealSpot(x: 0.5, y: 0.5, radius: 0.02)],
    );
    watch.stop();
    // ignore: avoid_print
    print('heal_12mp_ms=${watch.elapsedMilliseconds}');
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });

  test('부분 보정 지점이 여러 개면 모두 적용된다', () {
    final image = img.Image(width: 200, height: 100);
    for (final p in image) {
      p.setRgb(100, 100, 100);
    }
    final out = applySelectiveAdjust(image, const [
      LocalSelectivePoint(
          x: 0.2, y: 0.5, brightness: 80, contrast: 0, saturation: 0, radius: 0.2),
      LocalSelectivePoint(
          x: 0.8, y: 0.5, brightness: -80, contrast: 0, saturation: 0, radius: 0.2),
    ]);
    expect(out.getPixel(40, 50).r, greaterThan(100));
    expect(out.getPixel(160, 50).r, lessThan(100));
    expect(out.getPixel(100, 50).r, closeTo(100, 3));
  });

  test('추가 지점·지우개 획이 기록 JSON과 렌더 recipe로 보존된다', () {
    final state = EditorEditState()
      ..selectiveActive = true
      ..selectiveExtras.add(const SelectivePointState(
          x: 0.1, y: 0.2, brightness: 30, contrast: 0, saturation: 5, radius: 0.25))
      ..healStrokes.add(const HealHistoryStroke(x: 0.3, y: 0.4, radius: 0.02));
    final snapshot = state.toSnapshot(localSubTabName: 'tiltShift');

    final restored = EditorEffectState.fromJson(snapshot.effects.toJson());
    expect(restored.selectiveExtras.single.brightness, 30);
    expect(restored.healStrokes.single.y, 0.4);

    final other = EditorEditState()..restore(snapshot, resolvedPreset: null);
    expect(other.selectiveExtras.length, 1);
    expect(other.healStrokes.length, 1);

    final recipe = snapshot.toRenderRecipe(lutBytes: null, cropAspectRatio: null);
    expect(recipe.selectiveExtras.single.x, 0.1);
    expect(recipe.healStrokes.single.radius, 0.02);
  });

  test('예전 기록(추가 필드 없음)도 읽힌다', () {
    final restored = EditorEffectState.fromJson({'selectiveActive': true});
    expect(restored.selectiveExtras, isEmpty);
    expect(restored.healStrokes, isEmpty);
  });

  test('하늘 보정 값이 기록 JSON·상태 복원·렌더 recipe로 보존된다', () {
    final state = EditorEditState()
      ..skyBrightness = -30
      ..skySaturation = 20
      ..skyWarmth = 45;
    final snapshot = state.toSnapshot(localSubTabName: 'tiltShift');

    final restored = EditorEffectState.fromJson(snapshot.effects.toJson());
    expect(restored.skyBrightness, -30);
    expect(restored.skySaturation, 20);
    expect(restored.skyWarmth, 45);

    final other = EditorEditState()..restore(snapshot, resolvedPreset: null);
    expect(other.skyWarmth, 45);

    final recipe =
        snapshot.toRenderRecipe(lutBytes: null, cropAspectRatio: null);
    expect(recipe.sky.isNeutral, isFalse);
    expect(recipe.sky.brightness, -30);
    expect(recipe.skyShowMask, isFalse);

    final preview = snapshot.toRenderRecipe(
        lutBytes: null, cropAspectRatio: null, skyShowMask: true);
    expect(preview.skyShowMask, isTrue);
  });

  test('하늘 값이 없는 예전 기록은 보정 없음으로 읽힌다', () {
    final restored = EditorEffectState.fromJson({'selectiveActive': true});
    expect(restored.skyBrightness, 0);
    final recipe = EditorEditState()
        .toSnapshot(localSubTabName: 'tiltShift')
        .toRenderRecipe(lutBytes: null, cropAspectRatio: null);
    expect(recipe.sky.isNeutral, isTrue);
  });
}
