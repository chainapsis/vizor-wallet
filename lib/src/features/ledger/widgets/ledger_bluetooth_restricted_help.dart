import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../ledger_capability.dart';
import 'ledger_bluetooth_session.dart';

/// Settings can be inspected even when policy prevents changing permission.
/// Closing remains the primary action; this never requests permission or scans.
class LedgerBluetoothRestrictedHelp extends ConsumerWidget {
  const LedgerBluetoothRestrictedHelp({required this.model, super.key});

  final LedgerBluetoothPresentation model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!model.restricted) return const SizedBox.shrink();
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final guidance = model.access?.macOS == true
        ? 'Check Privacy & Security > Bluetooth in System Settings. This restriction may need to be changed by your administrator.'
        : model.access?.locationPermission == true
        ? 'Check location access for Vizor in Settings. Device restrictions or your administrator may prevent changes.'
        : platform == TargetPlatform.android
        ? 'Check Nearby devices access for Vizor in Settings. Device restrictions or your administrator may prevent changes.'
        : 'Check Vizor’s Bluetooth access in Settings. Device restrictions or your administrator may prevent changes.';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            guidance,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              variant: AppButtonVariant.ghost,
              constrainContent: true,
              growWithContent: true,
              onPressed: model.onOpenSettings,
              child: const Text('Open settings'),
            ),
          ),
        ],
      ),
    );
  }
}
