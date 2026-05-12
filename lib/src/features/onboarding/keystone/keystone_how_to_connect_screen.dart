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

  static const _buttonWidth = 256.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeystoneOnboardingTrailingPane(
      child: Column(
        children: [
          const KeystoneBackRow(routePath: '/welcome'),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _HeroLayout(buttonWidth: _buttonWidth, ref: ref),
          ),
        ],
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({required this.buttonWidth, required this.ref});

  final double buttonWidth;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: Center(child: _HeroBlock()),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed: () {
            ref.read(keystoneOnboardingProvider.notifier).resetScan();
            context.go(KeystoneOnboardingStep.scanQrCode.routePath);
          },
          variant: AppButtonVariant.primary,
          minWidth: buttonWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text("I'm ready now"),
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleBlock(),
        SizedBox(height: AppSpacing.base),
        _CardsRow(),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Connect Keystone',
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Prepare your Keystone wallet',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow();

  static const _width = 588.0;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _KeystoneStartCard(kind: _KeystoneStartCardKind.prep),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: _KeystoneStartCard(kind: _KeystoneStartCardKind.next),
          ),
        ],
      ),
    );
  }
}

enum _KeystoneStartCardKind { prep, next }

class _KeystoneStartCard extends StatelessWidget {
  const _KeystoneStartCard({required this.kind});

  final _KeystoneStartCardKind kind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeystoneCardTop(kind: kind),
          const SizedBox(height: AppSpacing.sm),
          _KeystoneCardContent(kind: kind),
        ],
      ),
    );
  }
}

class _KeystoneCardTop extends StatelessWidget {
  const _KeystoneCardTop({required this.kind});

  final _KeystoneStartCardKind kind;

  bool get _isPrep => kind == _KeystoneStartCardKind.prep;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 96,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: _isPrep ? colors.background.inverse : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: _isPrep ? Border.all(color: colors.border.subtleOpacity) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AppIcon(
              _isPrep ? AppIcons.importWallet : AppIcons.qr,
              size: AppIconSize.large,
              color: _isPrep ? colors.icon.inverse : colors.icon.accent,
            ),
          ),
          _CardLabelLine(
            number: _isPrep ? '1' : '2',
            label: _isPrep ? 'Before you start' : 'Next step',
            inverse: _isPrep,
          ),
        ],
      ),
    );
  }
}

class _CardLabelLine extends StatelessWidget {
  const _CardLabelLine({
    required this.number,
    required this.label,
    required this.inverse,
  });

  final String number;
  final String label;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBadge(text: number, inverse: inverse),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.codeMedium.copyWith(
            color: inverse ? colors.text.inverse : colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.text, required this.inverse});

  static const double _radius = 4;

  final String text;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 21,
      height: 21,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverse
            ? colors.background.base
            : colors.background.neutralStrongOpacity,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Text(
        text,
        style: AppTypography.codeMedium.copyWith(color: colors.text.accent),
      ),
    );
  }
}

class _KeystoneCardContent extends StatelessWidget {
  const _KeystoneCardContent({required this.kind});

  final _KeystoneStartCardKind kind;

  bool get _isPrep => kind == _KeystoneStartCardKind.prep;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isPrep ? 'Check Keystone firmware' : 'Prepare to connect',
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          if (_isPrep) const _FirmwareCardBody() else const _ConnectionSteps(),
        ],
      ),
    );
  }
}

class _FirmwareCardBody extends StatelessWidget {
  const _FirmwareCardBody();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 256,
          child: Text(
            'Check if your Keystone device has the latest version of the '
            'Cypherpunk firmware, update or install if needed.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          onPressed: _openKeystoneFirmware,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.medium,
          minWidth: 96,
          iconGap: 0,
          leading: const AppIcon(AppIcons.link),
          child: const Text('Keystone Firmware'),
        ),
      ],
    );
  }
}

class _ConnectionSteps extends StatelessWidget {
  const _ConnectionSteps();

  static const _steps = [
    'Unlock your Keystone.',
    'Tap the ... Menu, then go to Sync',
    'Open the Zcash QR Code in order to connect.',
    'Grant camera access in your laptop settings and proceed with QR code import to Vizor.',
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
