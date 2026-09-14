import '../providers/payment_request_input_origin_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import 'dart:async';
import '../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../../core/widgets/app_toast.dart';
import '../../address_scan/domain/address_input_policy.dart';
import '../../address_scan/domain/address_input_provider.dart';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/navigation/payment_request_intake.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../address_scan/widgets/payment_request_input.dart';
import '../../send/widgets/verify_address_modal.dart';
import '../../../providers/account_provider.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/models/swap_intent_presentation_mapper.dart'
    show swapIntentsFromRecords;
import '../../swap/models/swap_models.dart';
import '../../swap/providers/swap_activity_store.dart'
    show swapActivityRecordsProvider;
import '../../swap/providers/swap_state_provider.dart';
import '../../swap/screens/swap_review_screen.dart'
    show swapReviewFiatTextForAsset, swapReviewQuoteExceedsAvailableZec;
import '../../swap/widgets/swap_asset_selector_modal.dart';
import '../../swap/widgets/swap_slippage_modal.dart';
import '../models/pay_recent_recipients.dart';
import '../widgets/pay_add_contact_modal.dart';
import '../widgets/pay_amount_step.dart';
import '../widgets/pay_recipient_step.dart';
import '../widgets/pay_review_step.dart';
import '../widgets/pay_wizard_page.dart';

enum _PayModalSurface {
  assetSelector,
  addressScanner,
  contactPicker,
  addContact,
  slippage,
  verifyAddress,
}

enum _PayWizardStep { amount, recipient, review }

class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({
    this.preservePreparedComposer = false,
    this.paymentRequestId,
    this.showPreparedReview = false,
    this.reviewAfterAmount = false,
    super.key,
  });

  final bool preservePreparedComposer;
  final String? paymentRequestId;
  final bool showPreparedReview;
  final bool reviewAfterAmount;

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  late final ScrollController _scrollController;
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;
  late final TextEditingController _recipientController;
  _PayModalSurface? _payModal;
  String? _paymentRequestText;
  var _paymentRequestGeneration = 0;
  var _inputResolutionGeneration = 0;
  AddressInputResult? _scannedPaymentResult;
  var _wizardStep = _PayWizardStep.amount;
  var _startingIntent = false;
  var _reviewRequestGeneration = 0;
  var _reviewAfterAmount = false;
  Timer? _expiryTimer;
  DateTime? _expiryDeadline;
  Duration? _expiryRemaining;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _amountController = TextEditingController();
    _amountFocusNode = FocusNode(debugLabel: 'PayWizardAmount');
    _recipientController = TextEditingController();
    _reviewAfterAmount =
        widget.preservePreparedComposer &&
        widget.paymentRequestId != null &&
        widget.reviewAfterAmount;
    final initial = ref.read(swapStateProvider);
    if (widget.preservePreparedComposer &&
        widget.showPreparedReview &&
        initial.payMode &&
        initial.reviewVisible &&
        initial.reviewQuote != null &&
        initial.reviewAddressPlan != null) {
      _wizardStep = _PayWizardStep.review;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preparedState = ref.read(swapStateProvider);
      if (!widget.preservePreparedComposer || !preparedState.payMode) {
        ref.read(swapStateProvider.notifier).preparePayFromShieldedZec();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _paymentRequestGeneration++;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _scrollController.dispose();
    _amountController.dispose();
    _amountFocusNode.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  void _closePayModal() {
    if (_payModal == null) return;
    setState(() => _payModal = null);
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _goToStep(_PayWizardStep step) {
    if (_wizardStep == step) return;
    _reviewRequestGeneration++;
    if (_wizardStep == _PayWizardStep.review ||
        ref.read(swapStateProvider).quoteLoading) {
      ref.read(swapStateProvider.notifier).cancelReviewQuote();
    }
    setState(() => _wizardStep = step);
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
      _cancelReviewForPaymentRequest();
      setState(() => _paymentRequestText = value);
      return;
    }
    if (_paymentRequestText != null) setState(() => _paymentRequestText = null);
    ref.read(swapStateProvider.notifier).updateDestination(value);
  }

  void _cancelReviewForPaymentRequest() {
    _reviewRequestGeneration++;
    ref.read(swapStateProvider.notifier).cancelReviewQuote();
  }

  Future<AddressInputResult?> _resolvePayInputResult(String raw) async {
    final resolutionGeneration = ++_inputResolutionGeneration;
    final generation = _paymentRequestGeneration;
    final reviewGeneration = _reviewRequestGeneration;
    final step = _wizardStep;
    final surface = _payModal;
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
        step != _wizardStep ||
        surface != _payModal ||
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
    final step = _wizardStep;
    final input = _recipientController.text;
    final contextKey = addressInputContextKey(ref, includeSwap: true);
    bool isCurrent() =>
        mounted &&
        generation == _paymentRequestGeneration &&
        reviewGeneration == _reviewRequestGeneration &&
        step == _wizardStep &&
        input == _recipientController.text &&
        _payModal == null &&
        contextKey == addressInputContextKey(ref, includeSwap: true);
    _closePayModal();
    await WidgetsBinding.instance.endOfFrame;
    if (!isCurrent()) return;
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
    await _openReview();
  }

  Future<void> _openReview() async {
    if (ref.read(swapStateProvider).quoteLoading) return;
    final requestGeneration = ++_reviewRequestGeneration;
    final originStep = _wizardStep;
    final notifier = ref.read(swapStateProvider.notifier);
    await notifier.showReview();
    if (!mounted ||
        requestGeneration != _reviewRequestGeneration ||
        _wizardStep != originStep) {
      return;
    }
    final next = ref.read(swapStateProvider);
    if (next.reviewVisible &&
        next.reviewQuote != null &&
        next.reviewAddressPlan != null) {
      setState(() {
        _reviewAfterAmount = false;
        _wizardStep = _PayWizardStep.review;
      });
    }
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
              returnTarget: SwapActivityReturnTarget.pay,
            ).toString(),
          );
        case SwapStartedKeystoneSigning(:final intentId):
          context.go(
            swapActivityDetailUri(
              intentId: intentId,
              returnTarget: SwapActivityReturnTarget.pay,
              autoSignZecDeposit: true,
            ).toString(),
          );
      }
    }());
  }

  Future<void> _saveContact(
    AddressBookNetwork network,
    String label,
    String profilePictureId,
  ) async {
    final address = ref.read(swapStateProvider).destinationText.trim();
    final contextKey = addressInputContextKey(ref, includeSwap: true);
    final generation = _paymentRequestGeneration;
    final surface = _payModal;
    bool isCurrent() =>
        mounted &&
        generation == _paymentRequestGeneration &&
        surface == _payModal &&
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

  /// Keeps the review countdown aligned with the active quote; a new quote
  /// (re-review) re-arms the ticker.
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
        if (!mounted || _wizardStep != _PayWizardStep.review) return;
        ref.read(swapStateProvider.notifier).expireReviewQuote();
      });
      return;
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = deadline.difference(DateTime.now());
      setState(() => _expiryRemaining = remaining);
      if (remaining <= Duration.zero) {
        _expiryTimer?.cancel();
        _expiryTimer = null;
        ref.read(swapStateProvider.notifier).expireReviewQuote();
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

    final quote = swapState.reviewQuote;
    if (_wizardStep == _PayWizardStep.review) {
      _ensureExpiryTicker(quote);
      if ((quote == null || !swapState.reviewVisible) &&
          !swapState.quoteLoading &&
          !_startingIntent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _wizardStep != _PayWizardStep.review) return;
          if (ref.read(swapStateProvider).reviewQuote == null) {
            setState(() => _wizardStep = _PayWizardStep.recipient);
          }
        });
      }
    } else {
      _ensureExpiryTicker(null);
    }

    final recipientAddress = swapState.destinationText.trim();
    final effectiveSelection = resolvePayRecipientSelection(
      contacts,
      recipientAddress,
      explicitSelection: swapState.userExternalContactId == null
          ? null
          : PayRecipientSelection(
              address: recipientAddress,
              contactId: swapState.userExternalContactId,
            ),
    );
    final recipientContact = payContactForSelection(
      contacts,
      effectiveSelection,
    );
    final migrationSpendable = ref.watch(
      ironwoodMigrationAwareDisplaySpendableProvider(activeAccountUuid),
    );
    final startBlockedReason =
        quote != null &&
            swapReviewQuoteExceedsAvailableZec(quote, migrationSpendable)
        ? "You don't have enough ZEC for this payment. Try a smaller amount."
        : null;

    final title = switch (_wizardStep) {
      _PayWizardStep.amount => 'Pay in ${swapState.externalAsset.symbol}',
      _PayWizardStep.recipient => 'Select Recipient',
      _PayWizardStep.review => 'Review Payment',
    };
    final backLabel = switch (_wizardStep) {
      _PayWizardStep.amount => 'Home',
      _PayWizardStep.recipient => 'Amount',
      _PayWizardStep.review => 'Recipient',
    };
    final recipientActions = PayRecipientActions(
      typedAddress: swapState.destinationText,
      addressError: swapState
          .copyWith(destinationText: _paymentRequestText)
          .destinationAddressFormatError,
      contacts: contacts,
      busy: swapState.quoteLoading,
      enabled: swapState.externalAssetIsAvailable && !addressBookInitialLoading,
      quoteError: swapState.externalAssetSupportError ?? swapState.quoteError,
      onSelectRecipient: () => unawaited(_reviewRecipient(effectiveSelection)),
      onAddToContacts: network == null
          ? () {}
          : () => setState(() => _payModal = _PayModalSurface.addContact),
    );
    final actions = switch (_wizardStep) {
      _PayWizardStep.amount => PayAmountAction(
        state: swapState,
        onContinue: () {
          _amountFocusNode.unfocus();
          if (_reviewAfterAmount && swapState.canReviewQuote) {
            unawaited(_openReview());
          } else {
            _goToStep(_PayWizardStep.recipient);
          }
        },
      ),
      _PayWizardStep.recipient =>
        _paymentRequestText == null && recipientActions.visible
            ? recipientActions
            : null,
      _PayWizardStep.review =>
        quote == null
            ? swapState.quoteLoading
                  ? const _PayReviewLoadingAction()
                  : null
            : PayReviewAction(
                expired: swapState.quoteExpired,
                starting: _startingIntent || swapState.startSubmitting,
                startBlockedReason: startBlockedReason,
                onConfirm: _startIntent,
                onReviewAgain: () => unawaited(_openReview()),
              ),
    };

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            PayWizardPage(
              scrollController: _scrollController,
              title: title,
              currentIndex: _wizardStep.index,
              backLabel: backLabel,
              onBack: () {
                switch (_wizardStep) {
                  case _PayWizardStep.amount:
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  case _PayWizardStep.recipient:
                    _goToStep(_PayWizardStep.amount);
                  case _PayWizardStep.review:
                    _goToStep(_PayWizardStep.recipient);
                }
              },
              headingTrailing: _wizardStep == _PayWizardStep.amount
                  ? _PaySlippageControl(
                      label: formatSwapSlippage(swapState.slippageBps),
                      selected: _payModal == _PayModalSurface.slippage,
                      onTap: () =>
                          setState(() => _payModal = _PayModalSurface.slippage),
                    )
                  : null,
              actions: actions,
              onStepSelected: (index) =>
                  _goToStep(_PayWizardStep.values[index]),
              child: switch (_wizardStep) {
                _PayWizardStep.amount => PayAmountStep(
                  state: swapState,
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  onAmountChanged: (value) {
                    _paymentRequestGeneration++;
                    swapNotifier.updateReceiveAmount(value);
                  },
                  onFiatAmountChanged: (value) {
                    _paymentRequestGeneration++;
                    swapNotifier.updateReceiveAmountFiat(value);
                  },
                  onToggleFiatInputMode: () => swapNotifier.toggleFiatInputMode(
                    SwapAmountInputSide.receive,
                  ),
                  onOpenAssetSelector: () => setState(
                    () => _payModal = _PayModalSurface.assetSelector,
                  ),
                ),
                _PayWizardStep.recipient => PayRecipientStep(
                  controller: _recipientController,
                  typedAddress:
                      _paymentRequestText ?? swapState.destinationText,
                  addressError: swapState
                      .copyWith(destinationText: _paymentRequestText)
                      .destinationAddressFormatError,
                  contacts: contacts,
                  recents: recents,
                  busy: swapState.quoteLoading,
                  enabled:
                      swapState.externalAssetIsAvailable &&
                      !addressBookInitialLoading,
                  selectedContactId: swapState.userExternalContactId,
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
                  onOpenScanner: () => setState(
                    () => _payModal = _PayModalSurface.addressScanner,
                  ),
                  onChooseRecipient: _chooseRecipient,
                ),
                _PayWizardStep.review =>
                  quote == null
                      ? const SizedBox(height: 428)
                      : PayReviewStep(
                          quote: quote,
                          recipientAddress: recipientAddress,
                          recipientContact: recipientContact,
                          payingFiatText: swapReviewFiatTextForAsset(
                            swapState,
                            quote: quote,
                            asset: quote.receiveAsset,
                            amount: quote.receiveAmount,
                          ),
                          convertedFiatText: swapReviewFiatTextForAsset(
                            swapState,
                            quote: quote,
                            asset: quote.sellAsset,
                            amount: quote.sellAmount,
                          ),
                          expiresInText: _expiresInText,
                          expired: swapState.quoteExpired,
                          starting:
                              _startingIntent || swapState.startSubmitting,
                          startBlockedReason: startBlockedReason,
                          startError: swapState.statusError,
                          onShowFullAddress: () => setState(
                            () => _payModal = _PayModalSurface.verifyAddress,
                          ),
                          onConfirm: _startIntent,
                          onReviewAgain: () => unawaited(_openReview()),
                        ),
              },
            ),
            if (_payModal != null)
              AppPaneModalOverlay(
                onDismiss: _closePayModal,
                child: Material(
                  type: MaterialType.transparency,
                  child: switch (_payModal!) {
                    _PayModalSurface.assetSelector => SwapAssetSelectorModal(
                      assets: swapState.supportedExternalAssets,
                      selected: swapState.externalAsset,
                      onSelected: (asset) {
                        ref
                            .read(swapStateProvider.notifier)
                            .selectPayExternalAsset(
                              asset,
                              clearDestinationOnChainChange: true,
                            );
                        _closePayModal();
                      },
                    ),
                    _PayModalSurface.addressScanner => AddressQrScanModal(
                      onAddressScanned: _handleAddressScanned,
                      resolve: _resolvePayInput,
                      validationContext: (
                        addressInputContextKey(ref, includeSwap: true),
                        _paymentRequestGeneration,
                        _reviewRequestGeneration,
                        _wizardStep,
                      ),
                      onCancel: _closePayModal,
                    ),
                    // The contact picker surface is mobile-only; the desktop
                    // wizard surfaces contacts inline on the recipient step.
                    _PayModalSurface.contactPicker => const SizedBox.shrink(),
                    _PayModalSurface.addContact =>
                      network == null
                          ? const SizedBox.shrink()
                          : PayAddContactModal(
                              network: network,
                              address: recipientAddress,
                              onCancel: _closePayModal,
                              onSave: (label, profilePictureId) => _saveContact(
                                network,
                                label,
                                profilePictureId,
                              ),
                            ),
                    _PayModalSurface.slippage => SwapSlippageModal(
                      slippageBps: swapState.slippageBps,
                      paymentMode: true,
                      onSubmitted: (bps) {
                        ref
                            .read(swapStateProvider.notifier)
                            .updateSlippageBps(bps);
                        _closePayModal();
                      },
                      onCancel: _closePayModal,
                    ),
                    _PayModalSurface.verifyAddress => VerifyAddressModal(
                      address: recipientAddress,
                      variant: recipientContact == null
                          ? VerifyAddressModalVariant.unknown
                          : VerifyAddressModalVariant.knownContact,
                      unknownAddressKind:
                          VerifyAddressModalAddressKind.external,
                      contactName: recipientContact?.label,
                      contactProfilePictureId:
                          recipientContact?.profilePictureId,
                      onClose: _closePayModal,
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

/// Slippage affordance right of the amount-step title — same anatomy as the
/// swap composer's `_SlippageControl`.
class _PaySlippageControl extends StatelessWidget {
  const _PaySlippageControl({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('pay_slippage_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 24,
          alignment: Alignment.center,
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.ground.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(AppIcons.cog, size: 16, color: colors.icon.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayReviewLoadingAction extends StatelessWidget {
  const _PayReviewLoadingAction();

  @override
  Widget build(BuildContext context) {
    return const AppButton(
      key: ValueKey('pay_review_refreshing_button'),
      onPressed: null,
      minWidth: 196,
      child: Text('Refreshing quote'),
    );
  }
}
