import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Only iOS reports a restricted state through the native channel.
bool get _canReportRestriction => defaultTargetPlatform == TargetPlatform.iOS;

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

  /// Whether Screen Time or device management blocks the camera. The scanner
  /// plugin reports this as permission denied, but Settings cannot lift it.
  static Future<bool> isRestricted() async {
    if (!_canReportRestriction) return false;
    try {
      final status = await _channel.invokeMethod<String>('authorizationStatus');
      return status == 'restricted';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Tells whether a scanner's permission-denied error is an iOS restriction.
///
/// Looks up once up front, so the answer is ready before the first denial,
/// and again on each denial because Screen Time can change mid-scan.
class CameraRestrictionProbe extends ChangeNotifier {
  CameraRestrictionProbe(this._controller) {
    if (!_canReportRestriction) return;
    _denied = _isDenied(_controller.value);
    _controller.addListener(_handleScannerChange);
    unawaited(_refresh());
  }

  final MobileScannerController _controller;
  bool _denied = false;
  bool _restricted = false;
  int _lookup = 0;

  bool get restricted => _restricted;

  static bool _isDenied(MobileScannerState state) =>
      state.error?.errorCode == MobileScannerErrorCode.permissionDenied;

  void _handleScannerChange() {
    final denied = _isDenied(_controller.value);
    if (denied == _denied) return;
    _denied = denied;
    if (denied) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final lookup = ++_lookup;
    final restricted = await CameraPermissionSettings.isRestricted();
    if (lookup != _lookup || restricted == _restricted) return;
    _restricted = restricted;
    notifyListeners();
  }

  @override
  void dispose() {
    // Invalidates lookups still in flight.
    _lookup++;
    _controller.removeListener(_handleScannerChange);
    super.dispose();
  }
}
