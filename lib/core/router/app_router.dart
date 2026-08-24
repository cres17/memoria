import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_page.dart';
import '../../features/editor/editor_page.dart';
import '../../features/filters/filters_page.dart';
import '../../features/create_filter/create_filter_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/dev_panel_page.dart';
import '../../features/splash/splash_page.dart';
import '../shell/main_shell.dart';

Page<void> _adaptivePage(GoRouterState state, Widget child) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPage<void>(
      key: state.pageKey,
      name: state.name,
      child: child,
    );
  }
  return MaterialPage<void>(
    key: state.pageKey,
    name: state.name,
    child: child,
  );
}

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      pageBuilder: (context, state) => _adaptivePage(state, const SplashPage()),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/filters',
          name: 'filters',
          builder: (context, state) => const FiltersPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/editor',
      name: 'editor',
      pageBuilder: (context, state) {
        final extra = state.extra;
        if (extra is Map<String, String?>) {
          return _adaptivePage(
              state,
              EditorPage(
                imagePath: extra['imagePath'],
                initialPresetId: extra['presetId'],
              ));
        }
        return _adaptivePage(state, EditorPage(imagePath: extra as String?));
      },
    ),
    GoRoute(
      path: '/create-filter',
      name: 'createFilter',
      pageBuilder: (context, state) =>
          _adaptivePage(state, const CreateFilterPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) =>
          _adaptivePage(state, const SettingsPage()),
    ),
    if (kDebugMode)
      GoRoute(
        path: '/dev-panel',
        name: 'devPanel',
        pageBuilder: (context, state) =>
            _adaptivePage(state, const DevPanelPage()),
      ),
  ],
);
