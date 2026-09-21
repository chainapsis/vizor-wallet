import 'package:flutter/widgets.dart';

import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';
import '../full_address_viewer.dart';

/// Full-address verification sheet — identity title on top, a continuous
/// wrapping Geist Mono address, a primary Copy address action, and header close.
Future<void> showMobileAddressVerifySheet(
  BuildContext context, {
  required String title,
  required String address,
  Widget? leading,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      return MobileAddressVerifySheet(
        title: title,
        address: address,
        leading: leading,
        onClose: () => Navigator.of(sheetContext).pop(),
      );
    },
  );
}

/// Sheet body extracted so Widgetbook / figma-compare can render the
/// viewer without opening a route.
class MobileAddressVerifySheet extends StatelessWidget {
  const MobileAddressVerifySheet({
    required this.title,
    required this.address,
    required this.onClose,
    this.leading,
    super.key,
  });

  final String title;
  final String address;
  final Widget? leading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MobileModalScaffold(
      title: title,
      leading: leading,
      bodyGap: AppSpacing.sm,
      bottomPadding: AppSpacing.md,
      constrainBody: true,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('mobile_address_verify_chunks'),
              child: SizedBox(
                width: double.infinity,
                child: FullAddressText(address: address),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FullAddressCopyButton(
            address: address,
            expand: true,
            size: AppButtonSize.large,
          ),
        ],
      ),
    );
  }
}
