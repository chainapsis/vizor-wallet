import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_bootstrap.dart';
import '../../../core/config/app_version_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/navigation/app_back_resolver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/wallet_provider.dart';
import '../../onboarding/shared/onboarding_welcome_art.dart';

const _utilityContentWidth = 420.0;
const _vizorGithubUrl = 'https://github.com/chainapsis/vizor-wallet/';
const _vizorWebsiteUrl = 'https://vizor.cash';

// Body copy mirrors the Figma About frame (4086:478836) verbatim, including
// the duplicated third heading and the unterminated first two sentences —
// fix the design file first if those change.
const _aboutParagraphs = [
  _UtilityParagraphData(
    heading: 'Built by the Keplr team',
    body:
        'We built Keplr, the wallet used by millions across Cosmos, Ethereum, '
        'and Bitcoin. Vizor is our take on what a Zcash wallet should feel',
  ),
  _UtilityParagraphData(
    heading: 'Designed for shielded Zcash',
    body:
        'Vizor is built around shielded transactions, where the sender, '
        'recipient, and amount stay private. Transparent Zcash works too, but '
        'private is the default',
  ),
  _UtilityParagraphData(
    heading: 'Designed for shielded Zcash',
    body:
        'Vizor is Apache licensed. Your keys stay on your device.\n'
        "We don't see your balances or your transactions.",
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
          // Design: back chevron sits 16px into the pane, same as settings.
          // The 16px inset is the AppPaneToolbar default.
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
      title: 'Terms of Usage',
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

class _LegalScreen extends ConsumerWidget {
  const _LegalScreen({required this.title, required this.paragraphs});

  final String title;
  final List<_UtilityParagraphData> paragraphs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = _UtilityPane(
      toolbar: const AppPaneToolbar(
        // The 16px inset is the AppPaneToolbar default.
        leading: _UtilityBackButton(),
      ),
      child: _LegalContent(title: title, paragraphs: paragraphs),
    );

    // In the design these pages live inside the regular desktop shell with
    // the glass nav sidebar. Pre-wallet they are public legal routes, so
    // there is no account/sidebar context to show — fall back to the bare
    // full-width pane.
    if (_hasWallet(ref)) {
      return AppDesktopShell(
        sidebar: const AppMainSidebar(),
        pane: AppDesktopPane(padding: EdgeInsets.zero, child: pane),
      );
    }
    return _FullPaneShell(child: pane);
  }
}

bool _hasWallet(WidgetRef ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  final wallet = ref.watch(walletProvider).value;
  return wallet?.hasWallet ?? bootstrap.hasWallet;
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

class _UtilityPane extends StatelessWidget {
  const _UtilityPane({required this.toolbar, required this.child});

  final Widget toolbar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPaneScrollScaffold(
      toolbar: toolbar,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _utilityContentWidth),
          child: child,
        ),
      ),
    );
  }
}

class _UtilityBackButton extends ConsumerWidget {
  const _UtilityBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirror the standard pane toolbar: the back link is labeled with its
    // destination ("Settings", "Home", ...), never a generic "Back".
    if (context.canPop()) {
      final target = AppBackResolver.resolve(context);
      return AppBackLink(
        label: target.label,
        onTap: () => target.navigate(context),
      );
    }
    final hasWallet = _hasWallet(ref);
    final label = hasWallet ? 'Home' : 'Welcome';
    final path = hasWallet ? '/home' : '/welcome';
    return AppBackLink(label: label, onTap: () => context.go(path));
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
        _UtilityPageTitle(title: title, subtitle: kVizorAboutVersionLabel),
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
        // Figma: semantic/foreground/neutral/ground in both modes
        // (#ffffff light, #1b1f1f dark).
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _utilitySurfaceShadow(colors),
      ),
      child: child,
    );
  }
}

// Figma "Shadow Surface" — four layers of Semantic/Shadows/Subtle
// (alpha 0 in dark mode, so the card reads from fill contrast alone).
List<BoxShadow> _utilitySurfaceShadow(AppColors colors) {
  return [
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
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.xs,
        children: [
          _AboutLinkButton(
            label: 'Github',
            icon: AppIcons.github,
            semanticsLabel: 'Open Vizor GitHub',
            url: _vizorGithubUrl,
          ),
          _AboutLinkButton(
            label: 'Website',
            icon: AppIcons.globe,
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
    required this.icon,
    required this.semanticsLabel,
    required this.url,
  });

  // Figma buttons stack: 24px ghost pills with a 16px icon and Label M.
  static const _height = 24.0;

  final String label;
  final String icon;
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
        height: _height,
        leading: AppIcon(icon),
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
