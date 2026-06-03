import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../models/swap_activity_navigation.dart';
import '../models/swap_fiat_amount.dart';
import '../models/swap_fiat_value_formatting.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';
import '../widgets/swap_near_intents_attribution.dart';
import '../widgets/swap_review_page_content.dart';

class SwapReviewScreen extends ConsumerStatefulWidget {
  const SwapReviewScreen({super.key});

  @override
  ConsumerState<SwapReviewScreen> createState() => _SwapReviewScreenState();
}

class _SwapReviewScreenState extends ConsumerState<SwapReviewScreen> {
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

  String? _accountLabelFor(AccountState? accountState, String? accountUuid) {
    if (accountUuid == null || accountUuid.trim().isEmpty) return null;
    for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
      if (account.uuid == accountUuid) return account.name;
    }
    return null;
  }

  String _accountProfilePictureIdFor(
    AccountState? accountState,
    String? accountUuid,
  ) {
    if (accountUuid == null || accountUuid.trim().isEmpty) {
      return kDefaultProfilePictureId;
    }
    for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
      if (account.uuid == accountUuid) return account.profilePictureId;
    }
    return kDefaultProfilePictureId;
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
      final started = await ref.read(swapStateProvider.notifier).startIntent();
      if (!mounted) return;
      if (!started) {
        setState(() => _startingIntent = false);
        return;
      }
      final startedIntent = ref.read(swapStateProvider).selectedIntentOrNull;
      if (startedIntent != null) {
        context.go(
          swapActivityDetailUri(
            intentId: startedIntent.id,
            returnTarget: SwapActivityReturnTarget.swap,
          ).toString(),
        );
        return;
      }
      context.go('/activity');
    }());
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final quote = swapState.reviewQuote;
    final addressPlan = swapState.reviewAddressPlan;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ?? const [];
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
    final sync = ref.watch(
      syncProvider.select(
        (value) => (value.value ?? SyncState()).scopedToAccount(
          accountState?.activeAccountUuid,
        ),
      ),
    );
    final accountLabel = _accountLabelFor(
      accountState,
      swapState.reviewAccountUuid,
    );
    final accountProfilePictureId = _accountProfilePictureIdFor(
      accountState,
      swapState.reviewAccountUuid,
    );
    final startBlockedReason =
        _reviewQuoteExceedsAvailableZec(quote, sync.spendableBalance)
            ? "You don't have enough ZEC for this swap. Try a smaller amount."
            : null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: 'Swap',
                minWidth: 60,
                onTap: _returnToSwap,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: SwapReviewPageScrollArea(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SwapReviewPageContent(
                                    quote: quote,
                                    addressPlan: addressPlan,
                                    addressBookContacts: addressBookContacts,
                                    accountLabel: accountLabel,
                                    accountProfilePictureId:
                                        accountProfilePictureId,
                                    expired: swapState.quoteExpired,
                                    amountWarning:
                                        swapState.reviewAmountDifferenceWarning,
                                    startError: swapState.statusError,
                                    startBlockedReason: startBlockedReason,
                                    payFiatTextOverride:
                                        _reviewFiatTextForAsset(
                                          swapState,
                                          quote: quote,
                                          asset: quote.sellAsset,
                                          amount: quote.sellAmount,
                                        ),
                                    receiveFiatTextOverride:
                                        _reviewFiatTextForAsset(
                                          swapState,
                                          quote: quote,
                                          asset: quote.receiveAsset,
                                          amount: quote.receiveAmount,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
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
                        ),
                      ),
                      if (constraints.maxHeight >= 520)
                        const Positioned(
                          left: 0,
                          bottom: AppSpacing.md,
                          child: SwapNearIntentsAttribution(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _reviewFiatTextForAsset(
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

bool _reviewQuoteExceedsAvailableZec(SwapQuote quote, BigInt availableZatoshi) {
  if (!quote.direction.sendsZec) return false;
  final amountText = quote.sellAmountText.split(' ').first.trim();
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
