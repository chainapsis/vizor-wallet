import 'package:flutter/services.dart';

class CameraPermissionSettings {
  CameraPermissionSettings._();

  static const _channel = MethodChannel('com.zcash.wallet/camera_permission');

  static Future<bool> open() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
