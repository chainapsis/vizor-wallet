import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../import/desktop_import_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'keystone_onboarding_flow.dart';

class KeystoneHowToConnectScreen extends ConsumerWidget {
  const KeystoneHowToConnectScreen({this.backTarget, super.key});

  final OnboardingBackTarget? backTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeystoneOnboardingTrailingPane(
      backTarget:
          backTarget ??
          OnboardingBackTarget.route(
            label: context.l10n.keystoneBackWelcome,
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
        context.go(
          desktopImportLocation(
            context,
            KeystoneOnboardingStep.scanQrCode.routePath,
          ),
        );
      },
      variant: AppButtonVariant.primary,
      minWidth: _buttonMinWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: Text(context.l10n.keystoneImReadyNow),
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
            context.l10n.keystoneConnectTitle,
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
          context.l10n.keystonePrepareSubtitle,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _KeystoneInstructionsPanel extends StatelessWidget {
  const _KeystoneInstructionsPanel();

  static const double _minHeight = 392;
  static const _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final fill = isDark ? colors.background.base : colors.background.ground;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: _minHeight),
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
      child: Column(
        children: [
          _InstructionSection(
            iconName: AppIcons.importWallet,
            stepNumber: 1,
            title: context.l10n.keystoneFirmwareTitle,
            body: null,
            action: const _FirmwareBodyWithLink(),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Divider(),
          const SizedBox(height: AppSpacing.md),
          _InstructionSection(
            iconName: AppIcons.qr,
            stepNumber: 2,
            title: context.l10n.keystonePrepareToConnectTitle,
            body: null,
            action: const _ConnectionSteps(),
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

class _FirmwareBodyWithLink extends StatelessWidget {
  const _FirmwareBodyWithLink();

  @override
  Widget build(BuildContext context) {
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: context.colors.text.primary,
    );
    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          TextSpan(text: context.l10n.keystoneFirmwareBody),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _FirmwareInlineLink(),
          ),
        ],
      ),
    );
  }
}

class _FirmwareInlineLink extends StatelessWidget {
  const _FirmwareInlineLink();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: context.l10n.keystoneFirmwareDownloadSemantics,
      child: AppButton(
        onPressed: _openKeystoneFirmware,
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.small,
        height: 24,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        iconGap: AppSpacing.xxs,
        leading: const AppIcon(AppIcons.link),
        child: Text(context.l10n.keystoneFirmwareLinkLabel),
      ),
    );
  }
}

class _ConnectionSteps extends StatelessWidget {
  const _ConnectionSteps();

  static const _markerWidth = 15.0;
  static const _markerGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConnectionStepGroup(
          title: l10n.keystoneOnYourKeystone,
          startIndex: 1,
          steps: [
            l10n.keystoneStepOpenSoftwareWallet,
            l10n.keystoneStepSelectVizor,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _ConnectionStepGroup(
          title: l10n.keystoneOnVizor,
          startIndex: 3,
          steps: [l10n.keystoneStepScanDynamicQr],
        ),
      ],
    );
  }
}

class _ConnectionStepGroup extends StatelessWidget {
  const _ConnectionStepGroup({
    required this.title,
    required this.startIndex,
    required this.steps,
  });

  final String title;
  final int startIndex;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (var i = 0; i < steps.length; i++)
          _ConnectionStepRow(
            index: startIndex + i,
            text: steps[i],
            isFirstInGroup: i == 0,
          ),
      ],
    );
  }
}

class _ConnectionStepRow extends StatelessWidget {
  const _ConnectionStepRow({
    required this.index,
    required this.text,
    required this.isFirstInGroup,
  });

  final int index;
  final String text;
  final bool isFirstInGroup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.bodyMedium.copyWith(color: colors.text.primary);
    return Padding(
      padding: EdgeInsets.only(top: isFirstInGroup ? 0 : AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _ConnectionSteps._markerWidth,
            child: Text('$index.', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _ConnectionSteps._markerGap),
          Expanded(child: Text(text, style: style)),
        ],
      ),
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
