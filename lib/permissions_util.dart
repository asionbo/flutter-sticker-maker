import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionsUtil {
  static Future<bool> requestAll({bool requestCamera = false}) async {
    bool granted = false;
    if (Platform.isIOS) {
      final photoStatus = await Permission.photos.request();
      if (requestCamera) {
        final cameraStatus = await Permission.camera.request();
        granted = photoStatus.isGranted && cameraStatus.isGranted;
      } else {
        granted = photoStatus.isGranted;
      }
    } else if (Platform.isAndroid) {
      PermissionStatus storageStatus;
      if (await Permission.photos.isGranted || await Permission.photos.isLimited) {
        storageStatus = await Permission.photos.status;
      } else if (await Permission.storage.isGranted) {
        storageStatus = await Permission.storage.status;
      } else {
        if (await Permission.photos.isAvailable) {
          storageStatus = await Permission.photos.request();
        } else {
          storageStatus = await Permission.storage.request();
        }
      }
      if (requestCamera) {
        final cameraStatus = await Permission.camera.request();
        granted = storageStatus.isGranted && cameraStatus.isGranted;
      } else {
        granted = storageStatus.isGranted;
      }
    }
    return granted;
  }

  static Future<void> handlePermanentlyDenied() async {
    if (Platform.isIOS) {
      if (await Permission.photos.isPermanentlyDenied ||
          await Permission.camera.isPermanentlyDenied) {
        await openAppSettings();
      }
    } else if (Platform.isAndroid) {
      if (await Permission.storage.isPermanentlyDenied ||
          await Permission.photos.isPermanentlyDenied ||
          await Permission.camera.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }
}