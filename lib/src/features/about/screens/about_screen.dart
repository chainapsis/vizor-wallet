import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Colors,
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
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../providers/wallet_provider.dart';
import '../../onboarding/shared/onboarding_welcome_art.dart';

const _utilityPageScrollbarKey = ValueKey('utility-page-scrollbar');
const _backLinkContentGap = AppSpacing.s;
const _legalUpdatedLabel = 'Last Update:  ';
const _paragraphWidth = 352.0;
const _maxSidebarPaneContentWidth = 752.0;
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
        child: const _AboutScrollView(),
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
        _UtilityPageTitle(
          title: 'About Vizor Wallet',
          subtitle: kVizorAboutVersionLabel,
        ),
        SizedBox(height: AppSpacing.md),
        AppDecorativeDivider(width: 256),
        SizedBox(height: AppSpacing.md),
        _UtilityParagraphList(paragraphs: _aboutParagraphs),
        _AboutLinkRow(),
        SizedBox(height: AppSpacing.md),
        VizorWordmark(width: 74, height: 27.925),
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
      child: _LegalScrollView(title: title, paragraphs: paragraphs),
    );
  }
}

class _FullPaneShell extends StatelessWidget {
  const _FullPaneShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(padding: EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class _AboutScrollView extends StatefulWidget {
  const _AboutScrollView();

  @override
  State<_AboutScrollView> createState() => _AboutScrollViewState();
}

class _AboutScrollViewState extends State<_AboutScrollView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UtilityScrollbar(
      controller: _scrollController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AppRouteBackLink(),
                    ),
                    const SizedBox(height: _backLinkContentGap),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          constraints.maxHeight -
                              (AppSpacing.md * 2) -
                              AppBackLink.height -
                              _backLinkContentGap,
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _maxSidebarPaneContentWidth,
                          ),
                          child: const _AboutContent(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LegalScrollView extends StatefulWidget {
  const _LegalScrollView({required this.title, required this.paragraphs});

  final String title;
  final List<_UtilityParagraphData> paragraphs;

  @override
  State<_LegalScrollView> createState() => _LegalScrollViewState();
}

class _LegalScrollViewState extends State<_LegalScrollView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UtilityScrollbar(
      controller: _scrollController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: _UtilityBackButton(),
                    ),
                    const SizedBox(height: _backLinkContentGap),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _UtilityPageTitle(
                            title: widget.title,
                            subtitle: _legalUpdatedLabel,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const AppDecorativeDivider(width: 256),
                          const SizedBox(height: AppSpacing.md),
                          _UtilityParagraphList(paragraphs: widget.paragraphs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
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
    return SizedBox(
      width: _paragraphWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < paragraphs.length; i++) ...[
              _UtilityParagraph(paragraph: paragraphs[i]),
              if (i < paragraphs.length - 1)
                const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
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
      width: _paragraphWidth,
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _AboutTextLink(
            label: 'GitHub',
            semanticsLabel: 'Open Vizor GitHub',
            url: _vizorGithubUrl,
          ),
          _AboutTextLink(
            label: 'Website',
            semanticsLabel: 'Open Vizor website',
            url: _vizorWebsiteUrl,
          ),
        ],
      ),
    );
  }
}

class _AboutTextLink extends StatefulWidget {
  const _AboutTextLink({
    required this.label,
    required this.semanticsLabel,
    required this.url,
  });

  final String label;
  final String semanticsLabel;
  final String url;

  @override
  State<_AboutTextLink> createState() => _AboutTextLinkState();
}

class _AboutTextLinkState extends State<_AboutTextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textColor = colors.text.accent;
    return Semantics(
      button: true,
      link: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_launchAboutUrl(widget.url)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              widget.label,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                decoration: _hovered
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: textColor,
              ),
            ),
          ),
        ),
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
