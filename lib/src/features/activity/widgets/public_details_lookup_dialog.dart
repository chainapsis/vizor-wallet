import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal_shape.dart';

/// Asks before loading one transaction's full details from the server, which
/// learns that this wallet is interested in it. Resolves to true only when
/// the user chooses to load.
Future<bool> confirmPublicDetailsLookup(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const PublicDetailsLookupDialog(),
  );
  return confirmed == true;
}

class PublicDetailsLookupDialog extends StatelessWidget {
  const PublicDetailsLookupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      key: const ValueKey('public_details_lookup_dialog'),
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
                'Load details publicly?',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vizor will ask the server for this one transaction to show '
                'what private lookups leave out.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The server learns that this wallet is interested in this '
                'transaction, and without Tor, your IP address.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('public_details_lookup_confirm'),
                expand: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Load publicly'),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                key: const ValueKey('public_details_lookup_cancel'),
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
