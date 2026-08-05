// ignore_for_file: depend_on_referenced_packages
// Widgetbook is dev-only; every value in this file is deterministic fixture
// data and is intentionally isolated from payment-link services and storage.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import '../src/features/payment_links/widgets/payment_link_confetti.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';

const _previewWindowSize = Size(1080, 720);
const _message = 'Hey there! Welcome to the Shielded\nWorld ;)';

enum PaymentLinkPreviewState {
  empty,
  help,
  createEmpty,
  createFocused,
  createAmount,
  createFiatLoading,
  createFiat,
  messageEmpty,
  messageFilled,
  review,
  readyFlip,
  ready,
  cardsList,
  redeemPaste,
  redeemLoading,
  redeemInvalid,
  received,
}

Widget buildPaymentLinkEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.empty);

Widget buildPaymentLinkHelpUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.help);

Widget buildPaymentLinkCreateEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createEmpty);

Widget buildPaymentLinkCreateFocusedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFocused,
    );

Widget buildPaymentLinkCreateAmountUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createAmount,
    );

Widget buildPaymentLinkCreateFiatLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFiatLoading,
    );

Widget buildPaymentLinkCreateFiatUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createFiat);

Widget buildPaymentLinkMessageEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageEmpty,
    );

Widget buildPaymentLinkMessageFilledUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageFilled,
    );

Widget buildPaymentLinkReviewUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review);

Widget buildPaymentLinkReadyFlipUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.readyFlip);

Widget buildPaymentLinkReadyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.ready);

Widget buildPaymentLinkCardsListUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList);

Widget buildPaymentLinkRedeemPasteUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.redeemPaste);

Widget buildPaymentLinkRedeemLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemLoading,
    );

Widget buildPaymentLinkRedeemInvalidUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemInvalid,
    );

Widget buildPaymentLinkReceivedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.received);

/// A deterministic desktop-only surface for Widgetbook and Figma capture.
///
/// This deliberately contains no provider, persistence, network, or Rust
/// dependency. Unsupported values such as messages, fees, and Redeemed status
/// exist only in this fixture layer.
class PaymentLinkDesktopPreview extends StatelessWidget {
  const PaymentLinkDesktopPreview({required this.state, super.key});

  final PaymentLinkPreviewState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PaymentLinkPreviewSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: _PaymentLinkPreviewPane(state: state),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkPreviewPane extends StatelessWidget {
  const _PaymentLinkPreviewPane({required this.state});

  final PaymentLinkPreviewState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PaymentLinkPreviewState.empty => _home(),
      PaymentLinkPreviewState.help => PaymentLinkHowItWorksDesktopView(
        background: _home(),
        onClose: _noop,
        // This is the exact Figma-authored fixture copy. It is intentionally
        // confined here because the current bearer-secret link is not encrypted.
        createDescription:
            'Enter amount to gift, pick a design, add a message (optional) '
            'and create your Card with a single click.',
        shareDescription:
            'After the card created, you will get a uniquely generated Link. '
            'All data in the link is encrypted and safe to share, send this '
            'Link to the recipient.',
        redeemDescription:
            'Recipient can redeem the Card in their Vizor wallet using the '
            'Link. A small fee will be deducted from the recipient balance '
            'in order to make a Shielded transaction.',
      ),
      PaymentLinkPreviewState.createEmpty => _amount(
        visualState: PaymentLinkAmountVisualState.empty,
        artwork: PaymentLinkCardArtwork.gift,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.gift,
          emptyAmountLabel: 'Enter Amount',
        ),
      ),
      PaymentLinkPreviewState.createFocused => _amount(
        visualState: PaymentLinkAmountVisualState.focused,
        artwork: PaymentLinkCardArtwork.gift,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.gift,
          amountText: '1',
          maxAmountText: '142.23',
        ),
      ),
      PaymentLinkPreviewState.createAmount => _amount(
        visualState: PaymentLinkAmountVisualState.amount,
        artwork: PaymentLinkCardArtwork.chestLava,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.chestLava,
          amountText: '4.45',
          maxAmountText: '142.23',
        ),
      ),
      PaymentLinkPreviewState.createFiatLoading => _amount(
        visualState: PaymentLinkAmountVisualState.fiatLoading,
        artwork: PaymentLinkCardArtwork.ruby,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingLoading: true,
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.createFiat => _amount(
        visualState: PaymentLinkAmountVisualState.fiatLoaded,
        artwork: PaymentLinkCardArtwork.ruby,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,201.21',
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.messageEmpty => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.empty,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
        ),
        onBack: _noop,
        onSkip: _noop,
        title: 'Attach Encrypted Message',
        subtitle: 'Optional. A short message only the receiver will see.',
      ),
      PaymentLinkPreviewState.messageFilled => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.filled,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
          onDeleteMessage: _noop,
        ),
        onBack: _noop,
        onSkip: _noop,
        onContinue: _noop,
        title: 'Attach Encrypted Message',
        subtitle: 'Optional. A short message only the receiver will see.',
      ),
      PaymentLinkPreviewState.review => PaymentLinkReviewDesktopView(
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        onBack: _noop,
        onConfirm: _noop,
        subtitle: 'You will get a secure link you can share.',
        feeText: 'Creating fee: 0.12 ZEC',
        confirmLabel: 'Confirm & create',
      ),
      PaymentLinkPreviewState.readyFlip => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.flipHint,
        card: _readyCard(),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onCopy: _noop,
        onCardTap: _noop,
      ),
      PaymentLinkPreviewState.ready => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.ready,
        card: _readyCard(),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onCopy: _noop,
        onReturnHome: _noop,
      ),
      PaymentLinkPreviewState.cardsList => PaymentLinkCardsDesktopView(
        pendingCards: const [
          PaymentLinkCardListRow(
            thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.ruby),
            amountText: '0.25 ZEC',
            dateText: 'July 2',
            statusText: 'Copy link',
            onAction: _noop,
            showCopyIcon: true,
          ),
          PaymentLinkCardListRow(
            thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.dragon),
            amountText: '1.10 ZEC',
            dateText: 'May 20',
            statusText: 'Copy link',
            onAction: _noop,
            showCopyIcon: true,
          ),
        ],
        createdCards: const [
          PaymentLinkCardListRow(
            thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.chestLava),
            amountText: '2.5 ZEC',
            dateText: 'July 20',
            statusText: 'Redeemed',
          ),
          PaymentLinkCardListRow(
            thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.chestLava),
            amountText: '2.5 ZEC',
            dateText: 'July 20',
            statusText: 'Redeemed',
          ),
        ],
        onBack: _noop,
        onCreate: _noop,
        onRedeem: _noop,
        createdSectionLabel: 'July 2026',
      ),
      PaymentLinkPreviewState.redeemPaste => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.paste,
        onBack: _noop,
        onPaste: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
      ),
      PaymentLinkPreviewState.redeemLoading =>
        const PaymentLinkRedeemDesktopView(
          state: PaymentLinkRedeemVisualState.loading,
          onBack: _noop,
          subtitle: 'Copy the card link you’ve received, and paste it below.',
        ),
      PaymentLinkPreviewState.redeemInvalid => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.invalid,
        onBack: _noop,
        onPaste: _noop,
        onClearClipboard: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
        clearLabel: 'Clear clipboard',
      ),
      PaymentLinkPreviewState.received => PaymentLinkReceivedDesktopView(
        card: _readyCard(),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onClaim: _noop,
        onRevealMessage: _noop,
      ),
    };
  }

  PaymentLinksHomeDesktopView _home() {
    return PaymentLinksHomeDesktopView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        width: 261,
        height: 174,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: _noop,
      onShowHelp: _noop,
      onCreate: _noop,
      onRedeem: _noop,
    );
  }

  PaymentLinkAmountDesktopView _amount({
    required PaymentLinkAmountVisualState visualState,
    required PaymentLinkCardArtwork artwork,
    required Widget card,
  }) {
    return PaymentLinkAmountDesktopView(
      state: visualState,
      card: card,
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: artwork,
        onSelected: _ignoreArtwork,
      ),
      onBack: _noop,
      onCreate: _noop,
    );
  }

  static Widget _readyCard() {
    return const PaymentLinkGiftCard(
      artwork: PaymentLinkCardArtwork.ruby,
      amountText: '4.45',
      supportingText: r'$1,210.20',
      showCaret: false,
    );
  }
}

class _PaymentLinkThumbnail extends StatelessWidget {
  const _PaymentLinkThumbnail(this.artwork);

  final PaymentLinkCardArtwork artwork;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      artwork.assetPath,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
  }
}

class _PaymentLinkPreviewSidebar extends StatelessWidget {
  const _PaymentLinkPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PaymentLinkPreviewAccountHeader(),
            const SizedBox(height: AppSpacing.md),
            const AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              active: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Vote',
              iconName: AppIcons.scroll,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              onTap: _noop,
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: colors.sync.lightSuccess,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '34% Syncing...',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.sync.textSyncing,
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

class _PaymentLinkPreviewAccountHeader extends StatelessWidget {
  const _PaymentLinkPreviewAccountHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const AppProfilePicture(
            profilePictureId: kDefaultProfilePictureId,
            size: AppProfilePictureSize.large,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '142.23 ZEC',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.copy, size: 16, color: colors.icon.muted),
        ],
      ),
    );
  }
}

void _noop() {}

void _ignoreArtwork(PaymentLinkCardArtwork _) {}
