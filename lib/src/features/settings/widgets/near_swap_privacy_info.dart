import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import 'swap_history_check_control.dart';

/// Which subtitle the NEAR swap privacy option shows.
enum NearSwapPrivacyDescription {
  /// The setting is on.
  on,

  /// The setting is off and could be turned on. Swaps then use a fresh address
  /// of the wallet, as hardware accounts always do.
  off,

  /// The saved choice couldn't be read.
  unknown,

  /// A hardware wallet account is active, and only software accounts get
  /// one-time swap addresses.
  hardware;

  /// The subtitle in the display language.
  String text(AppLocalizations l10n) => switch (this) {
    NearSwapPrivacyDescription.on => l10n.settingsNearSwapPrivacyOn,
    NearSwapPrivacyDescription.off => l10n.settingsNearSwapPrivacyOff,
    NearSwapPrivacyDescription.unknown => l10n.settingsNearSwapPrivacyUnknown,
    NearSwapPrivacyDescription.hardware => l10n.settingsNearSwapPrivacyHardware,
  };
}

/// What Settings shows for NEAR swap privacy on desktop and mobile.
typedef NearSwapPrivacySetting = ({
  bool enabled,
  NearSwapPrivacyDescription description,
  EnhancePirTransition? transition,
});

/// The NEAR swap privacy option's state, or null when Settings doesn't offer
/// it (see [nearSwapPrivacySettingAvailableProvider]).
final nearSwapPrivacySettingProvider = Provider<NearSwapPrivacySetting?>((ref) {
  if (!ref.watch(nearSwapPrivacySettingAvailableProvider)) return null;
  final enabled = ref.watch(nearSwapPrivacyProvider);
  final hardwareAccount =
      ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false;
  return (
    enabled: enabled ?? false,
    description: enabled == null
        ? NearSwapPrivacyDescription.unknown
        : hardwareAccount
        ? NearSwapPrivacyDescription.hardware
        : enabled
        ? NearSwapPrivacyDescription.on
        : NearSwapPrivacyDescription.off,
    transition: ref.watch(nearSwapPrivacyTransitionProvider),
  );
});

/// Paragraphs of the NEAR swap privacy explanation.
List<String> nearSwapPrivacyInfoParagraphs(AppLocalizations l10n) => [
  l10n.settingsNearSwapPrivacyInfoOneTime,
  l10n.settingsNearSwapPrivacyInfoReuse,
  l10n.settingsNearSwapPrivacyInfoOwnAddresses,
  l10n.settingsNearSwapPrivacyInfoRestore,
  l10n.settingsNearSwapPrivacyInfoTurnOff,
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
                context.l10n.commonWhatsThis,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: _Body(color: colors.text.secondary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('near_swap_privacy_info_close'),
                expand: true,
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.commonClose),
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
      title: context.l10n.commonWhatsThis,
      onClose: () => Navigator.of(context).pop(),
      leading: AppIcon(AppIcons.eye, size: 20, color: colors.icon.accent),
      constrainBody: true,
      child: SingleChildScrollView(child: _Body(color: colors.text.accent)),
    );
  }
}

/// [nearSwapPrivacyInfoParagraphs] in [color], then the troubleshooting
/// section with the swap history check while Settings offers NEAR swap
/// privacy and the wallet has a software account, whatever the setting says.
class _Body extends ConsumerWidget {
  const _Body({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final showHistoryCheck =
        ref.watch(nearSwapPrivacySettingAvailableProvider) &&
        (ref
                .watch(accountProvider)
                .value
                ?.accounts
                .any((account) => !account.isHardware) ??
            false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, paragraph) in nearSwapPrivacyInfoParagraphs(
          context.l10n,
        ).indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          Text(
            paragraph,
            style: AppTypography.bodyMedium.copyWith(color: color),
          ),
        ],
        if (showHistoryCheck) ...[
          const SizedBox(height: AppSpacing.md),
          Column(
            key: const ValueKey('near_swap_privacy_troubleshooting'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.settingsNearSwapPrivacyTroubleshootingTitle,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.settingsNearSwapPrivacyTroubleshootingBody,
                style: AppTypography.bodyMedium.copyWith(color: color),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The provider owns the check, so closing the explanation
              // leaves a running or saved one going.
              const SwapHistoryCheckControl(),
            ],
          ),
        ],
      ],
    );
  }
}
