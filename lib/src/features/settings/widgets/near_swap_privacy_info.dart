import 'package:flutter/material.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';

/// NEAR swap privacy subtitle while Private queries is on.
const kNearSwapPrivacyOnCopy = 'Each swap uses new one-time Zcash addresses.';

/// NEAR swap privacy subtitle while Private queries is off.
const kNearSwapPrivacyOffCopy = 'Needs Private queries.';

/// NEAR swap privacy subtitle while a hardware wallet account is active, since
/// only software accounts get one-time swap addresses.
const kNearSwapPrivacyHardwareCopy =
    'Not available for hardware wallet accounts. Their swaps use regular '
    'Zcash addresses.';

/// The NEAR swap privacy subtitle for the active account and Private queries.
String nearSwapPrivacyDescription({
  required bool hardwareAccount,
  required bool privateQueriesOn,
}) => hardwareAccount
    ? kNearSwapPrivacyHardwareCopy
    : privateQueriesOn
    ? kNearSwapPrivacyOnCopy
    : kNearSwapPrivacyOffCopy;

/// Title of the NEAR swap privacy explanation.
const kNearSwapPrivacyInfoTitle = "What's this?";

/// Paragraphs of the NEAR swap privacy explanation.
const kNearSwapPrivacyInfoParagraphs = [
  'When you swap with NEAR Intents, your wallet gives NEAR a Zcash address for '
      'the payout and another for any refund. With NEAR swap privacy on, each '
      'swap gets new Zcash addresses made just for it, so any future quantum '
      "adversary can't tie them to your wallet or to your other swaps.",
  'Addresses you enter yourself, like an Ethereum address you reuse for '
      'several swaps, are still shared with NEAR and can link those swaps. '
      "Hardware wallet accounts don't use one-time addresses.",
  'Your recovery phrase still recovers everything. When you restore your '
      'wallet, it finds these payments privately, even with these settings off.',
  "Turning this off doesn't affect swaps you've already made. Their refunds "
      'and payouts still arrive.',
];

/// Shows the NEAR swap privacy explanation for this binary's form factor: a
/// sheet on mobile, a dialog on desktop.
Future<void> showNearSwapPrivacyInfo(BuildContext context) =>
    kAppFormFactor == AppFormFactor.mobile
    ? showAppMobileSheet<void>(
        context: context,
        builder: (_) => const NearSwapPrivacyInfoSheet(),
      )
    : showDialog<void>(
        context: context,
        builder: (_) => const NearSwapPrivacyInfoDialog(),
      );

/// Desktop NEAR swap privacy explanation.
class NearSwapPrivacyInfoDialog extends StatelessWidget {
  const NearSwapPrivacyInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      key: const ValueKey('near_swap_privacy_info_dialog'),
      backgroundColor: colors.background.ground,
      shape: appModalShape(BorderRadius.circular(AppRadii.medium)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kNearSwapPrivacyInfoTitle,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: _Paragraphs(color: colors.text.secondary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('near_swap_privacy_info_close'),
                expand: true,
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobile NEAR swap privacy explanation.
class NearSwapPrivacyInfoSheet extends StatelessWidget {
  const NearSwapPrivacyInfoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('near_swap_privacy_info_sheet'),
      title: kNearSwapPrivacyInfoTitle,
      onClose: () => Navigator.of(context).pop(),
      leading: AppIcon(AppIcons.eye, size: 20, color: colors.icon.accent),
      constrainBody: true,
      child: SingleChildScrollView(
        child: _Paragraphs(color: colors.text.accent),
      ),
    );
  }
}

/// [kNearSwapPrivacyInfoParagraphs] in [color].
class _Paragraphs extends StatelessWidget {
  const _Paragraphs({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, paragraph)
            in kNearSwapPrivacyInfoParagraphs.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          Text(
            paragraph,
            style: AppTypography.bodyMedium.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}
