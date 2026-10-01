import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/features/editor/editor_page.dart';
import 'package:path_provider/path_provider.dart';

// A person must complete Save to Files in the real native sheet. The channel
// observer forwards every message to the engine, without faking native results.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('physical iOS editor export and native share complete',
      (tester) async {
    const physical = bool.fromEnvironment('MEMORIA_PHYSICAL_DEVICE');
    const deviceName = String.fromEnvironment('MEMORIA_PERF_DEVICE_NAME');
    if (!Platform.isIOS || !physical || !kProfileMode || deviceName.isEmpty) {
      throw StateError('Use a physical iOS device, --profile, '
          'MEMORIA_PHYSICAL_DEVICE=true and MEMORIA_PERF_DEVICE_NAME.');
    }
    final directory = await getTemporaryDirectory();
    final fixture = File('${directory.path}/memoria_share_validation.jpg');
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(40, 100, 160));
    await fixture.writeAsBytes(img.encodeJpg(image, quality: 95));
    final settings = await ExportPreferences.load(allowWebp: true);
    await ExportPreferences.saveFormat(ExportFormat.jpeg);

    const channel = 'dev.fluttercommunity.plus/share';
    const codec = StandardMethodCodec();
    final messenger = binding.defaultBinaryMessenger;
    final completion = Completer<Map<String, Object>>();
    messenger.setMockMessageHandler(channel, (data) async {
      final call = codec.decodeMethodCall(data!);
      if (call.method != 'shareFiles') {
        return messenger.delegate.send(channel, data);
      }
      try {
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final path = (arguments['paths'] as List).single as String;
        final source = File(path);
        final checksum = sha256.convert(await source.readAsBytes()).toString();
        // Real UIKit invocation. Its completion envelope is observed unchanged.
        final reply = await messenger.delegate.send(channel, data);
        final activity = reply == null ? null : codec.decodeEnvelope(reply);
        completion.complete(<String, Object>{
          'activityType': activity?.toString() ?? '',
          'sourceSha256': checksum,
          'sourcePreserved': await source.exists() &&
              sha256.convert(await source.readAsBytes()).toString() == checksum,
          'anchor': [
            arguments['originX'] ?? -1,
            arguments['originY'] ?? -1,
            arguments['originWidth'] ?? 0,
            arguments['originHeight'] ?? 0,
          ],
        });
        return reply;
      } catch (error) {
        if (!completion.isCompleted) {
          completion.complete({'nativeError': error.toString()});
        }
        rethrow;
      }
    });
    try {
      await tester.pumpWidget(MaterialApp(
        home: EditorPage(imagePath: fixture.path),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.tap(find.text('내보내기').first);
      await tester.pump();
      // ignore: avoid_print
      print('IOS_SHARE_READY: Complete Save to Files; cancellation fails.');
      await tester.tap(find.text('다른 앱으로 공유'));
      await tester.pump();
      final native = await tester.runAsync(
          () => completion.future.timeout(const Duration(minutes: 5)));
      expect(native, isNotNull);
      final report = <String, Object>{
        'schemaVersion': 1,
        'deviceName': deviceName,
        'osVersion': Platform.operatingSystemVersion,
        'buildMode': 'profile',
        'fixture': 'synthetic-solid-640x480',
        ...native!,
        'limitations': [
          'Receiver file bytes must be checked against sourceSha256 separately.',
          'An iPhone completion does not validate the iPad popover.',
        ],
      };
      binding.reportData = {'editorShareCompletion': report};
      // ignore: avoid_print
      print('IOS_SHARE_COMPLETION_RESULT=${jsonEncode(report)}');
      expect(native.containsKey('nativeError'), isFalse);
      expect(native['activityType'], isNot(isEmpty));
      expect(native['activityType'],
          isNot('dev.fluttercommunity.plus/share/unavailable'));
      expect(native['sourcePreserved'], isTrue);
      final anchor = native['anchor'] as List;
      expect(anchor[2] as num, greaterThan(0));
      expect(anchor[3] as num, greaterThan(0));
      await tester.pump();
      expect(find.text('공유 준비 중...'), findsNothing);
    } finally {
      messenger.setMockMessageHandler(channel, null);
      await ExportPreferences.saveFormat(settings.format);
      await tester.pumpWidget(const SizedBox.shrink());
      if (await fixture.exists()) await fixture.delete();
      // The production coordinator owns the shared output's deferred cleanup.
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
