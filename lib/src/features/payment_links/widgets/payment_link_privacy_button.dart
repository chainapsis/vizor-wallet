import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../providers/privacy_mode_provider.dart';

/// Toggles the wallet-wide privacy setting from the gift card list.
class PaymentLinkPrivacyButton extends ConsumerWidget {
  const PaymentLinkPrivacyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(privacyModeProvider);
    final label = enabled ? 'Turn off privacy mode' : 'Turn on privacy mode';
    const size = kAppFormFactor == AppFormFactor.mobile ? 44.0 : 32.0;
    return AppTooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: SizedBox.square(
          dimension: size,
          child: AppButton(
            key: const ValueKey('payment_link_privacy_button'),
            onPressed: () {
              if (kAppFormFactor == AppFormFactor.mobile) {
                unawaited(AppHaptics.privacyToggle());
              }
              unawaited(ref.read(privacyModeProvider.notifier).toggle());
            },
            variant: AppButtonVariant.ghost,
            height: size,
            minWidth: size,
            contentPadding: EdgeInsets.zero,
            child: AppIcon(
              enabled ? AppIcons.eyeClosed : AppIcons.eye,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
