import 'package:flutter/material.dart';

import '../../services/biometric_unlock.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

/// Uses Apple artwork only for the matching native authentication method.
class BiometricIcon extends StatelessWidget {
  const BiometricIcon({
    super.key,
    required this.kind,
    this.size,
    this.fingerprintSize,
  });

  final BiometricKind kind;
  final double? size;

  /// Retains the Material icon's optical size in compact passcode buttons.
  final double? fingerprintSize;

  @override
  Widget build(BuildContext context) => switch (kind) {
    BiometricKind.face => AppIcon(
      AppIcons.faceId,
      size: size ?? AppIconSize.medium,
    ),
    BiometricKind.touchId => AppIcon(
      AppIcons.touchId,
      size: size ?? AppIconSize.medium,
    ),
    BiometricKind.fingerprint => Icon(
      Icons.fingerprint,
      size: fingerprintSize ?? size,
    ),
    BiometricKind.none => AppIcon(
      AppIcons.unlock,
      size: size ?? AppIconSize.medium,
    ),
  };
}
