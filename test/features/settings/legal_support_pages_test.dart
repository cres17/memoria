import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/features/settings/legal_support_pages.dart';

void main() {
  late Locale previousLocale;

  setUp(() {
    previousLocale = localeNotifier.value;
  });

  tearDown(() {
    localeNotifier.value = previousLocale;
  });

  testWidgets('privacy page explains the permission-minimized photo flow',
      (tester) async {
    localeNotifier.value = const Locale('ko');
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyPolicyPage()),
    );

    expect(find.text('개인정보 보호'), findsOneWidget);
    expect(find.textContaining('전체 사진 보관함 권한이 필요하지 않습니다'), findsOneWidget);
    expect(find.textContaining('계정 없이 동작'), findsOneWidget);
  });

  testWidgets('support page exposes the official issue address in English',
      (tester) async {
    localeNotifier.value = const Locale('en');
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.pumpAndSettle();

    expect(find.text('Help & Support'), findsWidgets);
    expect(find.text(memoriaSupportUrl), findsOneWidget);
    expect(find.text('Copy support address'), findsOneWidget);
  });

  testWidgets('privacy and support remain usable at 200% text scale',
      (tester) async {
    localeNotifier.value = const Locale('en');
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget largeTextApp(Widget home) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: home,
        );

    await tester.pumpWidget(largeTextApp(const PrivacyPolicyPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Privacy'), findsOneWidget);

    await tester.pumpWidget(largeTextApp(const SupportPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Copy support address'),
      200,
    );
    expect(tester.takeException(), isNull);

    final semantics = tester.ensureSemantics();
    final copyNode = tester.getSemantics(
      find.widgetWithText(FilledButton, 'Copy support address'),
    );
    expect(copyNode.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });
}
