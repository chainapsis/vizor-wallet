import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/swap_feature_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/account_provider.dart';
import '../../swap/models/swap_fiat_value_formatting.dart';
import '../models/vizor_payment_link.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_service.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';
import '../widgets/mobile/payment_link_scan_sheet.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_card_motion.dart';
import '../widgets/payment_link_claim_outcome_view.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_copy.dart';
import '../widgets/payment_link_dashed_border_painter.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_long_sync_warning.dart';
import '../../onboarding/mobile/mobile_onboarding_progress.dart';
import '../../onboarding/mobile/mobile_onboarding_progress_scope.dart';

/// `/gift`: a Gift Card opened on a device without a wallet. The card is
/// checked without an account; the recipient then creates or brings a wallet
/// to claim it.
class GiftClaimScreen extends ConsumerStatefulWidget {
  const GiftClaimScreen({super.key});

  @override
  ConsumerState<GiftClaimScreen> createState() => _GiftClaimScreenState();
}

class _GiftClaimScreenState extends ConsumerState<GiftClaimScreen> {
  bool _showsBack = false;
  bool _reading = false;
  bool _invalidPaste = false;
  bool _handingOff = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(giftClaimFlowProvider, (_, next) {
      if (next?.phase != GiftClaimPhase.longSyncConfirmation) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(ref.read(giftClaimFlowProvider), next)) {
          return;
        }
        unawaited(_showLongSyncWarning(next!));
      });
    }, fireImmediately: true);
    ref.listenManual(paymentLinkIntakeProvider, (_, next) {
      if (next.pendingLink == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Consume only on the visible empty entry. Further links stay queued
        // while a Card or the wallet setup it owns is open.
        if (!mounted ||
            ModalRoute.of(context)?.isCurrent != true ||
            ref.read(giftClaimFlowProvider) != null ||
            ref.read(giftClaimSetupReturnProvider) != null) {
          return;
        }
        final pending = ref.read(paymentLinkIntakeProvider).pendingLink;
        if (pending != null) {
          ref.read(giftClaimFlowProvider.notifier).open(pending);
        }
      });
    }, fireImmediately: true);
  }

  Future<void> _close() async {
    try {
      await ref.read(giftClaimFlowProvider.notifier).close();
      if (mounted) context.go('/welcome');
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          'Couldn’t close the card. Try again.',
          iconName: AppIcons.warning,
        );
      }
    }
  }

  Future<void> _showLongSyncWarning(GiftClaimFlowState flow) async {
    final confirmed = await showPaymentLinkLongSyncWarningSheet(context);
    if (!mounted || !identical(ref.read(giftClaimFlowProvider), flow)) return;
    if (confirmed) {
      ref.read(giftClaimFlowProvider.notifier).recheck(allowLongSync: true);
    } else {
      _close();
    }
  }

  Future<void> _continueToSetup(String location) async {
    if (_handingOff) return;
    _handingOff = true;
    try {
      final saved = await ref
          .read(giftClaimFlowProvider.notifier)
          .handOffToSetup(
            accountUuidsBeforeSetup:
                ref
                    .read(accountProvider)
                    .value
                    ?.accounts
                    .map((account) => account.uuid) ??
                const <String>[],
          );
      if (!mounted) return;
      if (!saved) {
        showAppToast(
          context,
          'Too many gift cards are waiting. Finish another card first.',
          iconName: AppIcons.warning,
          tone: AppToastTone.destructive,
        );
        return;
      }
      if (mounted && saved) context.startOnboarding(location);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          'Couldn’t save the card. Try again.',
          iconName: AppIcons.warning,
        );
      }
    } finally {
      _handingOff = false;
    }
  }

  Future<void> _createGiftWallet() async {
    if (_handingOff) return;
    try {
      await ref.read(giftClaimFlowProvider.notifier).cancelSetupReturn();
      if (mounted) context.push('/gift/passcode');
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          'Couldn’t save the card. Try again.',
          iconName: AppIcons.warning,
        );
      }
    }
  }

  Future<void> _paste() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _invalidPaste = false;
    });
    try {
      final raw = await ref.read(paymentLinkClipboardProvider).readText();
      if (!mounted) return;
      final link = VizorPaymentLink.parse(raw?.trim() ?? '');
      ref.read(giftClaimFlowProvider.notifier).open(link);
    } catch (error) {
      log('GiftClaim: pasted link rejected: ${error.runtimeType}');
      if (mounted) setState(() => _invalidPaste = true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _scan() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _invalidPaste = false;
    });
    try {
      final link = await ref.read(paymentLinkScannerProvider)(
        context,
        networkName: ref.read(rpcEndpointProvider).networkName,
      );
      if (mounted && link != null) {
        ref.read(giftClaimFlowProvider.notifier).open(link);
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(giftClaimFlowProvider);
    if (flow == null) {
      return _guardBack(
        Scaffold(
          backgroundColor: context.colors.background.window,
          body: SafeArea(
            child: MobileGiftCardEntryView(
              state: _reading
                  ? PaymentLinkRedeemMobileState.loading
                  : _invalidPaste
                  ? PaymentLinkRedeemMobileState.invalid
                  : PaymentLinkRedeemMobileState.paste,
              onBack: _close,
              onPaste: _paste,
              onScan: _scan,
            ),
          ),
        ),
      );
    }
    final waitingForCheck =
        flow.phase == GiftClaimPhase.checking ||
        flow.phase == GiftClaimPhase.longSyncConfirmation;
    final inspection = flow.inspection;
    final canContinue =
        flow.phase == GiftClaimPhase.inspected &&
        inspection != null &&
        ((inspection.claimableZatoshi > BigInt.zero &&
                !inspection.waitingForFundingConfirmations) ||
            inspection.waitingForFundingConfirmations);
    return _guardBack(
      Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              if (waitingForCheck)
                const SizedBox(height: kMobileTopNavHeight)
              else
                MobileTopNav.back(
                  key: const ValueKey('gift_claim_close_button'),
                  title: '',
                  onBack: _close,
                  backIcon: AppIcons.cross,
                ),
              Expanded(
                child: canContinue
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxHeight < 420;
                            final gap = compact ? AppSpacing.sm : AppSpacing.md;
                            return Column(
                              children: [
                                if (compact)
                                  const SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ClipRect(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: _GiftArrivalHeading(),
                                      ),
                                    ),
                                  )
                                else
                                  const _GiftArrivalHeading(),
                                SizedBox(height: gap),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _card(flow.link, celebrate: true),
                                  ),
                                ),
                                SizedBox(height: gap),
                                _GiftClaimStatus(flow: flow),
                              ],
                            );
                          },
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 42),
                            const SizedBox(height: AppSpacing.md),
                            if (waitingForCheck)
                              const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: PaymentLinkLoadingMobileCard(),
                              )
                            else
                              _card(flow.link, celebrate: false),
                            const SizedBox(height: AppSpacing.md),
                            _GiftClaimStatus(flow: flow),
                          ],
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _GiftClaimActions(
                  flow: flow,
                  onCreate: _createGiftWallet,
                  onExisting: () => _continueToSetup('/onboarding/method'),
                  onClose: _close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guardBack(Widget child) {
    final phase = ref.watch(giftClaimFlowProvider)?.phase;
    final hasHandoff = ref.watch(giftClaimSetupReturnProvider) != null;
    return PopScope<void>(
      canPop:
          !hasHandoff &&
          phase != GiftClaimPhase.checking &&
          phase != GiftClaimPhase.longSyncConfirmation,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (hasHandoff && !_handingOff) unawaited(_close());
          return;
        }
        final flow = ref.read(giftClaimFlowProvider);
        final notifier = ref.read(giftClaimFlowProvider.notifier);
        scheduleMicrotask(() => notifier.closeAfterPop(flow));
      },
      child: child,
    );
  }

  Widget _card(VizorPaymentLink link, {required bool celebrate}) {
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final snapshot = link.presentation?.fiatSnapshot;
    final front = PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountText: formatZecAmount(link.amountZatoshi),
      supportingText: snapshot == null || !ref.watch(swapFeatureEnabledProvider)
          ? null
          : swapFormatCompactFiatValue(snapshot.amount),
      showCaret: false,
      onTap: message.isEmpty ? null : () => setState(() => _showsBack = true),
      semanticLabel: message.isEmpty
          ? null
          : kPaymentLinkRevealMessageSemanticLabel,
    );
    final card = message.isEmpty
        ? front
        : PaymentLinkCardFlip(
            showBack: _showsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              cardWidth: kPaymentLinkMobileCardWidth,
              cardHeight: kPaymentLinkMobileCardHeight,
              showBack: true,
              message: message,
              onTap: () => setState(() => _showsBack = false),
              semanticLabel:
                  'Sender message: $message; '
                  'Show gift card front',
            ),
          );
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: celebrate
              ? SizedBox(
                  width: kPaymentLinkMobileCardWidth,
                  height: kPaymentLinkMobileCardHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned.fill(
                        child: PaymentLinkConfetti(alignment: Alignment.center),
                      ),
                      PaymentLinkCardMotion(
                        celebrate: true,
                        width: kPaymentLinkMobileCardWidth,
                        height: kPaymentLinkMobileCardHeight,
                        child: card,
                      ),
                    ],
                  ),
                )
              : card,
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap on the card to reveal the message.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Walletless Gift Card entry from Figma `Redeed a Card` (8604:37897).
///
/// The regular payment-link redeem surface remains shared by an existing
/// wallet. This entry explains that redeeming the Card creates a new wallet,
/// and therefore keeps its own title, progress, and supporting copy.
class MobileGiftCardEntryView extends StatelessWidget {
  const MobileGiftCardEntryView({
    required this.state,
    required this.onBack,
    required this.onPaste,
    required this.onScan,
    super.key,
  });

  final PaymentLinkRedeemMobileState state;
  final VoidCallback onBack;
  final VoidCallback onPaste;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.s),
        SizedBox(
          height: 74,
          child: MobileTopNav.steps(
            progress: OnboardingProgressPosition.start.value,
            progressOffset: const Offset(-4.5, 0),
            progressTrackColor: const Color(0xffb1b3b3),
            onBack: onBack,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                Text(
                  'Create wallet by redeeming Vizor Gift Card',
                  key: const ValueKey('gift_walletless_entry_title'),
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    'Copy the card link you’ve\nreceived, and paste it below.',
                    key: const ValueKey('gift_walletless_entry_subtitle'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: context.colors.text.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 361),
                  child: AspectRatio(
                    aspectRatio: 320 / 200,
                    child: CustomPaint(
                      key: const ValueKey('gift_walletless_entry_card_slot'),
                      painter: PaymentLinkDashedBorderPainter(
                        color: context.colors.border.regular,
                        radius: 40,
                        strokeWidth: 3,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Center(child: _cardContent(context)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 233),
                  child: Text(
                    'Create a new Vizor wallet to receive the card’s balance.',
                    key: const ValueKey('gift_walletless_entry_explanation'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: context.colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardContent(BuildContext context) {
    return switch (state) {
      PaymentLinkRedeemMobileState.paste => _actions(),
      PaymentLinkRedeemMobileState.loading => const FittedBox(
        fit: BoxFit.scaleDown,
        child: PaymentLinkLoadingMobileCard(),
      ),
      PaymentLinkRedeemMobileState.invalid => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kPaymentLinkInvalidTitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                kPaymentLinkInvalidSubtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _actions(),
            ],
          ),
        ),
      ),
    };
  }

  Widget _actions() {
    return SizedBox(
      width: 170,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('payment_link_mobile_paste_button'),
            onPressed: onPaste,
            size: AppButtonSize.mediumLarge,
            expand: true,
            growWithContent: true,
            constrainContent: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: const AppIcon(AppIcons.paste, size: 20),
            child: const Text('Paste card link'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('payment_link_mobile_scan_button'),
            onPressed: onScan,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.mediumLarge,
            expand: true,
            growWithContent: true,
            constrainContent: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: const AppIcon(AppIcons.qr, size: 20),
            child: const Text('Scan QR code'),
          ),
        ],
      ),
    );
  }
}

class _GiftArrivalHeading extends StatelessWidget {
  const _GiftArrivalHeading();

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      'You’ve received a gift!',
      textAlign: TextAlign.center,
      style: AppTypography.headlineLarge.copyWith(
        color: context.colors.text.accent,
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - progress)),
          child: child,
        ),
      ),
      child: heading,
    );
  }
}

/// What the check found, always as text rather than color alone.
class _GiftClaimStatus extends StatelessWidget {
  const _GiftClaimStatus({required this.flow});

  final GiftClaimFlowState flow;

  @override
  Widget build(BuildContext context) {
    final (title, detail, tone) = _describe(flow);
    final colors = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        key: const ValueKey('gift_claim_status'),
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: tone == _Tone.problem
                  ? colors.text.destructive
                  : colors.text.primary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static (String, String?, _Tone) _describe(GiftClaimFlowState flow) {
    switch (flow.phase) {
      case GiftClaimPhase.checking:
      case GiftClaimPhase.longSyncConfirmation:
        return (
          'Checking the gift…',
          kPaymentLinkWaitingDescription,
          _Tone.neutral,
        );
      case GiftClaimPhase.failed:
        return switch (flow.failure) {
          GiftClaimFailure.otherNetwork => (
            'This gift card is for a different network.',
            null,
            _Tone.problem,
          ),
          GiftClaimFailure.invalid => (
            kPaymentLinkInvalidTitle,
            kPaymentLinkInvalidSubtitle,
            _Tone.problem,
          ),
          _ => (
            'We couldn’t reach the network.',
            'Check your connection and try again.',
            _Tone.problem,
          ),
        };
      case GiftClaimPhase.inspected:
        final inspection = flow.inspection!;
        if ((inspection.claimableZatoshi > BigInt.zero &&
            !inspection.waitingForFundingConfirmations)) {
          return (
            'Gift found',
            'Create a wallet or use one you have to claim it.',
            _Tone.neutral,
          );
        }
        if (inspection.waitingForFundingConfirmations) {
          return (
            'Waiting for the deposit to confirm · '
                '${inspection.fundingConfirmationCount} of '
                '$kPaymentLinkClaimConfirmationTarget',
            'You can create your wallet now.',
            _Tone.neutral,
          );
        }
        if (inspection.availability ==
            PaymentLinkAvailability.claimedElsewhere) {
          return (
            'This gift has already been claimed.',
            'Ask the sender for a new one.',
            _Tone.problem,
          );
        }
        return (
          PaymentLinkAvailability.noBalance.description,
          'The sender may not have funded it yet.',
          _Tone.problem,
        );
    }
  }
}

enum _Tone { neutral, problem }

class _GiftClaimActions extends ConsumerWidget {
  const _GiftClaimActions({
    required this.flow,
    required this.onCreate,
    required this.onExisting,
    required this.onClose,
  });

  final GiftClaimFlowState flow;
  final VoidCallback onCreate;
  final VoidCallback onExisting;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(giftClaimFlowProvider.notifier);
    final inspection = flow.inspection;
    final canClaimLater =
        inspection != null &&
        ((inspection.claimableZatoshi > BigInt.zero &&
                !inspection.waitingForFundingConfirmations) ||
            inspection.waitingForFundingConfirmations);
    final List<Widget> actions = switch (flow.phase) {
      GiftClaimPhase.checking || GiftClaimPhase.longSyncConfirmation => [
        _primary('Create a wallet to claim', null),
        _secondary('Claim with an existing wallet', null),
      ],
      GiftClaimPhase.failed =>
        flow.failure == GiftClaimFailure.network
            ? [_primary('Try again', notifier.recheck)]
            : [_secondary('Go back', onClose)],
      GiftClaimPhase.inspected when canClaimLater => [
        _primary('Create a wallet to claim', onCreate),
        _secondary('Claim with an existing wallet', onExisting),
      ],
      GiftClaimPhase.inspected => [
        // An empty scan is not proof the Card will never be funded.
        if (inspection!.availability == PaymentLinkAvailability.noBalance)
          _primary('Check again', notifier.recheck),
        _secondary('Go back', onClose),
      ],
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, action) in actions.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          action,
        ],
      ],
    );
  }

  // Labels wrap instead of clipping under large text.
  Widget _primary(String label, VoidCallback? onPressed) => Semantics(
    key: ValueKey('gift_claim_${label.toLowerCase().replaceAll(' ', '_')}'),
    button: true,
    enabled: onPressed != null,
    child: AppButton(
      onPressed: onPressed,
      size: AppButtonSize.large,
      expand: true,
      constrainContent: true,
      growWithContent: true,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );

  Widget _secondary(String label, VoidCallback? onPressed) => Semantics(
    key: ValueKey('gift_claim_${label.toLowerCase().replaceAll(' ', '_')}'),
    button: true,
    enabled: onPressed != null,
    child: AppButton(
      onPressed: onPressed,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.large,
      expand: true,
      constrainContent: true,
      growWithContent: true,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}
