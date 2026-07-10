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
import '../../../pay/widgets/mobile/mobile_pay_review_content.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../domain/swap_direction.dart';
import '../../domain/swap_quote.dart';
import '../../models/swap_activity_navigation.dart';
import '../../models/swap_address_book_helpers.dart';
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
  Timer? _expiryTimer;
  DateTime? _expiryDeadline;
  Duration? _expiryRemaining;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
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
    if (widget.payMode && context.canPop()) {
      context.pop();
      return;
    }
    context.go(widget.payMode ? '/pay' : '/swap');
  }

  void _ensureExpiryTicker(SwapQuote? quote) {
    final deadline = quote?.actionDeadline;
    if (deadline == _expiryDeadline) return;
    _expiryDeadline = deadline;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiryRemaining = deadline?.difference(DateTime.now());
    if (deadline == null) return;
    if (_expiryRemaining! <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(swapStateProvider.notifier).expireReviewQuote();
        }
      });
      return;
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = deadline.difference(DateTime.now());
      setState(() => _expiryRemaining = remaining);
      if (remaining <= Duration.zero) {
        ref.read(swapStateProvider.notifier).expireReviewQuote();
        _expiryTimer?.cancel();
        _expiryTimer = null;
      }
    });
  }

  String? get _expiresInText {
    final remaining = _expiryRemaining;
    if (remaining == null || remaining.isNegative) return null;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
          if (widget.payMode) {
            context.go('/pay/submitted/${Uri.encodeComponent(intentId)}');
            return;
          }
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
                returnTarget: returnTarget,
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
    _ensureExpiryTicker(widget.payMode ? quote : null);
    final paymentQuoteExpired =
        swapState.quoteExpired ||
        (_expiryRemaining != null && _expiryRemaining! <= Duration.zero);
    final recipientAddress = addressPlan.userExternalAddress.trim();
    final recipientContact = widget.payMode
        ? addressBookContactForSwapAsset(
            contacts: addressBookContacts,
            asset: quote.receiveAsset,
            address: recipientAddress,
          )
        : null;
    final payingFiatText = widget.payMode
        ? swapReviewFiatTextForAsset(
            swapState,
            quote: quote,
            asset: quote.receiveAsset,
            amount: quote.receiveAmount,
          )
        : null;
    final convertedFiatText = widget.payMode
        ? swapReviewFiatTextForAsset(
            swapState,
            quote: quote,
            asset: quote.sellAsset,
            amount: quote.sellAmount,
          )
        : null;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: widget.payMode ? 'Review Payment' : 'Review quote',
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
                child: widget.payMode
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MobilePayReviewContent(
                            quote: quote,
                            recipientAddress: recipientAddress,
                            recipientContact: recipientContact,
                            payingFiatText: payingFiatText,
                            convertedFiatText: convertedFiatText,
                            expiresInText: _expiresInText,
                            expired: paymentQuoteExpired,
                          ),
                          for (final message in [
                            swapState.reviewAmountDifferenceWarning,
                            swapState.statusError,
                            startBlockedReason,
                            if (inactiveReview)
                              'This quote is no longer active.',
                          ])
                            if (message != null) ...[
                              const SizedBox(height: AppSpacing.s),
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySmall.copyWith(
                                  color: colors.text.destructive,
                                ),
                              ),
                            ],
                        ],
                      )
                    : MobileSwapReviewContent(
                        quote: quote,
                        addressPlan: addressPlan,
                        addressBookContacts: addressBookContacts,
                        accountLabel: accountLabel,
                        accountProfilePictureId: accountProfilePictureId,
                        expired: widget.payMode
                            ? paymentQuoteExpired
                            : swapState.quoteExpired,
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
                child: widget.payMode
                    ? MobilePayReviewActions(
                        expired: paymentQuoteExpired,
                        starting:
                            !inactiveReview &&
                            (_startingIntent || liveSwapState.startSubmitting),
                        inactive: inactiveReview,
                        startBlockedReason: startBlockedReason,
                        onConfirm: _startIntent,
                        onRefreshQuote: _reviewAgain,
                        onCancel: _returnToSwap,
                      )
                    : MobileSwapReviewActions(
                        expired: swapState.quoteExpired,
                        starting:
                            !inactiveReview &&
                            (_startingIntent || liveSwapState.startSubmitting),
                        inactive: inactiveReview,
                        startBlockedReason: startBlockedReason,
                        sendsZec: quote.direction.sendsZec,
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
