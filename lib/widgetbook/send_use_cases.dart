// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/send/widgets/send_compose_view.dart';

// A long memo that exceeds the 512-byte cap, used to preview the over-limit
// error state.
const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin.';

const _sampleUnifiedAddress = 'u112344123478129718 … 1238312779jkasdy';

/// Empty / default compose state — placeholders, collapsed memo card,
/// disabled Review. (Toggle the Widgetbook theme to see dark mode.)
Widget buildSendEmptyUseCase(BuildContext context) {
  return const _SendPageFrame(child: SendComposeView());
}

/// Shielded recipient, amount entered, memo expanded, Review enabled.
Widget buildSendShieldedFilledUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      reviewEnabled: true,
    ),
  );
}

/// Shielded recipient with a memo over the 512-byte limit: destructive tone,
/// "Message is too long", Review disabled.
Widget buildSendMemoTooLongUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      memoText: _longMemo,
      memoCounter: '-32/512',
      memoError: 'Message is too long',
    ),
  );
}

/// Transparent recipient: memo hidden, Review enabled.
Widget buildSendTransparentUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToTransparent,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.transparentUnavailable,
      reviewEnabled: true,
    ),
  );
}

/// A contact was picked: the "Send to" link reflects the contact name
/// ("Mike ›") instead of "Contacts ›".
Widget buildSendContactSelectedUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      contactName: 'Mike',
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      reviewEnabled: true,
    ),
  );
}

/// Desktop window chrome (sidebar + pane + back link) wrapping the compose
/// view, mirroring `_SwapPageFrame` so Widgetbook previews use the same
/// surface the real screen lives in.
class _SendPageFrame extends StatelessWidget {
  const _SendPageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1080.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;

        return SizedBox(
          width: width,
          height: height,
          child: AppDesktopShell(
            sidebar: const _PreviewSendSidebar(),
            pane: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PreviewSendPaneToolbar(),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Preview sidebar with Home active — mirrors the live desktop nav so the
/// Send page renders in a realistic shell.
class _PreviewSendSidebar extends StatelessWidget {
  const _PreviewSendSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Home',
                    iconName: AppIcons.home,
                    active: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSuccess,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSendPaneToolbar extends StatelessWidget {
  const _PreviewSendPaneToolbar();

  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Padding(
        // AppBackLink now carries a 12px internal pill inset, so the toolbar
        // padding drops from md (24) to s (12) to keep the chevron at the
        // design position (pane + 24) instead of shifting it to pane + 36.
        padding: const EdgeInsets.only(
          left: AppSpacing.s,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppBackLink(
            key: const ValueKey('send_preview_pane_back_button'),
            label: 'Home',
            minWidth: 60,
            onTap: () {},
          ),
        ),
      ),
    );
  }
}
