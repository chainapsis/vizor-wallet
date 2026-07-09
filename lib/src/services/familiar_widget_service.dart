import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../main.dart' show log;
import '../core/profile_pictures.dart';

typedef FamiliarWidgetPlatformCheck = bool Function();

bool _defaultSupportsFamiliarWidget() => Platform.isIOS;

class FamiliarWidgetService {
  FamiliarWidgetService({
    MethodChannel? channel,
    FamiliarWidgetPlatformCheck? supportsFamiliarWidget,
  }) : _channel = channel ?? familiarWidgetChannel,
       _supportsFamiliarWidget =
           supportsFamiliarWidget ?? _defaultSupportsFamiliarWidget;

  @visibleForTesting
  static const familiarWidgetChannel = MethodChannel(
    'com.zcash.wallet/familiar_widget',
  );

  final MethodChannel _channel;
  final FamiliarWidgetPlatformCheck _supportsFamiliarWidget;

  // The account name is a user-authored string that can carry sensitive
  // labels ("Savings", "DAO payroll"). It must never reach the home-screen
  // widget, which renders on an unauthenticated surface. Only the profile
  // picture id crosses the channel; the widget derives its class title from
  // that id natively.
  Future<void> update({required String profilePictureId}) async {
    if (!_supportsFamiliarWidget()) return;

    final normalizedProfilePictureId = normalizeProfilePictureId(
      profilePictureId,
    );
    try {
      final success = await _channel.invokeMethod<bool>('updateFamiliar', {
        'profilePictureId': normalizedProfilePictureId,
      });
      if (success != true) {
        log('FamiliarWidget: native update returned $success');
      }
    } catch (e) {
      log('FamiliarWidget: native update failed: $e');
    }
  }
}
