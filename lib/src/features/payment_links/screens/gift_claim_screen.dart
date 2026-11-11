import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/swap_feature_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_toast.dart';
import '../../onboarding/shared/onboarding_auth_shell.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../providers/gift_card_entry_price_provider.dart';
import '../providers/gift_card_check_progress_provider.dart';
import '../../../providers/account_provider.dart';
import '../../swap/models/swap_fiat_value_formatting.dart';
import '../models/vizor_payment_link.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_service.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';
import '../providers/payment_link_scanner_provider.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/desktop_gift_entry_view.dart';
import '../widgets/payment_link_card_motion.dart';
import '../widgets/payment_link_claim_outcome_view.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_dashed_border_painter.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_long_sync_warning.dart';
import '../../onboarding/mobile/mobile_onboarding_progress.dart';
import '../../onboarding/mobile/mobile_onboarding_progress_scope.dart';
import '../../../core/l10n/l10n.dart';

/// `/gift`: a Gift Card opened from Welcome or Add account. The card is
/// checked without an account; the recipient then creates or brings a wallet
/// to claim it.
class GiftClaimScreen extends ConsumerStatefulWidget {
  const GiftClaimScreen({this.addingAccount = false, super.key});

  /// Whether the Gift flow was opened from an existing wallet's Add account
  /// screen. The flow creates an account in that wallet instead of creating a
  /// new wallet.
  final bool addingAccount;

  @override
  ConsumerState<GiftClaimScreen> createState() => _GiftClaimScreenState();
}

class _GiftClaimScreenState extends ConsumerState<GiftClaimScreen> {
  bool _showsBack = false;
  bool _reading = false;
  bool _invalidPaste = false;
  bool _handingOff = false;
  GiftClaimFlowState? _desktopLongSyncWarning;

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
        _openPendingLink();
      });
    }, fireImmediately: true);
  }

  void _openPendingLink() {
    // Open only on the visible empty entry. Further links stay queued while a
    // Card or the wallet setup it owns is open.
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
  }

  Future<void> _close() async {
    try {
      await ref.read(giftClaimFlowProvider.notifier).close();
      if (mounted) {
        context.go(
          ref.read(accountProvider).value?.hasAccounts == true
              ? '/add-account'
              : '/welcome',
        );
      }
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          context.l10n.commonCouldnTCloseTheCardTry,
          iconName: AppIcons.warning,
        );
      }
    }
  }

  Future<void> _showLongSyncWarning(GiftClaimFlowState flow) async {
    if (kAppFormFactor == AppFormFactor.desktop) {
      setState(() => _desktopLongSyncWarning = flow);
      return;
    }
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
          context.l10n.paymentLinkClaimQueueFull,
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
          context.l10n.paymentLinkClaimSaveFailed,
          iconName: AppIcons.warning,
        );
      }
    } finally {
      _handingOff = false;
    }
  }

  Future<void> _createGiftWallet() async {
    if (_handingOff) return;
    _handingOff = true;
    try {
      await ref.read(giftClaimFlowProvider.notifier).cancelSetupReturn();
      if (!mounted) return;
      final inspection = ref.read(giftClaimFlowProvider)?.inspection;
      if (inspection == null) return;
      ref.read(giftClaimFlowProvider.notifier).beginWalletSetup(inspection);
      context.push('/gift/customise');
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          context.l10n.paymentLinkClaimSaveFailed,
          iconName: AppIcons.warning,
        );
      }
    } finally {
      _handingOff = false;
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
      if (mounted) {
        setState(() => _reading = false);
        // Intake events are deferred while the scanner covers this route.
        // Recheck even when scanning was cancelled and returned no link.
        _openPendingLink();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(giftCardEntryPriceProvider);
    final flow = ref.watch(giftClaimFlowProvider);
    if (kAppFormFactor == AppFormFactor.desktop) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        body: _buildDesktop(flow),
      );
    }
    if (flow == null) {
      return _guardBack(
        Scaffold(
          backgroundColor: context.colors.background.window,
          body: SafeArea(
            child: MobileGiftCardEntryView(
              addingAccount: widget.addingAccount,
              state: _invalidPaste
                  ? PaymentLinkRedeemMobileState.invalid
                  : PaymentLinkRedeemMobileState.paste,
              onBack: _close,
              onPaste: _reading ? null : _paste,
              onScan: _reading ? null : _scan,
            ),
          ),
        ),
      );
    }
    final checkProgress = ref.watch(
      giftCardCheckProgressProvider,
    )[paymentLinkClaimWalletDirectoryName(flow.link)];
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
                child: SingleChildScrollView(
                  key: const ValueKey('gift_claim_stage_scroll'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GiftClaimStageHeading(
                        checking: waitingForCheck,
                        showArrival: canContinue,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _card(
                          flow.link,
                          celebrate: canContinue,
                          loading:
                              waitingForCheck &&
                              !(checkProgress?.hasFunding ?? false),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Keep the scroll extent stable when the progress
                      // details become the shorter inspection result.
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Visibility(
                            visible: false,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: PaymentLinkMobileCheckingDetails(
                              label: context.l10n.paymentLinkCheckingGiftFull,
                            ),
                          ),
                          if (waitingForCheck)
                            PaymentLinkMobileCheckingDetails(
                              label:
                                  checkProgress?.label(context.l10n) ??
                                  context.l10n.paymentLinkCheckingGiftEllipsis,
                            )
                          else
                            _GiftClaimStatus(
                              flow: flow,
                              addingAccount: widget.addingAccount,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Stack(
                  children: [
                    if (!waitingForCheck && !canContinue)
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: _GiftClaimActions(
                          flow: flow,
                          reserveClaimActions: true,
                          addingAccount: widget.addingAccount,
                          onCreate: _createGiftWallet,
                          onExisting: () =>
                              _continueToSetup('/onboarding/method'),
                          onClose: _close,
                        ),
                      ),
                    Visibility(
                      visible: !waitingForCheck,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _GiftClaimActions(
                        flow: flow,
                        reserveClaimActions: waitingForCheck,
                        addingAccount: widget.addingAccount,
                        onCreate: _createGiftWallet,
                        onExisting: () =>
                            _continueToSetup('/onboarding/method'),
                        onClose: _close,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(GiftClaimFlowState? flow) {
    if (flow == null) {
      return _guardBack(
        DesktopGiftEntryView(
          addingAccount: widget.addingAccount,
          invalid: _invalidPaste,
          onBack: _close,
          onPaste: _reading ? null : _paste,
          onScan: _reading ? null : _scan,
        ),
      );
    }
    final checking =
        flow.phase == GiftClaimPhase.checking ||
        flow.phase == GiftClaimPhase.longSyncConfirmation;
    final canContinue =
        flow.phase == GiftClaimPhase.inspected &&
        (flow.inspection!.claimableZatoshi > BigInt.zero ||
            flow.inspection!.waitingForFundingConfirmations);
    return _guardBack(
      Stack(
        fit: StackFit.expand,
        children: [
          OnboardingAuthShell(
            card: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canContinue) const _GiftArrivalHeading(),
                      const SizedBox(height: AppSpacing.md),
                      if (checking)
                        const PaymentLinkLoadingMobileCard()
                      else
                        _card(flow.link, celebrate: canContinue),
                      const SizedBox(height: AppSpacing.md),
                      _GiftClaimStatus(
                        flow: flow,
                        addingAccount: widget.addingAccount,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: 396,
                        child: _GiftClaimActions(
                          flow: flow,
                          addingAccount: widget.addingAccount,
                          onCreate: _createGiftWallet,
                          onExisting: () =>
                              _continueToSetup('/import/method?from=gift'),
                          onClose: _close,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!checking)
            PositionedDirectional(
              start: AppSpacing.md,
              top: AppSpacing.md,
              child: AppBackLink(
                key: const ValueKey('gift_claim_close_button'),
                label: context.l10n.commonGoBack,
                onTap: _close,
              ),
            ),
          if (_desktopLongSyncWarning != null)
            PaymentLinkLongSyncWarningModal(
              onConfirm: () {
                final warning = _desktopLongSyncWarning;
                setState(() => _desktopLongSyncWarning = null);
                if (identical(ref.read(giftClaimFlowProvider), warning)) {
                  ref
                      .read(giftClaimFlowProvider.notifier)
                      .recheck(allowLongSync: true);
                }
              },
              onCancel: () {
                setState(() => _desktopLongSyncWarning = null);
                unawaited(_close());
              },
            ),
        ],
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

  Widget _card(
    VizorPaymentLink link, {
    required bool celebrate,
    bool loading = false,
  }) {
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
      supportingText: !ref.watch(swapFeatureEnabledProvider)
          ? null
          : snapshot != null
          ? swapFormatCompactFiatValue(snapshot.amount)
          : fiatTextForZatoshi(
              link.amountZatoshi,
              zecUsdUnitPrice: ref.watch(giftCardEntryPriceProvider).value,
            ),
      showCaret: false,
      onTap: message.isEmpty ? null : () => setState(() => _showsBack = true),
      semanticLabel: message.isEmpty
          ? null
          : context.l10n.paymentLinkRevealMessageSemanticLabel,
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
              semanticLabel: context.l10n.paymentLinkSenderMessageSemantic(
                message,
              ),
            ),
          );
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('gift_claim_card_slot'),
          width: kPaymentLinkMobileCardWidth,
          height: kPaymentLinkMobileCardHeight,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              if (celebrate)
                const Positioned.fill(
                  child: PaymentLinkConfetti(alignment: Alignment.center),
                ),
              PaymentLinkCardMotion(
                key: const ValueKey('gift_claim_card_motion'),
                celebrate: celebrate,
                enableTilt: !loading,
                width: kPaymentLinkMobileCardWidth,
                height: kPaymentLinkMobileCardHeight,
                child: loading
                    ? const PaymentLinkLoadingMobileCard(
                        cardWidth: kPaymentLinkMobileCardWidth,
                        cardHeight: kPaymentLinkMobileCardHeight,
                      )
                    : card,
              ),
            ],
          ),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Visibility(
            visible: !loading,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Text(
              kAppFormFactor == AppFormFactor.mobile
                  ? context.l10n.paymentLinkTapToRevealMessage
                  : context.l10n.paymentLinkClickToRevealMessage,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Gift Card entry from Figma `Redeed a Card` (8604:37897).
///
/// The regular payment-link redeem surface remains shared by an existing
/// wallet. This entry explains that redeeming the Card creates either a new
/// wallet or an account in the current wallet, and therefore keeps its own
/// title, progress, and supporting copy.
class MobileGiftCardEntryView extends StatelessWidget {
  const MobileGiftCardEntryView({
    this.addingAccount = false,
    required this.state,
    required this.onBack,
    required this.onPaste,
    required this.onScan,
    super.key,
  });

  final bool addingAccount;
  final PaymentLinkRedeemMobileState state;
  final VoidCallback onBack;
  final VoidCallback? onPaste;
  final VoidCallback? onScan;

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
                  addingAccount
                      ? context.l10n.paymentLinkEntryTitleAccount
                      : context.l10n.paymentLinkEntryTitleWallet,
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
                    context.l10n.paymentLinkEntrySubtitle,
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
                    addingAccount
                        ? context.l10n.paymentLinkEntryExplanationAccount
                        : context.l10n.paymentLinkEntryExplanationWallet,
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
      PaymentLinkRedeemMobileState.paste => _actions(context),
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
                context.l10n.paymentLinkInvalidTitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                context.l10n.paymentLinkInvalidSubtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _actions(context),
            ],
          ),
        ),
      ),
    };
  }

  Widget _actions(BuildContext context) {
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
            child: Text(context.l10n.paymentLinkPasteLabel),
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
            child: Text(context.l10n.commonScanQrCodeSentenceCase),
          ),
        ],
      ),
    );
  }
}

/// Both headings occupy the checking heading's footprint, so discovering
/// funding and finishing inspection do not move the card below it.
class _GiftClaimStageHeading extends StatelessWidget {
  const _GiftClaimStageHeading({
    required this.checking,
    required this.showArrival,
  });

  final bool checking;
  final bool showArrival;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      ExcludeSemantics(
        child: Opacity(
          opacity: 0,
          child: RichText(
            textAlign: TextAlign.center,
            textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(
              text: context.l10n.paymentLinkClaimCheckingHeading,
              style: AppTypography.displayLarge,
            ),
          ),
        ),
      ),
      if (checking)
        Text(
          context.l10n.paymentLinkClaimCheckingHeading,
          textAlign: TextAlign.center,
          style: AppTypography.displayLarge.copyWith(
            color: context.colors.text.accent,
          ),
        )
      else if (showArrival)
        const _GiftArrivalHeading(),
    ],
  );
}

class _GiftArrivalHeading extends StatelessWidget {
  const _GiftArrivalHeading();

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      context.l10n.paymentLinkReceivedGiftHeading,
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
  const _GiftClaimStatus({required this.flow, required this.addingAccount});

  final GiftClaimFlowState flow;
  final bool addingAccount;

  @override
  Widget build(BuildContext context) {
    final (title, detail, tone) = _describe(
      context.l10n,
      flow,
      addingAccount: addingAccount,
    );
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

  static (String, String?, _Tone) _describe(
    AppLocalizations l10n,
    GiftClaimFlowState flow, {
    required bool addingAccount,
  }) {
    switch (flow.phase) {
      case GiftClaimPhase.checking:
      case GiftClaimPhase.longSyncConfirmation:
        return (
          l10n.paymentLinkCheckingGiftEllipsis,
          l10n.paymentLinkWaitingDescription,
          _Tone.neutral,
        );
      case GiftClaimPhase.failed:
        return switch (flow.failure) {
          GiftClaimFailure.interrupted => (
            l10n.paymentLinkInterruptedCheckMessage,
            null,
            _Tone.problem,
          ),
          GiftClaimFailure.otherNetwork => (
            l10n.paymentLinkClaimStatusOtherNetwork,
            null,
            _Tone.problem,
          ),
          GiftClaimFailure.invalid => (
            l10n.paymentLinkInvalidTitle,
            l10n.paymentLinkInvalidSubtitle,
            _Tone.problem,
          ),
          _ => (
            l10n.paymentLinkClaimStatusNetworkUnreachable,
            l10n.paymentLinkClaimStatusCheckConnection,
            _Tone.problem,
          ),
        };
      case GiftClaimPhase.inspected:
        final inspection = flow.inspection!;
        if ((inspection.claimableZatoshi > BigInt.zero &&
            !inspection.waitingForFundingConfirmations)) {
          return (
            l10n.paymentLinkClaimStatusGiftFound,
            addingAccount
                ? l10n.paymentLinkClaimStatusCreateAccountOrUseOne
                : l10n.paymentLinkClaimStatusCreateWalletOrUseOne,
            _Tone.neutral,
          );
        }
        if (inspection.waitingForFundingConfirmations) {
          return (
            l10n.paymentLinkClaimStatusWaitingDeposit(
              inspection.fundingConfirmationCount,
              kPaymentLinkClaimConfirmationTarget,
            ),
            addingAccount
                ? l10n.paymentLinkClaimStatusCreateAccountNow
                : l10n.paymentLinkClaimStatusCreateWalletNow,
            _Tone.neutral,
          );
        }
        if (inspection.availability ==
            PaymentLinkAvailability.claimedElsewhere) {
          return (
            l10n.paymentLinkClaimStatusAlreadyClaimed,
            l10n.paymentLinkClaimStatusAskSender,
            _Tone.problem,
          );
        }
        return (
          PaymentLinkAvailability.noBalance.description(l10n),
          l10n.paymentLinkClaimStatusMayNotBeFunded,
          _Tone.problem,
        );
    }
  }
}

enum _Tone { neutral, problem }

class _GiftClaimActions extends ConsumerWidget {
  const _GiftClaimActions({
    required this.flow,
    required this.addingAccount,
    required this.onCreate,
    required this.onExisting,
    required this.onClose,
    this.reserveClaimActions = false,
  });

  final bool reserveClaimActions;
  final GiftClaimFlowState flow;
  final bool addingAccount;
  final VoidCallback onCreate;
  final VoidCallback? onExisting;
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
    final List<Widget> actions = switch (reserveClaimActions
        ? GiftClaimPhase.checking
        : flow.phase) {
      GiftClaimPhase.checking || GiftClaimPhase.longSyncConfirmation =>
        reserveClaimActions
            ? [
                _primary(
                  addingAccount
                      ? 'gift_claim_create_an_account_to_claim'
                      : 'gift_claim_create_a_wallet_to_claim',
                  addingAccount
                      ? context.l10n.paymentLinkClaimActionCreateAccount
                      : context.l10n.paymentLinkClaimActionCreateWallet,
                  null,
                ),
                _secondary(
                  'gift_claim_claim_with_an_existing_wallet',
                  context.l10n.paymentLinkClaimActionExistingWallet,
                  null,
                ),
              ]
            : [],
      GiftClaimPhase.failed =>
        flow.failure == GiftClaimFailure.network ||
                flow.failure == GiftClaimFailure.interrupted
            ? [
                _primary(
                  'gift_claim_try_again',
                  context.l10n.commonTryAgain,
                  notifier.recheck,
                ),
              ]
            : [
                _secondary(
                  'gift_claim_go_back',
                  context.l10n.commonGoBack,
                  onClose,
                ),
              ],
      GiftClaimPhase.inspected when canClaimLater => [
        _primary(
          addingAccount
              ? 'gift_claim_create_an_account_to_claim'
              : 'gift_claim_create_a_wallet_to_claim',
          addingAccount
              ? context.l10n.paymentLinkClaimActionCreateAccount
              : context.l10n.paymentLinkClaimActionCreateWallet,
          onCreate,
        ),
        _secondary(
          'gift_claim_claim_with_an_existing_wallet',
          context.l10n.paymentLinkClaimActionExistingWallet,
          onExisting,
        ),
      ],
      GiftClaimPhase.inspected => [
        // An empty scan is not proof the Card will never be funded.
        if (inspection!.availability == PaymentLinkAvailability.noBalance)
          _primary(
            'gift_claim_check_again',
            context.l10n.commonCheckAgain,
            notifier.recheck,
          ),
        _secondary('gift_claim_go_back', context.l10n.commonGoBack, onClose),
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
  Widget _primary(String key, String label, VoidCallback? onPressed) =>
      Semantics(
        key: ValueKey(key),
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

  Widget _secondary(String key, String label, VoidCallback? onPressed) =>
      Semantics(
        key: ValueKey(key),
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
