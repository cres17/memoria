import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/core/l10n/strings.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/white_balance.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';

void main() {
  test('navigation and editor tool names follow the selected locale', () {
    final previousLocale = localeNotifier.value;
    addTearDown(() => localeNotifier.value = previousLocale);

    localeNotifier.value = const Locale('ko');
    expect(
      ['nav.home', 'nav.create_beta', 'nav.edit', 'nav.filters'].map(S.get),
      ['홈', '필터 제작 베타', '편집', '필터'],
    );
    expect(editorToolCatalog.first.label, '기본 보정');

    localeNotifier.value = const Locale('en');
    expect(
      ['nav.home', 'nav.create_beta', 'nav.edit', 'nav.filters'].map(S.get),
      ['Home', 'Create beta', 'Edit', 'Filters'],
    );
    expect(editorToolCatalog.first.label, 'Adjust');
  });

  test('editor detail controls and enum labels follow the selected locale', () {
    final previousLocale = localeNotifier.value;
    addTearDown(() => localeNotifier.value = previousLocale);

    localeNotifier.value = const Locale('en');

    expect(S.get('editor.exposure'), 'Exposure');
    expect(S.get('editor.selective_add_hint'),
        'Add a marker to enable selective adjustment controls.');
    expect(S.get(CropRatioPreset.free.l10nKey), 'Free');
    expect(S.get(WhiteBalancePreset.cloudy.l10nKey), 'Cloudy');
    expect(S.get(ArtisticEffect.dramaBright1.l10nKey), 'Bright Drama 1');
    expect(S.get('curve.soft_contrast'), 'Soft Contrast');
    expect(S.get('export.timeout'),
        'The export timed out. Retry at a lower resolution.');
  });

  test('low reference coverage guidance follows the selected locale', () {
    final previousLocale = localeNotifier.value;
    addTearDown(() => localeNotifier.value = previousLocale);

    localeNotifier.value = const Locale('ko');
    expect(
      S.get('create.low_coverage'),
      '이 사진은 색상 정보가 부족해 필터를 정확하게 만들기 어려워요. 여러 색상과 밝기가 포함된 사진을 선택해 주세요.',
    );
    expect(S.get('create.choose_another'), '다른 사진 선택');

    localeNotifier.value = const Locale('en');
    expect(
      S.get('create.low_coverage'),
      'This photo does not contain enough color information to create an accurate filter. Choose a photo with more varied colors and brightness.',
    );
    expect(S.get('create.choose_another'), 'Choose another');
  });
}
