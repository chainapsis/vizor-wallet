import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'keystone_onboarding_flow.dart';

class KeystoneHowToConnectScreen extends ConsumerWidget {
  const KeystoneHowToConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeystoneOnboardingTrailingPane(
      backTarget: const OnboardingBackTarget.route(
        label: 'Welcome',
        routePath: '/welcome',
      ),
      bodyPadding: EdgeInsets.zero,
      child: _HeroLayout(ref: ref),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({required this.ref});

  final WidgetRef ref;

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  children: [
                    const Expanded(child: _OnPageContent()),
                    _ButtonStack(ref: ref),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent();

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TitleBlock(),
        SizedBox(height: _sectionGap),
        _KeystoneInstructionsPanel(),
      ],
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack({required this.ref});

  final WidgetRef ref;

  static const double _buttonMinWidth = 196;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () {
        ref.read(keystoneOnboardingProvider.notifier).resetScan();
        context.go(KeystoneOnboardingStep.scanQrCode.routePath);
      },
      variant: AppButtonVariant.primary,
      minWidth: _buttonMinWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text("I'm ready now"),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Connect Keystone',
            style: AppTypography.displayLarge.copyWith(
              fontFamily: 'Young Serif',
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Prepare your Keystone wallet',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _KeystoneInstructionsPanel extends StatelessWidget {
  const _KeystoneInstructionsPanel();

  static const double _height = 392;
  static const _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final fill = isDark ? colors.background.base : colors.background.ground;

    return Container(
      width: double.infinity,
      height: _height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: const Column(
        children: [
          _InstructionSection(
            iconName: AppIcons.importWallet,
            stepNumber: 1,
            title: 'Check Keystone firmware',
            body:
                'Check if your Keystone device has the latest version of '
                'the Cypherpunk firmware, update or install if needed.',
            action: _FirmwareButton(),
          ),
          SizedBox(height: AppSpacing.md),
          _Divider(),
          SizedBox(height: AppSpacing.md),
          _InstructionSection(
            iconName: AppIcons.qr,
            stepNumber: 2,
            title: 'Prepare to connect',
            body: null,
            action: _ConnectionSteps(),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.border.regular,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: const SizedBox(height: 1, width: double.infinity),
    );
  }
}

class _InstructionSection extends StatelessWidget {
  const _InstructionSection({
    required this.iconName,
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.action,
  });

  final String iconName;
  final int stepNumber;
  final String title;
  final String? body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InstructionHeader(
            iconName: iconName,
            stepNumber: stepNumber,
            title: title,
          ),
          if (body case final body?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          action,
        ],
      ),
    );
  }
}

class _InstructionHeader extends StatelessWidget {
  const _InstructionHeader({
    required this.iconName,
    required this.stepNumber,
    required this.title,
  });

  final String iconName;
  final int stepNumber;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        AppIcon(iconName, size: 24, color: colors.icon.accent),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            '$stepNumber. $title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FirmwareButton extends StatelessWidget {
  const _FirmwareButton();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AppButton(
        onPressed: _openKeystoneFirmware,
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.medium,
        minWidth: 96,
        iconGap: 0,
        leading: const AppIcon(AppIcons.link),
        child: const Text('Keystone Firmware'),
      ),
    );
  }
}

class _ConnectionSteps extends StatelessWidget {
  const _ConnectionSteps();

  static const _steps = [
    'Unlock your Keystone.',
    'Tap the ... Menu, then go to Sync',
    'Open the Zcash QR Code in order to connect.',
    'Grant camera access in your laptop settings and proceed with QR code '
        'import to Vizor.',
  ];

  static const _markerWidth = 15.0;
  static const _markerGap = 6.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          _ConnectionStepRow(index: i + 1, text: _steps[i]),
      ],
    );
  }
}

class _ConnectionStepRow extends StatelessWidget {
  const _ConnectionStepRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.bodyMedium.copyWith(color: colors.text.primary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _ConnectionSteps._markerWidth,
          child: Text('$index.', style: style, textAlign: TextAlign.right),
        ),
        const SizedBox(width: _ConnectionSteps._markerGap),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

void _openKeystoneFirmware() {
  unawaited(_launchKeystoneFirmware());
}

Future<void> _launchKeystoneFirmware() async {
  try {
    await launchUrl(
      Uri.parse('https://keyst.one/firmware'),
      mode: LaunchMode.externalApplication,
    );
  } on Exception {
    // Opening the external firmware page is best-effort.
  }
}
