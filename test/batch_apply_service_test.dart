import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/features/batch/batch_apply_service.dart';
import 'package:memoria/features/editor/editor_media_export_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _meanLuma(img.Image image) {
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < image.height; y += 16) {
    for (var x = 0; x < image.width; x += 16) {
      final p = image.getPixel(x, y);
      sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      n++;
    }
  }
  return sum / n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;
  late Directory saved;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    work = Directory.systemTemp.createTempSync('batch_work');
    saved = Directory.systemTemp.createTempSync('batch_saved');
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    saved.deleteSync(recursive: true);
  });

  BatchApplyService buildService() => BatchApplyService(
        coordinatorFactory: () => EditorMediaExportCoordinator(
          supportsWebp: () async => false,
          isIos: () => false,
          temporaryDirectory: () async => work,
          saveToGallery: (path) async {
            File(path).copySync('${saved.path}/${path.split('/').last}');
          },
        ),
      );

  test('실제 사진 2장에 같은 보정을 적용해 저장한다', () async {
    final sources = ['test/원본_1.jpg', 'test/원본_2.jpg'];
    const look = EditorLook(
      params: AdjustParams(exposure: 0.8, saturation: 30),
      portrait: PortraitParams(smooth: 80),
    );
    final events = <BatchItemStatus>[];
    final watch = Stopwatch()..start();

    final results = await buildService().run(
      paths: sources,
      look: look,
      preset: null,
      onItem: (index, result) => events.add(result.status),
    );
    watch.stop();
    // ignore: avoid_print
    print('batch_2_photos_12mp_ms=${watch.elapsedMilliseconds}');

    expect(results.map((r) => r.status),
        everyElement(BatchItemStatus.done));
    expect(events.where((e) => e == BatchItemStatus.running).length, 2);

    final outputs = saved.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(outputs.length, 2);
    for (var i = 0; i < 2; i++) {
      final before = img.decodeImage(File(sources[i]).readAsBytesSync())!;
      final after = img.decodeImage(outputs[i].readAsBytesSync())!;
      expect(after.width, before.width);
      expect(after.height, before.height);
      expect(_meanLuma(after), greaterThan(_meanLuma(before) + 3),
          reason: '노출을 올렸으므로 평균 밝기가 올라가야 한다');
    }
    // 임시 렌더 파일이 남지 않는다.
    expect(work.listSync(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('읽을 수 없는 파일은 실패로 기록하고 나머지는 계속 처리한다', () async {
    final bad = File('${work.path}/broken.jpg')..writeAsBytesSync([1, 2, 3]);
    final results = await buildService().run(
      paths: [bad.path, 'test/원본_2.jpg'],
      look: const EditorLook(params: AdjustParams(exposure: 0.5)),
      preset: null,
      onItem: (_, __) {},
    );
    expect(results[0].status, BatchItemStatus.failed);
    expect(results[1].status, BatchItemStatus.done);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('중단하면 남은 사진은 취소로 표시된다', () async {
    final service = buildService();
    final future = service.run(
      paths: ['test/원본_1.jpg', 'test/원본_2.jpg', 'test/원본_1.jpg'],
      look: const EditorLook(params: AdjustParams(exposure: 0.5)),
      preset: null,
      onItem: (index, result) {
        if (index == 0 && result.status == BatchItemStatus.done) {
          service.cancel();
        }
      },
    );
    final results = await future;
    expect(results.first.status, BatchItemStatus.done);
    expect(results.skip(1).map((r) => r.status),
        everyElement(BatchItemStatus.cancelled));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('일괄 적용 recipe에는 인물 보정이 들어가지 않는다', () {
    final recipe = BatchApplyService.buildRecipe(
      const EditorLook(
        params: AdjustParams(exposure: 0.3),
        portrait: PortraitParams(smooth: 90, bokeh: 50),
      ),
      null,
      null,
    );
    expect(recipe.portrait.isZero, isTrue);
    expect(recipe.adjustParams.exposure, 0.3);
  });
}
