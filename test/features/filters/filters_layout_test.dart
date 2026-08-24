import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/l10n/app_locale.dart';
import 'package:memoria/features/filters/filters_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    localeNotifier.value = const Locale('ko');
    tempDirectory =
        await Directory.systemTemp.createTemp('memoria-filters-layout-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('Gallery hero separates Memoria and collection title',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: FiltersPage()));
    await tester.pump();
    await tester.pumpAndSettle();

    final brand = find.text('Memoria');
    final title = find.byKey(const ValueKey('filters-collection-title'));
    expect(brand, findsOneWidget);
    expect(title, findsOneWidget);
    expect(
        tester.getBottomLeft(brand).dy, lessThan(tester.getTopLeft(title).dy));

    final plus = find.byKey(const ValueKey('create-filter-plus'));
    expect(plus, findsOneWidget);
    expect(tester.getSize(plus), const Size(42, 42));
  });
}
