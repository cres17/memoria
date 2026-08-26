import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/features/settings/settings_recovery_section.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved-data recovery is actionable from settings UI',
      (tester) async {
    localeNotifier.value = const Locale('ko');
    final controller = _IntegrationRecoveryController([
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
          body: SafeArea(
            child: SettingsRecoverySection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
    expect(controller.discardedIds, isEmpty);

    await tester.tap(
      find.byKey(const Key('settings-recovery-discard-confirm')),
    );
    await tester.pumpAndSettle();

    expect(controller.discardedIds, ['filter-index:0']);
    expect(find.byKey(const Key('settings-recovery-row')), findsNothing);
  });
}

class _IntegrationRecoveryController implements SettingsRecoveryController {
  final List<SettingsRecoveryCandidate> candidates;
  final List<String> recoveredIds = [];
  final List<String> discardedIds = [];

  _IntegrationRecoveryController(List<SettingsRecoveryCandidate> candidates)
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
    candidates.removeWhere((item) => item.id == candidate.id);
  }

  @override
  Future<void> discardOriginal(SettingsRecoveryCandidate candidate) async {
    discardedIds.add(candidate.id);
    candidates.removeWhere((item) => item.id == candidate.id);
  }
}
