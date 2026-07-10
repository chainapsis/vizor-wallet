import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../models/swap_activity_navigation.dart';
import '../models/swap_fiat_amount.dart';
import '../models/swap_fiat_value_formatting.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';
import '../widgets/swap_review_page_content.dart';

class SwapReviewScreen extends ConsumerStatefulWidget {
  const SwapReviewScreen({super.key});

  @override
  ConsumerState<SwapReviewScreen> createState() => _SwapReviewScreenState();
}

class _SwapReviewScreenState extends ConsumerState<SwapReviewScreen> {
  final _toastOverlayContextKey = GlobalKey();
  var _hadReviewState = false;
  var _startingIntent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _copyAddress(String value) {
    final address = value.trim();
    if (address.isEmpty) return;
    final toastContext = _toastOverlayContextKey.currentContext;
    if (toastContext == null || !toastContext.mounted) return;
    copyTextWithToast(
      toastContext,
      text: address,
      toastMessage: 'Address copied',
    );
  }

  void _returnToSwap() {
    ref.read(swapStateProvider.notifier).cancelReviewQuote();
    context.go('/swap');
  }

  void _reviewAgain() {
    unawaited(() async {
      await ref.read(swapStateProvider.notifier).showReview();
      if (!mounted) return;
      final next = ref.read(swapStateProvider);
      if (!next.reviewVisible ||
          next.reviewQuote == null ||
          next.reviewAddressPlan == null) {
        context.go('/swap');
      }
    }());
  }

  void _startIntent() {
    unawaited(() async {
      if (!_startingIntent) {
        setState(() => _startingIntent = true);
      }
      final result = await ref.read(swapStateProvider.notifier).startIntent();
      if (!mounted) return;
      if (result == null) {
        setState(() => _startingIntent = false);
        return;
      }
      switch (result) {
        case SwapStartedActivity(:final intentId):
          context.go(
            swapActivityDetailUri(
              intentId: intentId,
              returnTarget: SwapActivityReturnTarget.swap,
            ).toString(),
          );
        case SwapStartedKeystoneSigning(:final intentId):
          context.go(
            swapActivityDetailUri(
              intentId: intentId,
              returnTarget: SwapActivityReturnTarget.swap,
              autoSignZecDeposit: true,
            ).toString(),
          );
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final quote = swapState.reviewQuote;
    final addressPlan = swapState.reviewAddressPlan;
    if (!swapState.reviewVisible || quote == null || addressPlan == null) {
      if (!_hadReviewState || !_startingIntent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/swap');
        });
      }
      return const SizedBox.shrink();
    }
    _hadReviewState = true;

    final accountState = ref.watch(accountProvider).value;
    // The balance gate is pinned to the account the quote was created for.
    // The swap provider clears reviewVisible on account switch, so the two
    // accounts are equal whenever this screen renders content — pinning the
    // review account keeps the gate correct even if that invariant changes.
    final sync = ref.watch(
      syncProvider.select(
        (value) => (value.value ?? SyncState()).scopedToAccount(
          swapState.reviewAccountUuid ?? accountState?.activeAccountUuid,
        ),
      ),
    );
    final startBlockedReason =
        swapReviewQuoteExceedsAvailableZec(quote, sync.displaySpendableBalance)
        ? "You don't have enough ZEC for this swap. Try a smaller amount."
        : null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppPaneScrollScaffold(
              toolbar: AppPaneToolbar(
                leading: AppBackLink(
                  label: 'Swap',
                  minWidth: 60,
                  onTap: _returnToSwap,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwapReviewPageContent(
                      quote: quote,
                      addressPlan: addressPlan,
                      addressBookContacts:
                          ref.watch(addressBookProvider).value?.contacts ??
                          const [],
                      expired: swapState.quoteExpired,
                      amountWarning: swapState.reviewAmountDifferenceWarning,
                      startError: swapState.statusError,
                      startBlockedReason: startBlockedReason,
                      payFiatTextOverride: swapReviewFiatTextForAsset(
                        swapState,
                        quote: quote,
                        asset: quote.sellAsset,
                        amount: quote.sellAmount,
                      ),
                      receiveFiatTextOverride: swapReviewFiatTextForAsset(
                        swapState,
                        quote: quote,
                        asset: quote.receiveAsset,
                        amount: quote.receiveAmount,
                      ),
                      onCopy: _copyAddress,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    SwapReviewPageActions(
                      expired: swapState.quoteExpired,
                      starting: swapState.startSubmitting,
                      startBlockedReason: startBlockedReason,
                      sendsZec: quote.direction.sendsZec,
                      onReviewAgain: _reviewAgain,
                      onCancelReview: _returnToSwap,
                      onStartIntent: _startIntent,
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AppToastHost(
                  key: const ValueKey('swap_review_toast_host'),
                  child: SizedBox.expand(key: _toastOverlayContextKey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared with the mobile review screen.
String? swapReviewFiatTextForAsset(
  SwapState state, {
  required SwapQuote quote,
  required SwapAsset asset,
  required double amount,
}) {
  final usdValue =
      _reviewQuoteUsdValueForAsset(quote, asset: asset, amount: amount) ??
      swapUsdValueForAsset(state, asset: asset, amount: amount);
  return usdValue == null ? null : swapFormatCompactFiatValue(usdValue);
}

double? _reviewQuoteUsdValueForAsset(
  SwapQuote quote, {
  required SwapAsset asset,
  required double amount,
}) {
  final basis = quote.fiatValueBasis;
  if (basis == null) return null;
  if (asset == quote.sellAsset || asset.hasSameMarketAs(quote.sellAsset)) {
    return basis.sellUsdValue(amount);
  }
  if (asset == quote.receiveAsset ||
      asset.hasSameMarketAs(quote.receiveAsset)) {
    return basis.receiveUsdValue(amount);
  }
  return null;
}

/// Shared with the mobile review screen.
bool swapReviewQuoteExceedsAvailableZec(
  SwapQuote quote,
  BigInt availableZatoshi,
) {
  if (!quote.direction.sendsZec) return false;
  final amountText = quote.sellAmountText.split(' ').first.trim();
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
