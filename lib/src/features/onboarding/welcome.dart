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

/// Welcome-specific button width. The redesigned Figma CTA stack is 256 dp
/// wide (node 1136:17519).
const double _welcomeActionWidth = 256;
const double _welcomeContentMaxWidth = 420;
const double _welcomeCardHorizontalMargin = AppSpacing.s;
const double _welcomeCardMinHeight = 520;
const double _welcomeWordmarkWidth = 93;
const double _welcomeWordmarkHeight = 35.1;

/// Onboarding entry point.
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
      // Transparent so the flutter_acrylic window effect on the native
      // surface shows through the outer gap below.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          // Only the 8 dp gap around the pane is transparent — this is
          // the strip where the native acrylic is visible.
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _Pane(
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
        ),
      ),
    );
  }
}

/// Opaque pane that owns the welcome-only top affordances.
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
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? colors.background.ground : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const topInset = AppSpacing.lg;
                const bottomInset = AppSpacing.md;
                final minHeight =
                    (constraints.maxHeight - topInset - bottomInset)
                        .clamp(0.0, double.infinity)
                        .toDouble();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    topInset,
                    0,
                    bottomInset,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _welcomeContentMaxWidth,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (showBackButton)
            const Positioned(
              left: AppSpacing.md,
              top: AppSpacing.md,
              child: _BackRow(),
            ),
          if (!showBackButton)
            Positioned(
              right: AppSpacing.md,
              top: AppSpacing.md,
              child: _WelcomeIconButton(
                key: const ValueKey('welcome_endpoint_settings_button'),
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
                key: const ValueKey('welcome_endpoint_settings_modal'),
                restartSyncAfterUpdate: false,
                onClose: onDismissEndpointSettings,
                onUpdated: onDismissEndpointSettings,
              ),
            ),
        ],
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

/// Vizor logo + title block + buttons + legal footer.
///
/// Mirrors the Figma layout hierarchy: `Content Area` owns the 24 dp outer
/// padding, this `Container` adds 64 dp top padding and centers `_Welcome
/// Content`, whose main content and legal footer are separated by 32 dp.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _welcomeCardHorizontalMargin,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? colors.background.base : colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
          boxShadow: [
            BoxShadow(
              color: colors.shadows.regular,
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _welcomeCardMinHeight),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MainWelcomeContent(),
                  SizedBox(height: AppSpacing.base),
                  _LegalFooterPlaceholder(),
                ],
              ),
            ),
          ),
        ),
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
        SizedBox(height: AppSpacing.xl),
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
        const _VizorLogo(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Private Money.\nBy default',
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Brand wordmark rendered above the title.
///
/// `VizorWordmark` owns the Figma logo frame metrics so the welcome and
/// unlock screens stay visually consistent.
class _VizorLogo extends StatelessWidget {
  const _VizorLogo();

  @override
  Widget build(BuildContext context) => const Opacity(
    opacity: 0.5,
    child: VizorWordmark(
      width: _welcomeWordmarkWidth,
      height: _welcomeWordmarkHeight,
    ),
  );
}

class _WelcomeButtonsWrap extends StatelessWidget {
  const _WelcomeButtonsWrap();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = constraints.maxWidth < _welcomeActionWidth
            ? constraints.maxWidth
            : _welcomeActionWidth;
        return SizedBox(
          width: actionWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WalletButtonsStack(actionWidth: actionWidth),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('welcome_connect_keystone_button'),
                onPressed: () => context.go('/onboarding/keystone'),
                variant: AppButtonVariant.ghost,
                minWidth: actionWidth,
                leading: const AppIcon(AppIcons.qrCodeFill, size: 18),
                child: const Text('Connect Keystone'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WalletButtonsStack extends StatelessWidget {
  const _WalletButtonsStack({required this.actionWidth});

  final double actionWidth;

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
          minWidth: actionWidth,
          leading: const AppIcon(AppIcons.addNew),
          child: const Text('Create a wallet'),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('welcome_import_wallet_button'),
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: actionWidth,
          leading: const AppIcon(AppIcons.importWallet),
          child: const Text('Import a wallet'),
        ),
      ],
    );
  }
}

class _LegalFooterPlaceholder extends StatelessWidget {
  const _LegalFooterPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.muted,
    );
    final linkStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
      decoration: TextDecoration.underline,
      decorationColor: colors.text.secondary,
    );

    return ExcludeSemantics(
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          width: 154,
          child: Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                const TextSpan(text: 'By using Vizor you agree to our '),
                TextSpan(text: 'Terms', style: linkStyle),
                const TextSpan(text: ' and '),
                TextSpan(text: 'Privacy', style: linkStyle),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
