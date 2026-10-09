import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel;

/// Title of the confirmation before private queries turn off.
const kPrivateQueriesTurnOffTitle = 'Turn off private queries?';

/// What turning private queries off does to the wallet's transparent funds.
const kPrivateQueriesTurnOffBody =
    'Vizor will discard what private recovery found and look up this '
    "wallet's transparent funds and history publicly.";

/// What the server learns once private queries are off.
const kPrivateQueriesTurnOffDisclosure =
    'The server receives every transparent address of every account and the '
    'IDs of transactions private recovery found. It can link them to each '
    'other and, without Tor, to your IP address.';

/// Asks whether to turn private queries off. Resolves to true only when the
/// user confirms. Overridable through [privateQueriesTurnOffConfirmerProvider].
typedef PrivateQueriesTurnOffConfirmer =
    Future<bool> Function(BuildContext context);

/// Overridable in tests; production shows the form factor's confirmation.
final privateQueriesTurnOffConfirmerProvider =
    Provider<PrivateQueriesTurnOffConfirmer>(
      (_) => confirmPrivateQueriesTurnOff,
    );

/// Shows the confirmation for this binary's form factor: a sheet on mobile, a
/// dialog on desktop.
Future<bool> confirmPrivateQueriesTurnOff(BuildContext context) async {
  final confirmed = kAppFormFactor == AppFormFactor.mobile
      ? await showAppMobileSheet<bool>(
          context: context,
          builder: (_) => const PrivateQueriesTurnOffSheet(),
        )
      : await showDialog<bool>(
          context: context,
          builder: (_) => const PrivateQueriesTurnOffDialog(),
        );
  return confirmed == true;
}

/// Toggles private queries, first confirming a turn-off that would send the
/// wallet's transparent lookups to the server.
Future<void> togglePrivateQueries(BuildContext context, WidgetRef ref) async {
  if (ref.read(enhancePirProvider) && !await _confirmTurnOff(context, ref)) {
    return;
  }
  if (!context.mounted) return;
  await ref.read(enhancePirProvider.notifier).toggle();
}

/// Finishes turning private queries off, after the same confirmation.
Future<void> finishPrivateQueriesTurnOff(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await _confirmTurnOff(context, ref)) return;
  if (!context.mounted) return;
  await ref.read(enhancePirProvider.notifier).finishTransparentOptOut();
}

Future<bool> _confirmTurnOff(BuildContext context, WidgetRef ref) async {
  if (!ref.read(privateQueriesTurnOffDisclosesProvider)) return true;
  return ref.read(privateQueriesTurnOffConfirmerProvider)(context);
}

class PrivateQueriesTurnOffDialog extends StatelessWidget {
  const PrivateQueriesTurnOffDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      key: const ValueKey('private_queries_turn_off_dialog'),
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
                kPrivateQueriesTurnOffTitle,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                kPrivateQueriesTurnOffBody,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                kPrivateQueriesTurnOffDisclosure,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('private_queries_turn_off_confirm'),
                expand: true,
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn off'),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                key: const ValueKey('private_queries_turn_off_cancel'),
                expand: true,
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivateQueriesTurnOffSheet extends StatelessWidget {
  const PrivateQueriesTurnOffSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('private_queries_turn_off_sheet'),
      title: kPrivateQueriesTurnOffTitle,
      onClose: () => Navigator.of(context).pop(false),
      leading: AppIcon(AppIcons.eye, size: 20, color: colors.icon.accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kPrivateQueriesTurnOffBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kPrivateQueriesTurnOffDisclosure,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.warning,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('private_queries_turn_off_confirm'),
            variant: AppButtonVariant.destructive,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off'),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
