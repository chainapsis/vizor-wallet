import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_pane_modal_overlay.dart';
import '../../core/widgets/app_tooltip.dart';
import '../settings/widgets/custom_endpoint_settings_panel.dart';
import 'shared/onboarding_welcome_art.dart';

const double _welcomeCanvasHeight = 720;
const double _welcomePaneWidth = 420;
const double _welcomeActionWidth = 196;
const double _welcomeBackButtonTop = AppSpacing.base + AppSpacing.xs;

/// Onboarding entry point — Figma `_Welcome` at node 4034:62997
/// (light) / 4363:117257 (dark).
///
/// The screen targets the large (landscape) desktop layout by design.
/// On entry it asks [AppLayoutNotifier] to switch to
/// [AppLayoutMode.large] so a user who had previously toggled the window
/// into small can still come back through onboarding.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _showEndpointSettings = false;

  @override
  void initState() {
    super.initState();
    // Post-frame so the provider mutation doesn't clash with the current
    // build (Riverpod forbids state writes during build). `setMode` is
    // idempotent when the mode already matches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _Pane(
        showBackButton: widget.showBackButton,
        showEndpointSettings: _showEndpointSettings,
        onShowEndpointSettings: () {
          setState(() {
            _showEndpointSettings = true;
          });
        },
        onDismissEndpointSettings: () {
          setState(() {
            _showEndpointSettings = false;
          });
        },
        child: const _Content(),
      ),
    );
  }
}

/// Responsive welcome layout from the 1080 x 720 Figma baseline.
///
/// The Figma file includes macOS wallpaper, menu bar, dock, and window
/// controls around this node. Per AGENTS.md those layers are OS chrome and
/// are ignored; the implemented app starts at `Window Contents > Trailing
/// Pane`, with a fixed 420px lead pane and a responsive trailing hero pane.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.child,
    required this.showBackButton,
    required this.showEndpointSettings,
    required this.onShowEndpointSettings,
    required this.onDismissEndpointSettings,
  });

  final Widget child;
  final bool showBackButton;
  final bool showEndpointSettings;
  final VoidCallback onShowEndpointSettings;
  final VoidCallback onDismissEndpointSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colors.background.ground,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final heroWidth = (constraints.maxWidth - _welcomePaneWidth)
                    .clamp(0.0, double.infinity);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: _welcomePaneWidth,
                      height: constraints.maxHeight,
                      child: child,
                    ),
                    Positioned(
                      left: _welcomePaneWidth,
                      top: 0,
                      width: heroWidth,
                      height: constraints.maxHeight,
                      child: _WelcomeHeroPane(
                        width: heroWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                    if (!showBackButton)
                      Positioned(
                        right: AppSpacing.md,
                        top: AppSpacing.md,
                        child: _WelcomeIconButton(
                          key: ValueKey('welcome_endpoint_settings_button'),
                          icon: AppIcons.cog,
                          tooltip: 'Endpoint settings',
                          semanticLabel: 'Endpoint settings',
                          onTap: onShowEndpointSettings,
                        ),
                      ),
                    if (!showBackButton && showEndpointSettings)
                      AppPaneModalOverlay(
                        borderRadius: BorderRadius.circular(AppRadii.xSmall),
                        onDismiss: onDismissEndpointSettings,
                        child: CustomEndpointSettingsPanel(
                          key: const ValueKey(
                            'welcome_endpoint_settings_modal',
                          ),
                          restartSyncAfterUpdate: false,
                          onClose: onDismissEndpointSettings,
                          onUpdated: onDismissEndpointSettings,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (showBackButton)
            const Positioned(
              left: AppSpacing.md,
              top: _welcomeBackButtonTop,
              child: _BackRow(),
            ),
        ],
      ),
    );
  }
}

class _WelcomeHeroPane extends StatelessWidget {
  const _WelcomeHeroPane({required this.width, required this.height});

  static final _foregroundColor = AppTextColors.light.inverse;
  static const _textBottomInset = _welcomeCanvasHeight - 493;
  static const _wordmarkTopInset = _welcomeCanvasHeight - 628;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/welcome_hero_dark.png'
        : 'assets/illustrations/welcome_hero_light.png';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: Transform.flip(
                flipX: true,
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [Colors.transparent, Color(0xFF1D1D1D)],
                    stops: const [0.47237, 0.97439],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: height - _textBottomInset,
              child: Text(
                'Private money.\nBy default',
                textAlign: TextAlign.center,
                style: AppTypography.displayMedium.copyWith(
                  color: _foregroundColor,
                  height: 48 / 45,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: height - _wordmarkTopInset,
              child: Center(
                child: VizorWordmark(
                  width: 96,
                  height: 36,
                  color: _foregroundColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeIconButton extends StatefulWidget {
  const _WelcomeIconButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_WelcomeIconButton> createState() => _WelcomeIconButtonState();
}

class _WelcomeIconButtonState extends State<_WelcomeIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: ExcludeSemantics(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _hovered
                      ? colors.button.ghost.bgHover
                      : colors.background.ground.withValues(alpha: 0),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AppIcon(
                      widget.icon,
                      size: AppIconSize.medium,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.canPop() ? context.pop() : context.go('/home'),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
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
    );
  }
}

/// Badge + title + buttons from the Figma left welcome pane, with the
/// legal footer pinned to the pane bottom (Figma: text bottom 45px above
/// the pane edge — 13px inside the 32px vertical padding).
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      child: Stack(
        children: [
          Center(child: _MainWelcomeContent()),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 13),
              child: _LegalFooter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalFooter extends StatefulWidget {
  const _LegalFooter();

  @override
  State<_LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<_LegalFooter> {
  // `from=onboarding` keeps the legal pages on the bare full pane (no
  // sidebar) even when a wallet exists (the /add-account variant).
  late final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => context.push('/terms?from=onboarding');
  late final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer()
    ..onTap = () => context.push('/privacy?from=onboarding');

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodySmall.copyWith(
      color: context.colors.text.muted,
    );
    final linkStyle = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: context.colors.text.muted,
    );
    return SizedBox(
      width: 154,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'By using Vizor you agree to our '),
            TextSpan(
              text: 'Terms',
              style: linkStyle,
              recognizer: _termsRecognizer,
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy',
              style: linkStyle,
              recognizer: _privacyRecognizer,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _MainWelcomeContent extends StatelessWidget {
  const _MainWelcomeContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleBlock(),
        SizedBox(height: AppSpacing.base),
        _WelcomeButtonsWrap(),
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
        Image.asset(
          'assets/illustrations/welcome_badge.png',
          width: 50,
          height: 50,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 218,
          child: Text(
            'Get started\nwith Vizor',
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
              height: 33 / 32,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _WelcomeButtonsWrap extends StatelessWidget {
  const _WelcomeButtonsWrap();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _WalletButtonsStack(),
        const SizedBox(height: AppSpacing.md),
        const _OrDivider(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('welcome_connect_keystone_button'),
          onPressed: () => context.go('/onboarding/keystone'),
          variant: AppButtonVariant.ghost,
          minWidth: _welcomeActionWidth,
          leading: const AppIcon(AppIcons.qrCodeFill, size: 18),
          child: const Text('Connect Keystone'),
        ),
      ],
    );
  }
}

class _WalletButtonsStack extends StatelessWidget {
  const _WalletButtonsStack();

  @override
  Widget build(BuildContext context) {
    // Both buttons carry the same minWidth so they render identical
    // widths even when their labels differ in length; Column picks up
    // the larger child's intrinsic width and applies it to both.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          key: const ValueKey('welcome_create_wallet_button'),
          onPressed: () => context.go('/onboarding/intro'),
          variant: AppButtonVariant.primary,
          minWidth: _welcomeActionWidth,
          leading: const AppIcon(AppIcons.addNew),
          child: const Text('Create a wallet'),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('welcome_import_wallet_button'),
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: _welcomeActionWidth,
          leading: const AppIcon(AppIcons.importWallet),
          child: const Text('Import a wallet'),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: _welcomeActionWidth,
      height: 14,
      child: Row(
        children: [
          Expanded(child: _OrDividerLine(color: colors.border.regular)),
          const SizedBox(width: AppSpacing.s),
          Text(
            'OR',
            style: AppTypography.labelSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: _OrDividerLine(color: colors.border.regular)),
        ],
      ),
    );
  }
}

class _OrDividerLine extends StatelessWidget {
  const _OrDividerLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        // Current `_Divider` component: 1.5px hairline pill.
        child: const SizedBox(height: 1.5, width: double.infinity),
      ),
    );
  }
}
