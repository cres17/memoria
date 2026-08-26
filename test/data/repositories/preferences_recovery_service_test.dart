import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/data/repositories/preferences_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recovers valid favorite ids and archives the original payload',
      () async {
    const key = 'filter_favorites_v1_corrupt_backup';
    SharedPreferences.setMockInitialValues({
      key: '["warm", 42, "warm", "film"]',
    });
    final service = PreferencesRecoveryService();

    final attempt = await service.tryRecover(PreferenceRecoveryItem.favorites);

    expect(attempt.recovered, isTrue);
    expect(attempt.recoveredItemCount, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(prefs.getString('filter_favorites_v1')!), ['film', 'warm']);
    expect(prefs.getString(key), isNull);
    expect(
      prefs.getString('filter_favorites_v1_recovery_archive'),
      '["warm", 42, "warm", "film"]',
    );
  });

  test('keeps an invalid JSON backup pending when recovery is impossible',
      () async {
    const key = 'custom_adjustments_v1_corrupt_backup';
    SharedPreferences.setMockInitialValues({key: '{invalid'});
    final service = PreferencesRecoveryService();

    final attempt =
        await service.tryRecover(PreferenceRecoveryItem.customAdjustments);

    expect(attempt.recovered, isFalse);
    expect((await service.pending()).single.item,
        PreferenceRecoveryItem.customAdjustments);
  });

  test('safe reset archives the original before clearing the live collection',
      () async {
    SharedPreferences.setMockInitialValues({
      'filter_favorites_v1': '["bad"]',
      'filter_favorites_v1_corrupt_backup': '["bad"]',
    });
    final service = PreferencesRecoveryService();

    await service.resetKeepingOriginal(PreferenceRecoveryItem.favorites);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('filter_favorites_v1'), isNull);
    expect(prefs.getString('filter_favorites_v1_corrupt_backup'), isNull);
    expect(prefs.getString('filter_favorites_v1_recovery_archive'), '["bad"]');
  });

  test('destructive reset removes the current value and archived source',
      () async {
    SharedPreferences.setMockInitialValues({
      'custom_adjustments_v1': '["bad"]',
      'custom_adjustments_v1_corrupt_backup': '["bad"]',
      'custom_adjustments_v1_recovery_archive': '["bad"]',
    });
    final service = PreferencesRecoveryService();

    await service.discardOriginalAndReset(
      PreferenceRecoveryItem.customAdjustments,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_adjustments_v1'), isNull);
    expect(prefs.getString('custom_adjustments_v1_corrupt_backup'), isNull);
    expect(prefs.getString('custom_adjustments_v1_recovery_archive'), isNull);
  });
}
