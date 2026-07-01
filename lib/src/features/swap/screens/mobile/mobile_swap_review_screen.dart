import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../domain/swap_direction.dart';
import '../../models/swap_activity_navigation.dart';
import '../../models/swap_state.dart';
import '../../providers/swap_state_provider.dart';
import '../../widgets/mobile/mobile_swap_review_content.dart';
import '../swap_review_screen.dart'
    show swapReviewFiatTextForAsset, swapReviewQuoteExceedsAvailableZec;
import 'mobile_swap_keystone_sign_screen.dart';

const _keystoneSigningReviewInactiveDelay = Duration(milliseconds: 500);

/// Mobile swap review — hosts the shared review content (a 400 pt
/// surface that fits the phone; smaller devices scale down) with the
/// same quote/start orchestration as the desktop review screen.
class MobileSwapReviewScreen extends ConsumerStatefulWidget {
  const MobileSwapReviewScreen({this.payMode = false, super.key});

  final bool payMode;

  @override
  ConsumerState<MobileSwapReviewScreen> createState() =>
      _MobileSwapReviewScreenState();
}

class _MobileSwapReviewScreenState
    extends ConsumerState<MobileSwapReviewScreen> {
  var _hadReviewState = false;
  var _startingIntent = false;
  SwapState? _startingReviewSnapshot;
  var _keystoneSigningReviewInactive = false;

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
    context.go(widget.payMode ? '/pay' : '/swap');
  }

  void _reviewAgain() {
    unawaited(() async {
      await ref.read(swapStateProvider.notifier).showReview();
      if (!mounted) return;
      final next = ref.read(swapStateProvider);
      if (!next.reviewVisible ||
          next.reviewQuote == null ||
          next.reviewAddressPlan == null) {
        context.go(widget.payMode ? '/pay' : '/swap');
      }
    }());
  }

  void _startIntent() {
    unawaited(() async {
      final reviewSnapshot = ref.read(swapStateProvider);
      if (!_startingIntent) {
        setState(() {
          _startingIntent = true;
          _startingReviewSnapshot = reviewSnapshot;
          _keystoneSigningReviewInactive = false;
        });
      }
      final result = await ref.read(swapStateProvider.notifier).startIntent();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _startingIntent = false;
          _startingReviewSnapshot = null;
          _keystoneSigningReviewInactive = false;
        });
        return;
      }
      final returnTarget = widget.payMode
          ? SwapActivityReturnTarget.pay
          : SwapActivityReturnTarget.swap;
      switch (result) {
        case SwapStartedActivity(:final intentId):
          context.go(
            swapActivityDetailUri(
              intentId: intentId,
              returnTarget: returnTarget,
            ).toString(),
          );
        case SwapStartedKeystoneSigning(:final intentId):
          final pendingIntent = ref
              .read(swapStateProvider)
              .pendingKeystoneSigningIntent;
          if (pendingIntent != null && pendingIntent.id == intentId) {
            final signingRoute = context.push<void>(
              '/swap/keystone-sign',
              extra: MobileSwapKeystoneSignArgs.fromReview(
                intent: pendingIntent,
              ),
            );
            _scheduleKeystoneSigningReviewInactive();
            await signingRoute;
            if (!mounted) return;
            final path = GoRouter.of(
              context,
            ).routerDelegate.currentConfiguration.uri.path;
            if (path == (widget.payMode ? '/pay/review' : '/swap/review')) {
              ref
                  .read(swapStateProvider.notifier)
                  .clearPendingKeystoneSigningIntent(intentId);
              setState(() {
                _keystoneSigningReviewInactive = true;
              });
            }
            return;
          }
          context.go(
            swapActivityDetailUri(
              intentId: intentId,
              returnTarget: returnTarget,
              autoSignZecDeposit: true,
            ).toString(),
          );
      }
    }());
  }

  void _scheduleKeystoneSigningReviewInactive() {
    unawaited(() async {
      await Future<void>.delayed(_keystoneSigningReviewInactiveDelay);
      if (!mounted || !_startingIntent || _startingReviewSnapshot == null) {
        return;
      }
      setState(() => _keystoneSigningReviewInactive = true);
    }());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final liveSwapState = ref.watch(swapStateProvider);
    final reviewSnapshot = _startingIntent ? _startingReviewSnapshot : null;
    final liveHasReview =
        liveSwapState.reviewVisible &&
        liveSwapState.reviewQuote != null &&
        liveSwapState.reviewAddressPlan != null;
    final snapshotHasReview =
        reviewSnapshot != null &&
        reviewSnapshot.reviewVisible &&
        reviewSnapshot.reviewQuote != null &&
        reviewSnapshot.reviewAddressPlan != null;
    final inactiveReview =
        _keystoneSigningReviewInactive && snapshotHasReview && !liveHasReview;
    final swapState = liveHasReview
        ? liveSwapState
        : snapshotHasReview
        ? reviewSnapshot
        : liveSwapState;
    final quote = swapState.reviewQuote;
    final addressPlan = swapState.reviewAddressPlan;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ?? const [];
    if (!swapState.reviewVisible || quote == null || addressPlan == null) {
      if (!_hadReviewState || !_startingIntent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(widget.payMode ? '/pay' : '/swap');
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
        swapReviewQuoteExceedsAvailableZec(quote, sync.spendableBalance)
        ? widget.payMode
              ? "You don't have enough ZEC for this payment. Try a smaller amount."
              : "You don't have enough ZEC for this swap. Try a smaller amount."
        : null;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: widget.payMode ? 'Confirm payment' : 'Review quote',
              onBack: _returnToSwap,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.s,
                ),
                child: MobileSwapReviewContent(
                  quote: quote,
                  addressPlan: addressPlan,
                  addressBookContacts: addressBookContacts,
                  accountLabel: accountLabel,
                  accountProfilePictureId: accountProfilePictureId,
                  expired: swapState.quoteExpired,
                  amountWarning: swapState.reviewAmountDifferenceWarning,
                  startError: swapState.statusError,
                  startBlockedReason: startBlockedReason,
                  inactiveMessage: inactiveReview
                      ? 'This quote is no longer active.'
                      : null,
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
                  payMode: widget.payMode,
                ),
              ),
            ),
            MobileBottomSafeArea(
              bottomPadding: AppSpacing.md,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: MobileSwapReviewActions(
                  expired: swapState.quoteExpired,
                  starting:
                      !inactiveReview &&
                      (_startingIntent || liveSwapState.startSubmitting),
                  inactive: inactiveReview,
                  startBlockedReason: startBlockedReason,
                  sendsZec: quote.direction.sendsZec,
                  payMode: widget.payMode,
                  receiveAmountText: quote.receiveEstimateText,
                  onReviewAgain: _reviewAgain,
                  onCancelReview: _returnToSwap,
                  onStartIntent: _startIntent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
