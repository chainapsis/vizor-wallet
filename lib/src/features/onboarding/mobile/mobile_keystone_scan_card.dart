import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart'
    show AddressQrCameraStatus;
import '../../address_scan/widgets/mobile_address_scan_card.dart';

const _keystoneScannerCardHeight = 464.0;
const _keystoneScannerFooterHeight = 68.0;

class MobileKeystoneScanCardContent extends StatelessWidget {
  const MobileKeystoneScanCardContent({
    required this.status,
    required this.onTorch,
    required this.onClose,
    required this.onRetry,
    this.cameraView,
    this.error,
    this.unavailableDescription,
    this.cameraHeight,
    super.key,
  });

  final AddressQrCameraStatus status;
  final Widget? cameraView;
  final String? error;
  final String? unavailableDescription;
  final double? cameraHeight;
  final VoidCallback onTorch;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MobileAddressScanCardContent(
      status: status,
      cameraView: cameraView,
      caption: 'Scan a Zcash QR code to continue',
      error: error,
      unavailableDescription: unavailableDescription,
      cameraHeight: cameraHeight ?? _keystoneScannerCardHeight,
      onTorch: onTorch,
      onClose: onClose,
      onRetry: onRetry,
      permissionBuilder:
          (context, status, unavailableDescription, onRetry, onClose) =>
              MobileKeystoneScanPermissionCard(
                status: status,
                unavailableDescription: unavailableDescription,
                onRetry: onRetry,
                cameraHeight: cameraHeight ?? _keystoneScannerCardHeight,
              ),
    );
  }
}

class MobileKeystoneScanPermissionCard extends StatelessWidget {
  const MobileKeystoneScanPermissionCard({
    required this.status,
    required this.onRetry,
    this.unavailableDescription,
    this.cameraHeight = _keystoneScannerCardHeight,
    super.key,
  });

  final AddressQrCameraStatus status;
  final String? unavailableDescription;
  final VoidCallback onRetry;
  final double cameraHeight;

  bool get _showsRetry =>
      status == AddressQrCameraStatus.denied ||
      status == AddressQrCameraStatus.unavailable;

  String get _title {
    switch (status) {
      case AddressQrCameraStatus.denied:
        return "You've denied camera access";
      case AddressQrCameraStatus.unavailable:
        return 'Camera unavailable';
      case AddressQrCameraStatus.requesting:
      case AddressQrCameraStatus.active:
      case AddressQrCameraStatus.loading:
        return 'Enable camera access';
    }
  }

  String get _description {
    switch (status) {
      case AddressQrCameraStatus.denied:
        return 'Request again, or enable manually\n'
            'in the System settings.';
      case AddressQrCameraStatus.unavailable:
        return unavailableDescription ??
            'Keystone import uses camera QR scanning only.\n'
                'Connect a camera and try again.';
      case AddressQrCameraStatus.requesting:
      case AddressQrCameraStatus.active:
      case AddressQrCameraStatus.loading:
        return 'A camera is required to connect Keystone.\n'
            'You can revert this in settings anytime later.';
    }
  }

  String get _retryLabel => status == AddressQrCameraStatus.unavailable
      ? 'Try again'
      : 'Request again';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_keystone_scan_permission_card'),
      height: cameraHeight,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background.ground,
                  borderRadius: BorderRadius.circular(AppRadii.large),
                  boxShadow: const [
                    BoxShadow(color: Color(0x00000000), blurRadius: 1),
                    BoxShadow(
                      color: Color(0x00000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                    BoxShadow(
                      color: Color(0x00000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.s,
                      right: AppSpacing.s,
                      top: AppSpacing.md,
                    ),
                    child: _KeystonePermissionMessage(
                      title: _title,
                      description: _description,
                      denied: status == AddressQrCameraStatus.denied,
                      action: _showsRetry
                          ? AppButton(
                              key: const ValueKey(
                                'mobile_keystone_scan_retry_button',
                              ),
                              variant: AppButtonVariant.secondary,
                              size: AppButtonSize.medium,
                              minWidth: 96,
                              leading: const AppIcon(AppIcons.renew),
                              onPressed: onRetry,
                              child: Text(_retryLabel),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: _keystoneScannerFooterHeight),
        ],
      ),
    );
  }
}

class _KeystonePermissionMessage extends StatelessWidget {
  const _KeystonePermissionMessage({
    required this.title,
    required this.description,
    required this.denied,
    this.action,
  });

  final String title;
  final String description;
  final bool denied;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            // Requesting sits on the inverse tile, denied on the neutral
            // raised tile (Figma 4654:72631 / 4654:72955) — both theme-aware.
            color: denied ? colors.background.raised : colors.background.inverse,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Center(
            child: AppIcon(
              AppIcons.cameraDenied,
              size: 24,
              color: denied ? colors.icon.accent : colors.icon.inverse,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final line in description.split('\n'))
          Text(
            line,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
      ],
    );
  }
}
