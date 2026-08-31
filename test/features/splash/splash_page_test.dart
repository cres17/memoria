import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/features/splash/splash_page.dart';

void main() {
  testWidgets('localized splash leaves for home without a fixed long delay',
      (tester) async {
    final previousLocale = localeNotifier.value;
    localeNotifier.value = const Locale('ko');
    addTearDown(() => localeNotifier.value = previousLocale);

    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashPage(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SizedBox(key: ValueKey('home-destination')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('사진을 위한 조용한 작업실'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-destination')), findsOneWidget);
  });
}
