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

import '../../../app_bootstrap.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/wallet_provider.dart';
import '../../onboarding/shared/onboarding_welcome_art.dart';

const _aboutVersionLabel = 'Version: 0.1.24 Public Beta';
const _legalUpdatedLabel = 'Last Update:  ';
const _paragraphWidth = 352.0;
const _maxSidebarPaneContentWidth = 752.0;

const _placeholderParagraph = _UtilityParagraphData(
  heading: 'From the team that brought you Keplr Wallet.',
  body:
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount - verified by cryptography, not trust.',
);

const _aboutParagraphs = [_placeholderParagraph, _placeholderParagraph];

const _legalParagraphs = [
  _placeholderParagraph,
  _placeholderParagraph,
  _placeholderParagraph,
  _placeholderParagraph,
  _placeholderParagraph,
  _placeholderParagraph,
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _UtilityBackButton(fallbackPath: '/home'),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
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
          subtitle: _aboutVersionLabel,
        ),
        SizedBox(height: AppSpacing.md),
        AppDecorativeDivider(width: 256),
        SizedBox(height: AppSpacing.md),
        _UtilityParagraphList(paragraphs: _aboutParagraphs),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: _UtilityBackButton(),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: _LegalScrollView(title: title, paragraphs: paragraphs),
          ),
        ],
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ),
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
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: Column(
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
        ),
      ),
    );
  }
}

class _UtilityBackButton extends ConsumerWidget {
  const _UtilityBackButton({this.fallbackPath});

  final String? fallbackPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Back',
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _navigateBack(context, ref),
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.chevronBackward,
                    size: 16,
                    color: colors.icon.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Back',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateBack(BuildContext context, WidgetRef ref) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(fallbackPath ?? _defaultFallbackPath(ref));
  }

  String _defaultFallbackPath(WidgetRef ref) {
    final bootstrap = ref.read(appBootstrapProvider);
    final wallet = ref.read(walletProvider).value;
    final hasWallet = wallet?.hasWallet ?? bootstrap.hasWallet;
    return hasWallet ? '/home' : '/welcome';
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

class _UtilityParagraphData {
  const _UtilityParagraphData({required this.heading, required this.body});

  final String heading;
  final String body;
}
