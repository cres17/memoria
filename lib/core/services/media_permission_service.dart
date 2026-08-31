import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

/// Photo-library authorization as exposed to Memoria workflows.
enum PhotoLibraryAccessState {
  notDetermined,
  restricted,
  denied,
  authorized,
  limited,
}

extension PhotoLibraryAccessStateX on PhotoLibraryAccessState {
  bool get canReadLibrary =>
      this == PhotoLibraryAccessState.authorized ||
      this == PhotoLibraryAccessState.limited;

  bool get isLimited => this == PhotoLibraryAccessState.limited;
}

/// Owns the three intentionally different photo authorization paths.
///
/// * System picker: never requests whole-library permission.
/// * Recent-photo browser: requests read/write access only when opened.
/// * Export: requests add-only access immediately before saving.
///
/// iOS treats read/write and add-only as independent authorization levels, so
/// they must not be collapsed into one generic "photos permission" check.
class MediaPermissionService {
  /// The platform picker vends only user-selected files and never needs the
  /// whole-library authorization represented by this service.
  static const systemPickerRequiresLibraryAccess = false;

  static const recentPhotoRequestOption = PermissionRequestOption(
    iosAccessLevel: IosAccessLevel.readWrite,
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  static Future<PhotoLibraryAccessState> currentRecentPhotoAccess() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: recentPhotoRequestOption,
    );
    return mapPhotoManagerState(state);
  }

  static Future<PhotoLibraryAccessState> requestRecentPhotoAccess() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: recentPhotoRequestOption,
    );
    return mapPhotoManagerState(state);
  }

  /// Requests PhotoKit add-only access on iOS. Gal returns true without a
  /// runtime prompt on Android versions whose MediaStore writes need none.
  static Future<bool> ensurePhotoLibraryWriteAccess() async {
    if (await Gal.hasAccess()) return true;
    return Gal.requestAccess();
  }

  static PhotoLibraryAccessState mapPhotoManagerState(PermissionState state) {
    return switch (state) {
      PermissionState.notDetermined => PhotoLibraryAccessState.notDetermined,
      PermissionState.restricted => PhotoLibraryAccessState.restricted,
      PermissionState.denied => PhotoLibraryAccessState.denied,
      PermissionState.authorized => PhotoLibraryAccessState.authorized,
      PermissionState.limited => PhotoLibraryAccessState.limited,
    };
  }

  /// Opens the operating system's app-permission screen from Settings.
  static Future<bool> openAppPermissionSettings() => openAppSettings();
}
