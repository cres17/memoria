import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_page.dart';
import '../../features/editor/editor_page.dart';
import '../../features/filters/filters_page.dart';
import '../../features/create_filter/create_filter_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/dev_panel_page.dart';
import '../shell/main_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
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
      builder: (context, state) {
        final imagePath = state.extra as String?;
        return EditorPage(imagePath: imagePath);
      },
    ),
    GoRoute(
      path: '/create-filter',
      name: 'createFilter',
      builder: (context, state) => const CreateFilterPage(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/dev-panel',
      name: 'devPanel',
      builder: (context, state) => const DevPanelPage(),
    ),
  ],
);
