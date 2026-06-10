import 'dart:async';

import 'package:flutter/material.dart'
    show
        Scaffold,
        Scrollbar,
        ScrollbarTheme,
        ScrollbarThemeData,
        WidgetStatePropertyAll;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_bootstrap.dart';
import '../../../core/config/app_version_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/wallet_provider.dart';
import '../../onboarding/shared/onboarding_welcome_art.dart';

const _utilityPageScrollbarKey = ValueKey('utility-page-scrollbar');
const _legalUpdatedLabel = 'Last Update:  ';
const _utilityContentWidth = 420.0;
const _vizorGithubUrl = 'https://github.com/chainapsis/vizor-wallet/';
const _vizorWebsiteUrl = 'https://vizor.cash';

const _aboutParagraphs = [
  _UtilityParagraphData(
    heading: 'Built by the Keplr team',
    body:
        'We built Keplr, the wallet used by millions across Cosmos, Ethereum, '
        'and Bitcoin. Vizor is our take on what a Zcash wallet should feel '
        'like.',
  ),
  _UtilityParagraphData(
    heading: 'Designed for shielded Zcash',
    body:
        'Vizor is built around shielded transactions, where the sender, '
        'recipient, and amount stay private. Transparent Zcash works too, but '
        'private is the default here.',
  ),
  _UtilityParagraphData(
    heading: 'Open source, verifiable, and self-custodial',
    body:
        "Vizor is Apache licensed. Your keys stay on your device. We don't "
        "see your balances or your transactions.",
  ),
];

const _legalPlaceholderParagraph = _UtilityParagraphData(
  heading: 'From the team that brought you Keplr Wallet.',
  body:
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the '
      'sender, recipient, and amount.',
);

const _legalParagraphs = [
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: const _UtilityPane(
          toolbar: AppPaneToolbar(),
          child: _AboutContent(),
        ),
      ),
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Terms of Use',
      paragraphs: _legalParagraphs,
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Privacy Policy',
      paragraphs: _legalParagraphs,
    );
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(opacity: 0.5, child: VizorWordmark(width: 74, height: 27.925)),
        SizedBox(height: AppSpacing.base),
        _UtilityPageTitle(
          title: 'About Vizor Wallet',
          subtitle: kVizorAboutVersionLabel,
        ),
        SizedBox(height: AppSpacing.base),
        _UtilitySurface(
          child: _UtilityParagraphList(paragraphs: _aboutParagraphs),
        ),
        SizedBox(height: AppSpacing.base),
        _AboutLinkRow(),
      ],
    );
  }
}

class _LegalScreen extends StatelessWidget {
  const _LegalScreen({required this.title, required this.paragraphs});

  final String title;
  final List<_UtilityParagraphData> paragraphs;

  @override
  Widget build(BuildContext context) {
    return _FullPaneShell(
      child: _UtilityPane(
        toolbar: const AppPaneToolbar(leading: _UtilityBackButton()),
        child: _LegalContent(title: title, paragraphs: paragraphs),
      ),
    );
  }
}

class _FullPaneShell extends StatelessWidget {
  const _FullPaneShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.macosUtility.window,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(padding: EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class _UtilityPane extends StatefulWidget {
  const _UtilityPane({required this.toolbar, required this.child});

  final Widget toolbar;
  final Widget child;

  @override
  State<_UtilityPane> createState() => _UtilityPaneState();
}

class _UtilityPaneState extends State<_UtilityPane> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.toolbar,
        Expanded(
          child: _UtilityScrollbar(
            controller: _scrollController,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _scrollController,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s,
                        vertical: AppSpacing.sm,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _utilityContentWidth,
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UtilityScrollbar extends StatelessWidget {
  const _UtilityScrollbar({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(colors.background.overlay),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadii.full),
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(false),
        crossAxisMargin: 3,
        mainAxisMargin: 3,
      ),
      child: Scrollbar(
        key: _utilityPageScrollbarKey,
        controller: controller,
        child: child,
      ),
    );
  }
}

class _UtilityBackButton extends ConsumerWidget {
  const _UtilityBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBackLink(
      label: 'Back',
      semanticsLabel: context.canPop()
          ? 'Back'
          : 'Back to ${_defaultFallbackLabel(ref)}',
      onTap: () => _navigateBack(context, ref),
    );
  }

  void _navigateBack(BuildContext context, WidgetRef ref) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_defaultFallbackPath(ref));
  }

  String _defaultFallbackPath(WidgetRef ref) {
    return _hasWallet(ref) ? '/home' : '/welcome';
  }

  String _defaultFallbackLabel(WidgetRef ref) {
    return _hasWallet(ref) ? 'Home' : 'Welcome';
  }

  bool _hasWallet(WidgetRef ref) {
    final bootstrap = ref.read(appBootstrapProvider);
    final wallet = ref.read(walletProvider).value;
    return wallet?.hasWallet ?? bootstrap.hasWallet;
  }
}

class _LegalContent extends StatelessWidget {
  const _LegalContent({required this.title, required this.paragraphs});

  final String title;
  final List<_UtilityParagraphData> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _UtilityPageTitle(title: title, subtitle: _legalUpdatedLabel),
        const SizedBox(height: AppSpacing.base),
        _UtilitySurface(child: _UtilityParagraphList(paragraphs: paragraphs)),
      ],
    );
  }
}

class _UtilityPageTitle extends StatelessWidget {
  const _UtilityPageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
        ),
      ],
    );
  }
}

class _UtilityParagraphList extends StatelessWidget {
  const _UtilityParagraphList({required this.paragraphs});

  final List<_UtilityParagraphData> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          _UtilityParagraph(paragraph: paragraphs[i]),
          if (i < paragraphs.length - 1) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _UtilitySurface extends StatelessWidget {
  const _UtilitySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: AppTheme.of(context) == AppThemeData.light
            ? colors.background.ground
            : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _utilitySurfaceShadow(context),
      ),
      child: child,
    );
  }
}

List<BoxShadow> _utilitySurfaceShadow(BuildContext context) {
  final color = AppTheme.of(context) == AppThemeData.light
      ? const Color(0x0D141818)
      : const Color(0x00141818);
  return [
    BoxShadow(color: color, blurRadius: 1),
    BoxShadow(color: color, offset: const Offset(0, 1), blurRadius: 2),
    BoxShadow(color: color, offset: const Offset(0, 2), blurRadius: 4),
    BoxShadow(color: color, blurRadius: 1),
  ];
}

class _UtilityParagraph extends StatelessWidget {
  const _UtilityParagraph({required this.paragraph});

  final _UtilityParagraphData paragraph;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paragraph.heading,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          paragraph.body,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
        ),
      ],
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _AboutLinkButton(
            label: 'GitHub',
            semanticsLabel: 'Open Vizor GitHub',
            url: _vizorGithubUrl,
          ),
          _AboutLinkButton(
            label: 'Website',
            semanticsLabel: 'Open Vizor website',
            url: _vizorWebsiteUrl,
          ),
        ],
      ),
    );
  }
}

class _AboutLinkButton extends StatelessWidget {
  const _AboutLinkButton({
    required this.label,
    required this.semanticsLabel,
    required this.url,
  });

  final String label;
  final String semanticsLabel;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: semanticsLabel,
      child: AppButton(
        onPressed: () => unawaited(_launchAboutUrl(url)),
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.medium,
        leading: const AppIcon(AppIcons.link),
        child: Text(label),
      ),
    );
  }
}

Future<void> _launchAboutUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Exception {
    // External links are best-effort from this utility page.
  }
}

class _UtilityParagraphData {
  const _UtilityParagraphData({required this.heading, required this.body});

  final String heading;
  final String body;
}
