import 'package:flutter/material.dart';
import 'core/l10n/app_locale.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class MemoriaApp extends StatelessWidget {
  const MemoriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, locale, __) => MaterialApp.router(
        title: 'Memoria',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        locale: locale,
        supportedLocales: const [Locale('ko'), Locale('en')],
        routerConfig: appRouter,
      ),
    );
  }
}
