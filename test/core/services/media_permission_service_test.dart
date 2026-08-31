import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/services/media_permission_service.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  test('system picker never requires whole-library authorization', () {
    expect(MediaPermissionService.systemPickerRequiresLibraryAccess, isFalse);
  });

  test('maps every PhotoKit and Android library authorization state', () {
    const matrix = <PermissionState, PhotoLibraryAccessState>{
      PermissionState.notDetermined: PhotoLibraryAccessState.notDetermined,
      PermissionState.restricted: PhotoLibraryAccessState.restricted,
      PermissionState.denied: PhotoLibraryAccessState.denied,
      PermissionState.authorized: PhotoLibraryAccessState.authorized,
      PermissionState.limited: PhotoLibraryAccessState.limited,
    };

    for (final entry in matrix.entries) {
      expect(
        MediaPermissionService.mapPhotoManagerState(entry.key),
        entry.value,
      );
    }
  });

  test('only full and limited authorization can read recent photos', () {
    expect(PhotoLibraryAccessState.notDetermined.canReadLibrary, isFalse);
    expect(PhotoLibraryAccessState.restricted.canReadLibrary, isFalse);
    expect(PhotoLibraryAccessState.denied.canReadLibrary, isFalse);
    expect(PhotoLibraryAccessState.authorized.canReadLibrary, isTrue);
    expect(PhotoLibraryAccessState.limited.canReadLibrary, isTrue);
    expect(PhotoLibraryAccessState.limited.isLimited, isTrue);
  });

  test('recent-photo request uses read/write images without location', () {
    const option = MediaPermissionService.recentPhotoRequestOption;
    expect(option.iosAccessLevel, IosAccessLevel.readWrite);
    expect(option.androidPermission.type, RequestType.image);
    expect(option.androidPermission.mediaLocation, isFalse);
  });
}
