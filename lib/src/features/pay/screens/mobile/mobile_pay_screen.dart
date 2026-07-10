import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../swap/models/swap_intent_presentation_mapper.dart'
    show swapIntentsFromRecords;
import '../../../swap/models/swap_models.dart';
import '../../../swap/providers/swap_activity_store.dart'
    show swapActivityRecordsProvider;
import '../../../swap/providers/swap_state_provider.dart';
import '../../../swap/widgets/mobile/mobile_swap_asset_selector_modal.dart';
import '../../../swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import '../../models/pay_recent_recipients.dart';
import '../../widgets/mobile/mobile_pay_add_contact_card.dart';
import '../../widgets/mobile/mobile_pay_amount_step.dart';
import '../../widgets/mobile/mobile_pay_recipient_step.dart';

enum _PayModalSurface { assetSelector, addressScanner, addContact, slippage }

enum _MobilePayStep { amount, recipient }

class MobilePayScreen extends ConsumerStatefulWidget {
  const MobilePayScreen({this.preservePreparedComposer = false, super.key});

  final bool preservePreparedComposer;

  @override
  ConsumerState<MobilePayScreen> createState() => _MobilePayScreenState();
}

class _MobilePayScreenState extends ConsumerState<MobilePayScreen> {
  final ValueNotifier<_PayModalSurface?> _payModal =
      ValueNotifier<_PayModalSurface?>(null);
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;
  late final TextEditingController _recipientController;
  bool _modalRouteOpen = false;
  bool _reviewRequestInFlight = false;
  int _reviewRequestGeneration = 0;
  var _step = _MobilePayStep.amount;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _amountFocusNode = FocusNode(debugLabel: 'MobilePayAmount');
    _recipientController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preparedState = ref.read(swapStateProvider);
      if (!widget.preservePreparedComposer || !preparedState.payMode) {
        ref.read(swapStateProvider.notifier).preparePayFromShieldedZec();
      }
      setState(() => _step = _MobilePayStep.amount);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    _recipientController.dispose();
    _payModal.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _openModal(_PayModalSurface surface) {
    setState(() => _payModal.value = surface);
    if (_modalRouteOpen) return;
    _modalRouteOpen = true;
    final appTheme = context.appTheme;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: context.colors.background.neutralScrim,
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            AppTheme(data: appTheme, child: _buildPayModal()),
      ).whenComplete(() {
        _modalRouteOpen = false;
        if (mounted) setState(() => _payModal.value = null);
      }),
    );
  }

  void _closePayModal() {
    if (_modalRouteOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    if (_payModal.value != null) {
      setState(() => _payModal.value = null);
    }
  }

  void _handleAssetSelected(SwapAsset asset) {
    ref
        .read(swapStateProvider.notifier)
        .selectPayExternalAsset(asset, clearDestinationOnChainChange: true);
    _closePayModal();
  }

  void _handleAddressScanned(String value) {
    ref.read(swapStateProvider.notifier).updateDestination(value);
    _closePayModal();
  }

  Future<void> _saveContact(
    AddressBookNetwork network,
    String label,
    String profilePictureId,
  ) async {
    final address = ref.read(swapStateProvider).destinationText.trim();
    await ref
        .read(addressBookProvider.notifier)
        .addContact(
          label: label,
          network: network,
          address: address,
          profilePictureId: profilePictureId,
        );
    if (!mounted) return;
    _closePayModal();
  }

  Widget _buildPayModal() {
    return ValueListenableBuilder<_PayModalSurface?>(
      valueListenable: _payModal,
      builder: (context, surface, _) {
        if (surface == null) return const SizedBox.shrink();
        return Consumer(
          builder: (context, ref, _) {
            final swapState = ref.watch(swapStateProvider);
            final swapNotifier = ref.read(swapStateProvider.notifier);
            final network = AddressBookNetwork.tryFromChainTicker(
              swapState.externalAsset.chainTicker,
            );
            final content = switch (surface) {
              _PayModalSurface.assetSelector => MobileSwapAssetSelectorModal(
                assets: swapState.supportedExternalAssets,
                selected: swapState.externalAsset,
                onSelected: _handleAssetSelected,
                onClose: _closePayModal,
              ),
              _PayModalSurface.addressScanner => MobileAddressScanCard(
                caption: 'Scan the recipient address QR code',
                permissionTitle: 'Scan the recipient address',
                steadyHint: 'Keep the QR code steady and fully visible.',
                resolve: (raw) async {
                  final address = normalizeAddressScanPayload(raw)?.trim();
                  if (address == null || address.isEmpty) {
                    return const MobileScanOutcome.rejected(
                      'QR code did not include an address.',
                    );
                  }
                  return MobileScanOutcome.accepted(address);
                },
                onScanned: _handleAddressScanned,
                onClose: _closePayModal,
              ),
              _PayModalSurface.addContact =>
                network == null
                    ? const SizedBox.shrink()
                    : MobilePayAddContactCard(
                        network: network,
                        address: swapState.destinationText.trim(),
                        onCancel: _closePayModal,
                        onSave: (label, profilePictureId) =>
                            _saveContact(network, label, profilePictureId),
                      ),
              _PayModalSurface.slippage => MobileSwapSlippageStepperModal(
                slippageBps: swapState.slippageBps,
                paymentMode: true,
                onSubmitted: (value) {
                  swapNotifier.updateSlippageBps(value);
                  _closePayModal();
                },
                onCancel: _closePayModal,
              ),
            };
            // Match the Swap modal route exactly: only the bottom card is
            // hit-testable, so taps in the empty area reach the dismissible
            // dialog barrier instead of being swallowed by a full-screen
            // scroll view.
            return SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  MobileModalCard(child: content),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openReview() async {
    if (_reviewRequestInFlight) return;
    _reviewRequestInFlight = true;
    final requestGeneration = ++_reviewRequestGeneration;
    final originStep = _step;
    final notifier = ref.read(swapStateProvider.notifier);
    await notifier.showReview();
    if (requestGeneration == _reviewRequestGeneration) {
      _reviewRequestInFlight = false;
    }
    if (!mounted ||
        requestGeneration != _reviewRequestGeneration ||
        _step != originStep) {
      return;
    }
    final next = ref.read(swapStateProvider);
    if (next.reviewVisible &&
        next.reviewQuote != null &&
        next.reviewAddressPlan != null) {
      await context.push('/pay/review');
    }
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final swapNotifier = ref.read(swapStateProvider.notifier);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    final sync = ref.watch(
      syncProvider.select(
        (value) =>
            (value.value ?? SyncState()).scopedToAccount(activeAccountUuid),
      ),
    );
    _syncController(
      _amountController,
      swapState.receiveAmountInputMode == SwapAmountInputMode.fiat
          ? swapState.receiveFiatText
          : swapState.receiveAmountText,
    );
    _syncController(_recipientController, swapState.destinationText);

    final network = AddressBookNetwork.tryFromChainTicker(
      swapState.externalAsset.chainTicker,
    );
    final allContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final contacts = network == null
        ? const <AddressBookContact>[]
        : payCompatibleContacts(allContacts, network);
    final records = activeAccountUuid == null
        ? const <SwapIntentRecord>[]
        : ref.watch(swapActivityRecordsProvider(activeAccountUuid)).value ??
              const <SwapIntentRecord>[];
    final recents = network == null
        ? const <PayRecentRecipient>[]
        : payRecentRecipients(
            intents: swapIntentsFromRecords(records),
            network: network,
          );

    void back() {
      if (_step == _MobilePayStep.recipient) {
        _reviewRequestGeneration++;
        _reviewRequestInFlight = false;
        swapNotifier.cancelReviewQuote();
        setState(() => _step = _MobilePayStep.amount);
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }

    final title = switch (_step) {
      _MobilePayStep.amount => 'Pay in ${swapState.externalAsset.symbol}',
      _MobilePayStep.recipient => 'Select Recipient',
    };

    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_step == _MobilePayStep.amount)
              const SizedBox(height: AppSpacing.s),
            MobileTopNav.back(title: title, onBack: back),
            Expanded(
              child: MobileBottomSafeArea(
                bottomPadding: AppSpacing.md,
                child: switch (_step) {
                  _MobilePayStep.amount => MobilePayAmountStep(
                    state: swapState,
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    zecAvailableZatoshi: sync.spendableBalance,
                    onAmountChanged: swapNotifier.updateReceiveAmount,
                    onFiatAmountChanged: swapNotifier.updateReceiveAmountFiat,
                    onToggleFiatInputMode: () => swapNotifier
                        .toggleFiatInputMode(SwapAmountInputSide.receive),
                    onOpenAssetSelector: () =>
                        _openModal(_PayModalSurface.assetSelector),
                    slippageLabel: formatSwapSlippage(swapState.slippageBps),
                    onOpenSlippage: () => _openModal(_PayModalSurface.slippage),
                    onContinue: () {
                      _amountFocusNode.unfocus();
                      setState(() => _step = _MobilePayStep.recipient);
                    },
                  ),
                  _MobilePayStep.recipient => MobilePayRecipientStep(
                    controller: _recipientController,
                    typedAddress: swapState.destinationText,
                    addressError: swapState.destinationAddressFormatError,
                    quoteError: swapState.quoteError,
                    contacts: contacts,
                    recents: recents,
                    busy: swapState.quoteLoading,
                    externalAsset: swapState.externalAsset,
                    onAddressChanged: swapNotifier.updateDestination,
                    onOpenScanner: () =>
                        _openModal(_PayModalSurface.addressScanner),
                    onChooseRecipient: swapNotifier.updateDestination,
                    onSelectRecipient: () => unawaited(_openReview()),
                    onAddToContacts: () =>
                        _openModal(_PayModalSurface.addContact),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
