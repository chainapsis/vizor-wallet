import '../../providers/payment_request_input_origin_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import 'dart:async';
import '../../../../core/widgets/app_toast.dart';
import '../../../address_scan/domain/address_input_policy.dart';
import '../../../address_scan/domain/address_input_provider.dart';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/navigation/payment_request_intake.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/payment_request_input.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../../../providers/account_provider.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../migration/providers/ironwood_migration_announcement_provider.dart';
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
  const MobilePayScreen({
    this.preservePreparedComposer = false,
    this.paymentRequestId,
    this.reviewAfterAmount = false,
    super.key,
  });

  final bool preservePreparedComposer;
  final String? paymentRequestId;
  final bool reviewAfterAmount;

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
  bool _reviewAfterAmount = false;
  var _step = _MobilePayStep.amount;
  String? _paymentRequestText;
  var _paymentRequestGeneration = 0;
  var _inputResolutionGeneration = 0;
  AddressInputResult? _scannedPaymentResult;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _amountFocusNode = FocusNode(debugLabel: 'MobilePayAmount');
    _recipientController = TextEditingController();
    _reviewAfterAmount =
        widget.preservePreparedComposer &&
        widget.paymentRequestId != null &&
        widget.reviewAfterAmount;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _paymentRequestGeneration++;
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
    if (isPaymentRequestUri(value)) {
      final resolved = _scannedPaymentResult;
      _scannedPaymentResult = null;
      unawaited(_reviewInputPaymentRequest(value, resolved: resolved));
      return;
    }
    _handleAddressChanged(value);
    _closePayModal();
  }

  void _handleAddressChanged(String value) {
    _paymentRequestGeneration++;
    if (isPaymentRequestInputDraft(value)) {
      setState(() => _paymentRequestText = value);
      return;
    }
    if (_paymentRequestText != null) setState(() => _paymentRequestText = null);
    ref.read(swapStateProvider.notifier).updateDestination(value);
  }

  Future<AddressInputResult?> _resolvePayInputResult(String raw) async {
    final resolutionGeneration = ++_inputResolutionGeneration;
    final generation = _paymentRequestGeneration;
    final reviewGeneration = _reviewRequestGeneration;
    final step = _step;
    final surface = _payModal.value;
    final input = _recipientController.value;
    final contextKey = (
      addressInputContextKey(ref, includeSwap: true),
      ref.read(paymentRequestArrivalProvider),
    );
    final result = await resolveWalletAddressInput(
      ref,
      raw,
      context: AddressInputContext.pay,
    );
    if (!mounted ||
        resolutionGeneration != _inputResolutionGeneration ||
        generation != _paymentRequestGeneration ||
        reviewGeneration != _reviewRequestGeneration ||
        step != _step ||
        surface != _payModal.value ||
        input != _recipientController.value ||
        contextKey !=
            (
              addressInputContextKey(ref, includeSwap: true),
              ref.read(paymentRequestArrivalProvider),
            )) {
      return null;
    }
    return result;
  }

  Future<MobileScanOutcome> _resolvePayInput(String raw) async {
    final result = await _resolvePayInputResult(raw);
    if (result == null) return const MobileScanOutcome.ignored();
    _scannedPaymentResult = result;
    return result.kind == AddressInputResultKind.rejected
        ? MobileScanOutcome.rejected(result.reason)
        : MobileScanOutcome.accepted(result.address ?? result.rawPaymentUri!);
  }

  Future<void> _pasteRecipient(String raw) async {
    final result = await _resolvePayInputResult(raw);
    if (!mounted || result == null) return;
    if (result.kind == AddressInputResultKind.rejected) {
      showAppToast(context, result.reason!, tone: AppToastTone.destructive);
      return;
    }
    if (result.kind == AddressInputResultKind.paymentRequest) {
      await _reviewInputPaymentRequest(result.rawPaymentUri!, resolved: result);
    } else {
      _handleAddressChanged(result.address!);
      _syncController(_recipientController, result.address!);
    }
  }

  Future<void> _reviewInputPaymentRequest(
    String raw, {
    AddressInputResult? resolved,
  }) async {
    final originChain = ref.read(swapStateProvider).externalAsset.chainTicker;
    resolved ??= await _resolvePayInputResult(raw);
    if (!mounted || resolved == null) return;
    if (resolved.kind == AddressInputResultKind.rejected) {
      showAppToast(context, resolved.reason!, tone: AppToastTone.destructive);
      return;
    }
    if (resolved.kind == AddressInputResultKind.address) {
      _handleAddressChanged(resolved.address!);
      _syncController(_recipientController, resolved.address!);
      _closePayModal();
      return;
    }
    final generation = ++_paymentRequestGeneration;
    final reviewGeneration = _reviewRequestGeneration;
    final step = _step;
    final input = _recipientController.text;
    final contextKey = addressInputContextKey(ref, includeSwap: true);
    bool isCurrent() =>
        mounted &&
        generation == _paymentRequestGeneration &&
        reviewGeneration == _reviewRequestGeneration &&
        step == _step &&
        input == _recipientController.text &&
        _payModal.value == null &&
        contextKey == addressInputContextKey(ref, includeSwap: true);
    // Only guard presentation: intake advances the arrival revision itself,
    // while the input origin must remain valid for Keep editing afterward.
    final arrival = ref.read(paymentRequestArrivalProvider);
    _closePayModal();
    await WidgetsBinding.instance.endOfFrame;
    if (!isCurrent() || arrival != ref.read(paymentRequestArrivalProvider)) {
      return;
    }
    await reviewPaymentRequestFromInput(
      ref,
      resolved.rawPaymentUri!,
      isCurrent: isCurrent,
      resolvedCrossChainRequest: resolved.crossChainRequest,
      inputOrigin: PaymentRequestInputOrigin(
        chain: originChain,
        isCurrent: isCurrent,
        useAddress: (address) {
          _handleAddressChanged(address);
          _syncController(_recipientController, address);
        },
      ),
    );
  }

  void _chooseRecipient(PayRecipientSelection selection) {
    _paymentRequestGeneration++;
    setState(() => _paymentRequestText = null);
    final notifier = ref.read(swapStateProvider.notifier);
    final contactId = selection.contactId;
    if (contactId == null) {
      notifier.updateDestination(selection.address);
    } else {
      notifier.selectDestinationContact(
        address: selection.address,
        contactId: contactId,
      );
    }
  }

  Future<void> _reviewRecipient(PayRecipientSelection selection) async {
    _chooseRecipient(selection);
    await _openReview(selection);
  }

  Future<void> _saveContact(
    AddressBookNetwork network,
    String label,
    String profilePictureId,
  ) async {
    final address = ref.read(swapStateProvider).destinationText.trim();
    final contextKey = addressInputContextKey(ref, includeSwap: true);
    final generation = _paymentRequestGeneration;
    final surface = _payModal.value;
    bool isCurrent() =>
        mounted &&
        generation == _paymentRequestGeneration &&
        surface == _payModal.value &&
        contextKey == addressInputContextKey(ref, includeSwap: true) &&
        address == ref.read(swapStateProvider).destinationText.trim();
    final result = await resolveWalletAddressInput(
      ref,
      address,
      context: AddressInputContext.contact,
      network: network,
    );
    if (!mounted || !isCurrent()) return;
    if (result.kind != AddressInputResultKind.address) {
      showAppToast(
        context,
        result.reason ?? 'Invalid address',
        tone: AppToastTone.destructive,
      );
      return;
    }
    await ref
        .read(addressBookProvider.notifier)
        .addContact(
          label: label,
          network: network,
          address: result.address!,
          profilePictureId: profilePictureId,
        );
    if (!mounted || !isCurrent()) return;
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
                caption: 'Scan an address or payment request QR code',
                permissionTitle: 'Scan the recipient address',
                steadyHint: 'Keep the QR code steady and fully visible.',
                validationContext: (
                  addressInputContextKey(ref, includeSwap: true),
                  _paymentRequestGeneration,
                  _reviewRequestGeneration,
                  _step,
                ),
                resolve: _resolvePayInput,
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

  Future<void> _openReview(PayRecipientSelection selection) async {
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
      _reviewAfterAmount = false;
      await context.push('/pay/review', extra: selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (_, _) {
        setState(() => _paymentRequestGeneration++);
      },
    );
    ref.listen(rpcEndpointProvider.select((value) => value.networkName), (
      _,
      _,
    ) {
      setState(() => _paymentRequestGeneration++);
    });
    ref.listen(
      swapStateProvider.select(
        (value) => (value.externalAsset, value.direction, value.payMode),
      ),
      (_, _) {
        setState(() => _paymentRequestGeneration++);
      },
    );
    final swapState = ref.watch(swapStateProvider);
    final swapNotifier = ref.read(swapStateProvider.notifier);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    _syncController(
      _amountController,
      swapState.receiveAmountInputMode == SwapAmountInputMode.fiat
          ? swapState.receiveFiatText
          : swapState.receiveAmountText,
    );
    _syncController(
      _recipientController,
      _paymentRequestText ?? swapState.destinationText,
    );

    final network = AddressBookNetwork.tryFromChainTicker(
      swapState.externalAsset.chainTicker,
    );
    final addressBook = ref.watch(addressBookProvider);
    final addressBookInitialLoading =
        addressBook.isLoading && !addressBook.hasValue;
    final allContacts =
        addressBook.value?.contacts ?? const <AddressBookContact>[];
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
            contacts: contacts,
          );
    final effectiveSelection = resolvePayRecipientSelection(
      contacts,
      swapState.destinationText,
      explicitSelection: swapState.userExternalContactId == null
          ? null
          : PayRecipientSelection(
              address: swapState.destinationText,
              contactId: swapState.userExternalContactId,
            ),
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
    final migrationSpendable = ref.watch(
      ironwoodMigrationAwareDisplaySpendableProvider(activeAccountUuid),
    );

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
                    zecAvailableZatoshi: migrationSpendable,
                    onAmountChanged: (value) {
                      _paymentRequestGeneration++;
                      swapNotifier.updateReceiveAmount(value);
                    },
                    onFiatAmountChanged: (value) {
                      _paymentRequestGeneration++;
                      swapNotifier.updateReceiveAmountFiat(value);
                    },
                    onToggleFiatInputMode: () => swapNotifier
                        .toggleFiatInputMode(SwapAmountInputSide.receive),
                    onOpenAssetSelector: () =>
                        _openModal(_PayModalSurface.assetSelector),
                    slippageLabel: formatSwapSlippage(swapState.slippageBps),
                    onOpenSlippage: () => _openModal(_PayModalSurface.slippage),
                    onContinue: () {
                      _amountFocusNode.unfocus();
                      if (_reviewAfterAmount && swapState.canReviewQuote) {
                        unawaited(_openReview(effectiveSelection));
                      } else {
                        setState(() => _step = _MobilePayStep.recipient);
                      }
                    },
                  ),
                  _MobilePayStep.recipient => MobilePayRecipientStep(
                    controller: _recipientController,
                    typedAddress:
                        _paymentRequestText ?? swapState.destinationText,
                    addressError: swapState
                        .copyWith(destinationText: _paymentRequestText)
                        .destinationAddressFormatError,
                    quoteError:
                        swapState.externalAssetSupportError ??
                        swapState.quoteError,
                    contacts: contacts,
                    recents: recents,
                    busy: swapState.quoteLoading,
                    enabled:
                        swapState.externalAssetIsAvailable &&
                        !addressBookInitialLoading,
                    selectedContactId: swapState.userExternalContactId,
                    externalAsset: swapState.externalAsset,
                    onAddressChanged: _handleAddressChanged,
                    onPaste: _pasteRecipient,
                    readPasteContext: () => (
                      addressInputContextKey(ref, includeSwap: true),
                      _paymentRequestGeneration,
                      _reviewRequestGeneration,
                    ),
                    pasteContext: (
                      addressInputContextKey(ref, includeSwap: true),
                      _paymentRequestGeneration,
                      _reviewRequestGeneration,
                    ),
                    onReviewPaymentRequest: () => unawaited(
                      _reviewInputPaymentRequest(_recipientController.text),
                    ),
                    onOpenScanner: () =>
                        _openModal(_PayModalSurface.addressScanner),
                    onChooseRecipient: _chooseRecipient,
                    onSelectRecipient: () =>
                        unawaited(_reviewRecipient(effectiveSelection)),
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
