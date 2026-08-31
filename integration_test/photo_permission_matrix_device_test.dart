import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/services/media_permission_service.dart';
import 'package:photo_manager/photo_manager.dart';

const _deviceName = String.fromEnvironment(
  'MEMORIA_PERF_DEVICE_NAME',
  defaultValue: 'unknown device',
);
const _isPhysicalDevice = bool.fromEnvironment(
  'MEMORIA_PHYSICAL_DEVICE',
  defaultValue: false,
);
const _expectedReadState = String.fromEnvironment(
  'MEMORIA_EXPECTED_PHOTO_READ',
  defaultValue: 'any',
);
const _expectedAddState = String.fromEnvironment(
  'MEMORIA_EXPECTED_PHOTO_ADD',
  defaultValue: 'any',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports current photo permission matrix without prompting',
      (tester) async {
    final readWrite = await PhotoManager.getPermissionState(
      requestOption: MediaPermissionService.recentPhotoRequestOption,
    );
    final addOnly = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.addOnly,
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    final galAddAccess = await Gal.hasAccess();
    final mappedRead = MediaPermissionService.mapPhotoManagerState(readWrite);

    expect(
      mappedRead.canReadLibrary,
      readWrite == PermissionState.authorized ||
          readWrite == PermissionState.limited,
    );
    expect(MediaPermissionService.systemPickerRequiresLibraryAccess, isFalse);
    _expectState('readWrite', readWrite, _expectedReadState);
    _expectState('addOnly', addOnly, _expectedAddState);
    if (_expectedAddState == PermissionState.authorized.name) {
      expect(galAddAccess, isTrue);
    } else if (_expectedAddState == PermissionState.denied.name) {
      expect(galAddAccess, isFalse);
    }

    final report = <String, Object>{
      'schemaVersion': 1,
      'scope': _isPhysicalDevice
          ? 'physical-device/photo-permission-current-state'
          : 'simulator/photo-permission-current-state',
      'device': <String, String>{
        'name': _deviceName,
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      },
      'systemPicker': <String, Object>{
        'requiresWholeLibraryAccess': false,
        'promptTriggeredByTest': false,
      },
      'recentLibrary': <String, Object>{
        'accessLevel': 'readWrite',
        'state': readWrite.name,
        'canRead': mappedRead.canReadLibrary,
        'limited': mappedRead.isLimited,
        'promptTriggeredByTest': false,
      },
      'exportSave': <String, Object>{
        'accessLevel': 'addOnly',
        'photoManagerState': addOnly.name,
        'galHasAccess': galAddAccess,
        'promptTriggeredByTest': false,
      },
      'limitations': <String>[
        'This diagnostic is read-only and records the device current state.',
        if (_isPhysicalDevice)
          'Denied, limited, and authorized transitions require separate manual user choices.',
      ],
    };
    binding.reportData = <String, Object>{'photoPermissionMatrix': report};
    // ignore: avoid_print
    print('PHOTO_PERMISSION_MATRIX_RESULT=${jsonEncode(report)}');
  });
}

void _expectState(
  String accessLevel,
  PermissionState actual,
  String expected,
) {
  if (expected == 'any') return;
  expect(
    actual.name,
    expected,
    reason: '$accessLevel authorization did not match the injected matrix row',
  );
}
