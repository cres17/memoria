import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps iOS media permission handling consistent across all image entry points.
class MediaPermissionService {
  static const _didRequestPhotosOnFirstLaunch =
      'did_request_photos_on_first_launch';

  /// iOS's "Selected Photos" access is sufficient for the system photo picker.
  static bool hasPhotoAccess(PermissionStatus status) =>
      status.isGranted || status.isLimited;

  /// iOS's system photo picker can still return user-selected images without
  /// full PhotoKit library access. Do not block picker-based workflows merely
  /// because full library access is denied.
  static bool allowsSystemPhotoPicker(
    PermissionStatus status, {
    bool? isIOS,
  }) {
    if (isIOS ?? Platform.isIOS) {
      return !status.isRestricted;
    }

    return hasPhotoAccess(status);
  }

  static Future<PermissionStatus> requestPhotosIfNeeded() async {
    final current = await Permission.photos.status;
    if (hasPhotoAccess(current) ||
        current.isPermanentlyDenied ||
        current.isRestricted) {
      return current;
    }
    return Permission.photos.request();
  }

  static Future<bool> ensurePhotoAccess() async {
    final status = await requestPhotosIfNeeded();
    return allowsSystemPhotoPicker(status);
  }

  /// Prompts once after the initial app screen is visible, never during splash.
  static Future<void> requestPhotosOnFirstLaunch() async {
    final preferences = await SharedPreferences.getInstance();
    final current = await Permission.photos.status;
    final didCompleteRequest =
        preferences.getBool(_didRequestPhotosOnFirstLaunch) ?? false;
    if (didCompleteRequest && allowsSystemPhotoPicker(current)) return;

    final result = await requestPhotosIfNeeded();
    // Do not permanently suppress a future request merely because the initial
    // system dialog did not appear. A previously stored flag from an older
    // build is also cleared whenever photo access is still unavailable.
    if (allowsSystemPhotoPicker(result)) {
      await preferences.setBool(_didRequestPhotosOnFirstLaunch, true);
    } else {
      await preferences.remove(_didRequestPhotosOnFirstLaunch);
    }
  }

  /// Opens this app's system settings page on both iOS and Android. iOS only
  /// permits this app-level deep link; Android opens the app details/permission
  /// page provided by the device Settings app.
  static Future<bool> openAppPermissionSettings() => openAppSettings();

  static Future<bool> ensureCameraAccess() async {
    var status = await Permission.camera.status;
    if (!status.isGranted &&
        !status.isPermanentlyDenied &&
        !status.isRestricted) {
      status = await Permission.camera.request();
    }
    return status.isGranted;
  }
}
