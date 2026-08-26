import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/features/settings/settings_recovery_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'settings recovery UI executes recovery and confirms destructive discard',
    (tester) async {
      final previousLocale = localeNotifier.value;
      localeNotifier.value = const Locale('ko');
      addTearDown(() => localeNotifier.value = previousLocale);

      final controller = _FakeRecoveryController([
        const SettingsRecoveryCandidate(
          id: 'preference:favorites',
          kind: SettingsRecoveryKind.favorites,
          rawByteLength: 21,
        ),
        const SettingsRecoveryCandidate(
          id: 'filter-index:0',
          kind: SettingsRecoveryKind.filterIndex,
          rawByteLength: 48,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsRecoverySection(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('settings-recovery-row')), findsOneWidget);
      expect(find.text('복구가 필요한 항목 2개'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-recovery-row')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('settings-recovery-candidate-preference:favorites'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-recovery-attempt')));
      await tester.pumpAndSettle();

      expect(controller.recoveredIds, ['preference:favorites']);
      expect(find.text('유효한 항목 3개를 복구했습니다.'), findsOneWidget);
      expect(find.text('복구가 필요한 항목 1개'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-recovery-row')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-recovery-candidate-filter-index:0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-recovery-discard')));
      await tester.pumpAndSettle();

      expect(find.text('원본도 삭제할까요?'), findsOneWidget);
      expect(controller.discardedIds, isEmpty);
      await tester.tap(
        find.byKey(const Key('settings-recovery-discard-cancel')),
      );
      await tester.pumpAndSettle();
      expect(controller.discardedIds, isEmpty);

      await tester.tap(find.byKey(const Key('settings-recovery-row')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-recovery-candidate-filter-index:0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-recovery-discard')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-recovery-discard-confirm')),
      );
      await tester.pumpAndSettle();

      expect(controller.discardedIds, ['filter-index:0']);
      expect(find.byKey(const Key('settings-recovery-row')), findsNothing);
      expect(find.text('보관된 이전 목록 원본을 삭제했습니다.'), findsOneWidget);
    },
  );

  testWidgets('settings recovery UI keeps the original on safe reset',
      (tester) async {
    final previousLocale = localeNotifier.value;
    localeNotifier.value = const Locale('ko');
    addTearDown(() => localeNotifier.value = previousLocale);
    final controller = _FakeRecoveryController([
      const SettingsRecoveryCandidate(
        id: 'preference:customAdjustments',
        kind: SettingsRecoveryKind.customAdjustments,
        rawByteLength: 34,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsRecoverySection(controller: controller),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-recovery-row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key(
          'settings-recovery-candidate-preference:customAdjustments',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-recovery-safe-reset')));
    await tester.pumpAndSettle();

    expect(controller.resetIds, ['preference:customAdjustments']);
    expect(find.byKey(const Key('settings-recovery-row')), findsNothing);
    expect(find.text('원본을 보관한 채 데이터를 초기화했습니다.'), findsOneWidget);
  });
}

class _FakeRecoveryController implements SettingsRecoveryController {
  final List<SettingsRecoveryCandidate> candidates;
  final List<String> recoveredIds = [];
  final List<String> resetIds = [];
  final List<String> discardedIds = [];

  _FakeRecoveryController(List<SettingsRecoveryCandidate> candidates)
      : candidates = [...candidates];

  @override
  Future<List<SettingsRecoveryCandidate>> pending() async => [...candidates];

  @override
  Future<SettingsRecoveryResult> recover(
    SettingsRecoveryCandidate candidate,
  ) async {
    recoveredIds.add(candidate.id);
    candidates.removeWhere((item) => item.id == candidate.id);
    return const SettingsRecoveryResult(
      recovered: true,
      recoveredItemCount: 3,
    );
  }

  @override
  Future<void> resetKeepingOriginal(
    SettingsRecoveryCandidate candidate,
  ) async {
    resetIds.add(candidate.id);
    candidates.removeWhere((item) => item.id == candidate.id);
  }

  @override
  Future<void> discardOriginal(SettingsRecoveryCandidate candidate) async {
    discardedIds.add(candidate.id);
    candidates.removeWhere((item) => item.id == candidate.id);
  }
}
