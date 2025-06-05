import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service for handling image and camera permissions.
class PermissionService {
  /// Requests permissions needed for image processing.
  ///
  /// [includeCamera] - Whether to request camera permission in addition to photos
  ///
  /// Returns true if all required permissions are granted.
  static Future<bool> requestImagePermissions({
    bool includeCamera = false,
  }) async {
    final List<Permission> permissions = [Permission.photos];
    if (includeCamera) {
      permissions.add(Permission.camera);
    }

    final Map<Permission, PermissionStatus> statuses =
        await permissions.request();

    return statuses.values.every(
      (status) => status.isGranted || (Platform.isIOS && status.isLimited),
    );
  }

  /// Checks if permissions are permanently denied and shows appropriate dialog.
  ///
  /// [includeCamera] - Whether camera permission should be checked
  ///
  /// Returns true if any permissions are permanently denied.
  static Future<bool> arePermissionsPermanentlyDenied({
    bool includeCamera = false,
  }) async {
    final bool photosPermanentlyDenied =
        await Permission.photos.isPermanentlyDenied;
    final bool cameraPermanentlyDenied =
        includeCamera ? await Permission.camera.isPermanentlyDenied : false;

    return photosPermanentlyDenied || cameraPermanentlyDenied;
  }

  /// Opens the app settings page.
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
