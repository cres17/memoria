import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:memoria/core/services/media_permission_service.dart';

void main() {
  group('MediaPermissionService photo access policy', () {
    test('accepts granted and iOS limited photo access', () {
      expect(MediaPermissionService.hasPhotoAccess(PermissionStatus.granted),
          isTrue);
      expect(MediaPermissionService.hasPhotoAccess(PermissionStatus.limited),
          isTrue);
    });

    test('does not treat denied, restricted, or permanent denial as access',
        () {
      expect(MediaPermissionService.hasPhotoAccess(PermissionStatus.denied),
          isFalse);
      expect(MediaPermissionService.hasPhotoAccess(PermissionStatus.restricted),
          isFalse);
      expect(
        MediaPermissionService.hasPhotoAccess(
            PermissionStatus.permanentlyDenied),
        isFalse,
      );
    });

    test('allows iOS system picker even when full photo access is denied', () {
      expect(
        MediaPermissionService.allowsSystemPhotoPicker(
          PermissionStatus.denied,
          isIOS: true,
        ),
        isTrue,
      );
      expect(
        MediaPermissionService.allowsSystemPhotoPicker(
          PermissionStatus.permanentlyDenied,
          isIOS: true,
        ),
        isTrue,
      );
      expect(
        MediaPermissionService.allowsSystemPhotoPicker(
          PermissionStatus.restricted,
          isIOS: true,
        ),
        isFalse,
      );
    });

    test('keeps non-iOS picker policy aligned with photo access', () {
      expect(
        MediaPermissionService.allowsSystemPhotoPicker(
          PermissionStatus.granted,
          isIOS: false,
        ),
        isTrue,
      );
      expect(
        MediaPermissionService.allowsSystemPhotoPicker(
          PermissionStatus.denied,
          isIOS: false,
        ),
        isFalse,
      );
    });
  });
}
