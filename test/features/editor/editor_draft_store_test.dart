import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/editor_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips a matching draft without exposing its storage key',
      () async {
    final store = EditorDraftStore();
    const imagePath = '/private/photo.jpg';
    final draft = {
      'imagePath': imagePath,
      'initialPresetId': 'fuji-classic',
      'intensity': 0.75,
    };

    await store.save(imagePath: imagePath, draft: draft);
    final restored = await store.read(
      imagePath: imagePath,
      initialPresetId: 'fuji-classic',
    );

    expect(restored, draft);
  });

  test('ignores a draft from another route context', () async {
    final store = EditorDraftStore();
    await store.save(
      imagePath: '/private/photo.jpg',
      draft: {
        'imagePath': '/private/photo.jpg',
        'initialPresetId': 'first',
      },
    );

    final restored = await store.read(
      imagePath: '/private/photo.jpg',
      initialPresetId: 'second',
    );

    expect(restored, isNull);
  });
}
