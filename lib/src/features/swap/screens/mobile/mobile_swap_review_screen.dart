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
import '../../providers/swap_state_provider.dart';
import '../../widgets/mobile/mobile_swap_review_content.dart';
import '../../../../../l10n/app_localizations.dart';
import '../swap_review_screen.dart'
    show swapReviewFiatTextForAsset, swapReviewQuoteExceedsAvailableZec;

/// Mobile swap review — hosts the shared review content (a 400 pt
/// surface that fits the phone; smaller devices scale down) with the
/// same quote/start orchestration as the desktop review screen.
class MobileSwapReviewScreen extends ConsumerStatefulWidget {
  const MobileSwapReviewScreen({super.key});

  @override
  ConsumerState<MobileSwapReviewScreen> createState() =>
      _MobileSwapReviewScreenState();
}

class _MobileSwapReviewScreenState
    extends ConsumerState<MobileSwapReviewScreen> {
  var _hadReviewState = false;
  var _startingIntent = false;

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
    final colors = context.colors;
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
        swapReviewQuoteExceedsAvailableZec(quote, sync.spendableBalance)
        ? AppLocalizations.of(context).swapNotEnoughZecBody
        : null;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: AppLocalizations.of(context).swapReviewQuote,
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
                  amountWarning: swapState.reviewAmountDifferenceWarning(
                    AppLocalizations.of(context),
                  ),
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
                  starting: swapState.startSubmitting,
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
