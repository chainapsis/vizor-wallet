import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';

/// NEAR swap privacy subtitle while it is on.
const kNearSwapPrivacyOnCopy = 'Swaps use one-time Zcash addresses.';

/// NEAR swap privacy subtitle while it is off and could be turned on. Swaps
/// then use a fresh address of the wallet, as hardware accounts always do.
const kNearSwapPrivacyOffCopy = 'Swaps use regular Zcash addresses.';

/// NEAR swap privacy subtitle while Private queries is off.
const kNearSwapPrivacyNeedsPrivateQueriesCopy = 'Needs Private queries.';

/// NEAR swap privacy subtitle while a hardware wallet account is active, since
/// only software accounts get one-time swap addresses.
const kNearSwapPrivacyHardwareCopy =
    'Not available for hardware wallet accounts. Their swaps use regular '
    'Zcash addresses.';

/// The NEAR swap privacy subtitle for the active account, Private queries,
/// and whether NEAR swap privacy is `enabled`.
String nearSwapPrivacyDescription({
  required bool hardwareAccount,
  required bool privateQueriesOn,
  required bool enabled,
}) => hardwareAccount
    ? kNearSwapPrivacyHardwareCopy
    : !privateQueriesOn
    ? kNearSwapPrivacyNeedsPrivateQueriesCopy
    : enabled
    ? kNearSwapPrivacyOnCopy
    : kNearSwapPrivacyOffCopy;

/// What Settings shows for NEAR swap privacy on desktop and mobile.
typedef NearSwapPrivacySetting = ({
  bool enabled,
  String description,
  bool canToggle,
  bool showHistoryCheck,
  String? transition,
});

/// The NEAR swap privacy option's state, or null when Settings doesn't offer
/// it (see [nearSwapPrivacySettingAvailableProvider]).
final nearSwapPrivacySettingProvider = Provider<NearSwapPrivacySetting?>((ref) {
  if (!ref.watch(nearSwapPrivacySettingAvailableProvider)) return null;
  // New swap addresses follow the private queries setting itself, which
  // the NEAR swap privacy switch also checks.
  final privateQueriesOn = ref.watch(enhancePirProvider);
  final enabled = ref.watch(nearSwapPrivacyProvider);
  final hardwareAccount =
      ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false;
  final changingRecovery =
      ref.watch(enhancePirTransitionProvider) == kEnhancePirChangingMessage;
  return (
    enabled: enabled,
    description: nearSwapPrivacyDescription(
      hardwareAccount: hardwareAccount,
      privateQueriesOn: privateQueriesOn,
      enabled: enabled,
    ),
    canToggle: !changingRecovery && privateQueriesOn,
    // The check is discovery's, so it needs NEAR swap privacy too.
    showHistoryCheck: !hardwareAccount && enabled,
    transition: ref.watch(nearSwapPrivacyTransitionProvider),
  );
});

/// Title of the NEAR swap privacy explanation.
const kNearSwapPrivacyInfoTitle = "What's this?";

/// Paragraphs of the NEAR swap privacy explanation.
const kNearSwapPrivacyInfoParagraphs = [
  'When you swap with NEAR Intents, your wallet gives NEAR a Zcash address for '
      'the payout and another for any refund. With NEAR swap privacy on, these '
      'are one-time addresses made just for swaps, so any future quantum '
      "adversary can't tie them to your wallet.",
  'A payout address from a quote that expired unpaid can be used again for a '
      'later quote. Rarely, two devices with the same wallet that quote at the '
      'same moment get the same address. NEAR can see that those quotes share '
      'an address, but still not which wallet it belongs to.',
  'Addresses you enter yourself, like an Ethereum address you reuse for '
      'several swaps, are still shared with NEAR and can link those swaps. '
      "Hardware wallet accounts don't use one-time addresses.",
  'Your recovery phrase still recovers everything. After a restore, turn on '
      'Private queries and NEAR swap privacy, and your wallet finds these '
      'payments privately.',
  'Turning this off keeps the funds you already have. Payouts and refunds '
      'that arrive later at these addresses show up once NEAR swap privacy is '
      'on again.',
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
