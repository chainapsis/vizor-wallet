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

  Future<void> update({
    required String profilePictureId,
    required String accountName,
  }) async {
    if (!_supportsFamiliarWidget()) return;

    final normalizedProfilePictureId = normalizeProfilePictureId(
      profilePictureId,
    );
    final normalizedAccountName = accountName.trim();
    try {
      final success = await _channel.invokeMethod<bool>('updateFamiliar', {
        'profilePictureId': normalizedProfilePictureId,
        'accountName': normalizedAccountName.isEmpty
            ? 'Vizor'
            : normalizedAccountName,
      });
      if (success != true) {
        log('FamiliarWidget: native update returned $success');
      }
    } catch (e) {
      log('FamiliarWidget: native update failed: $e');
    }
  }
}
