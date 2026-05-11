import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'keystone_onboarding_flow.dart';

class KeystoneHowToConnectScreen extends ConsumerWidget {
  const KeystoneHowToConnectScreen({super.key});

  static const _contentWidth = 460.0;
  static const _buttonWidth = 256.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return KeystoneOnboardingTrailingPane(
      child: Column(
        children: [
          const KeystoneBackRow(routePath: '/welcome'),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Center(
              child: SizedBox(
                width: _contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Connect your Keystone',
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: 360,
                      child: Text(
                        'Prepare your Keystone and your desktop to start.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _InstructionList(),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: _buttonWidth,
            child: AppButton(
              onPressed: () {
                ref.read(keystoneOnboardingProvider.notifier).resetScan();
                context.go(KeystoneOnboardingStep.scanQrCode.routePath);
              },
              variant: AppButtonVariant.primary,
              minWidth: _buttonWidth,
              trailing: const AppIcon(AppIcons.chevronForward),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionList extends StatelessWidget {
  const _InstructionList();

  static const _steps = [
    'Unlock your Keystone.',
    'Tap the menu, then go to Sync.',
    'Open the Zcash QR Code in order to connect.',
    'Grant camera access on this device and proceed with QR code import to Vizor.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _InstructionRow(index: i + 1, text: _steps[i]),
          if (i != _steps.length - 1) const SizedBox(height: AppSpacing.s),
        ],
      ],
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.full),
            color: colors.background.overlay.withValues(alpha: 0.35),
          ),
          child: Text(
            '$index',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
