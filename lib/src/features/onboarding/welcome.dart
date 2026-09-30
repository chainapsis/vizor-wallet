import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_pane_modal_overlay.dart';
import '../../core/widgets/app_tooltip.dart';
import '../../providers/enhance_pir_provider.dart';
import '../settings/widgets/custom_endpoint_settings_panel.dart';
import 'shared/onboarding_welcome_art.dart';
import 'shared/welcome_accent_button.dart';
import 'shared/welcome_button_tokens.dart';
import 'shared/welcome_video_backdrop.dart';

const kDesktopWelcomeVideoAsset = 'assets/animations/desktop_welcome.mp4';
const kDesktopWelcomeAnimatedImageAsset =
    'assets/animations/desktop_welcome.webp';
const kDesktopWelcomePosterAsset =
    'assets/illustrations/desktop_welcome_poster.webp';
const double _welcomePaneWidth = 420;
const double _welcomeBackButtonTop = AppSpacing.base + AppSpacing.xs;

/// Figma Welcome (8648:104679), without the presentation-only OS chrome.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({
    super.key,
    this.showBackButton = false,
    this.showNetworkSettingsInitially = false,
    this.animateBackground = true,
  });

  final bool showBackButton;
  final bool showNetworkSettingsInitially;
  final bool animateBackground;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late bool _showEndpointSettings;

  @override
  void initState() {
    super.initState();
    _showEndpointSettings = widget.showNetworkSettingsInitially;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _dismissEndpointSettings() {
    if (ref.read(enhancePirTransitionProvider) == 'Changing setting…') return;
    setState(() => _showEndpointSettings = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff000000),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxHeight / 720;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 75 * scale + (constraints.maxWidth - 1080 * scale) / 2,
              top: 0,
              width: 1280 * scale,
              height: constraints.maxHeight,
              child: WelcomeVideoBackdrop(
                videoAsset: kDesktopWelcomeVideoAsset,
                posterAsset: kDesktopWelcomePosterAsset,
                animatedImageAsset: kDesktopWelcomeAnimatedImageAsset,
                animate: widget.animateBackground,
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xff000000),
                        Color(0x80000000),
                        Color(0x4d000000),
                        Color(0x00000000),
                      ],
                      stops: [0.13333, 0.43813, 0.56875, 0.65583],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: math.min(_welcomePaneWidth, constraints.maxWidth),
              height: constraints.maxHeight,
              child: ExcludeFocus(
                excluding: _showEndpointSettings,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 48,
                    ),
                    child: _WelcomeContent(
                      showBackButton: widget.showBackButton,
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.showBackButton)
              Positioned(
                right: AppSpacing.md,
                top: AppSpacing.md,
                child: _WelcomeIconButton(
                  key: const ValueKey('welcome_endpoint_settings_button'),
                  icon: AppIcons.cog,
                  tooltip: 'Network settings',
                  semanticLabel: 'Network settings',
                  onTap: () => setState(() => _showEndpointSettings = true),
                ),
              ),
            if (widget.showBackButton)
              const Positioned(
                left: AppSpacing.md,
                top: _welcomeBackButtonTop,
                child: _BackRow(),
              ),
            if (!widget.showBackButton && _showEndpointSettings)
              AppPaneModalOverlay(
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
                onDismiss: _dismissEndpointSettings,
                child: CustomEndpointSettingsPanel(
                  key: const ValueKey('welcome_endpoint_settings_modal'),
                  restartSyncAfterUpdate: false,
                  onClose: _dismissEndpointSettings,
                  onUpdated: _dismissEndpointSettings,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({required this.showBackButton});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 313,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const VizorWordmark(width: 106, height: 40, color: Color(0xffffffff)),
        const SizedBox(height: 48),
        Text(
          'Shielded\nby default',
          textAlign: TextAlign.center,
          style: AppTypography.displayLarge.copyWith(
            color: const Color(0xffffffff),
            fontSize: 56,
            height: 1.02,
            letterSpacing: -1.68,
          ),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WelcomeAccentButton(
                semanticKey: const ValueKey('welcome_create_wallet_button'),
                height: 44,
                glow: WelcomeButtonTokens.desktopAccentGlow,
                onPressed: () => context.go('/onboarding/intro'),
              ),
              const SizedBox(height: 16),
              AppButton(
                key: const ValueKey('welcome_import_wallet_button'),
                expand: true,
                height: 44,
                focusRingColor: WelcomeButtonTokens.focusRing,
                enabledBackgroundColor: WelcomeButtonTokens.secondaryBackground,
                pressedBackgroundColor:
                    WelcomeButtonTokens.secondaryHighlightedBackground,
                enabledBorderColor: WelcomeButtonTokens.border,
                enabledLabelColor: WelcomeButtonTokens.secondaryLabel,
                pressedLabelColor: WelcomeButtonTokens.secondaryLabel,
                leading: const AppIcon(AppIcons.importWallet, size: 20),
                onPressed: () => context.go(
                  showBackButton
                      ? '/import/method?from=add-account'
                      : '/import/method',
                ),
                child: const Text('Import wallet'),
              ),
              if (!showBackButton) ...[
                const SizedBox(height: 16),
                Semantics(
                  key: const ValueKey('welcome_redeem_card_button'),
                  button: true,
                  enabled: false,
                  child: AppButton(
                    expand: true,
                    height: 44,
                    variant: AppButtonVariant.ghost,
                    focusRingColor: WelcomeButtonTokens.focusRing,
                    enabledLabelColor: WelcomeButtonTokens.ghostLabel,
                    pressedLabelColor: WelcomeButtonTokens.ghostLabel,
                    pressedBackgroundColor:
                        WelcomeButtonTokens.ghostHighlightedBackground,
                    disabledBackgroundColor: const Color(0x00000000),
                    leading: const AppIcon(
                      AppIcons.giftCard,
                      size: 20,
                      color: WelcomeButtonTokens.ghostDisabledLabel,
                    ),
                    // TODO: Connect Gift Card activation once the claim flow is finalized.
                    onPressed: null,
                    child: const Text(
                      'Activate Gift Card',
                      style: TextStyle(
                        color: WelcomeButtonTokens.ghostDisabledLabel,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
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
                      ? colors.background.neutralScrim.withValues(alpha: 0.7)
                      : colors.background.neutralScrim,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AppIcon(
                      widget.icon,
                      size: AppIconSize.medium,
                      color: AppIconColors.light.inverse,
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
                color: const Color(0xfff7f7f7),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: const Color(0xfff7f7f7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
