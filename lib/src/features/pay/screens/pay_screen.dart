import 'dart:async';

import 'package:flutter/material.dart'
    show InputDecoration, Material, MaterialType, Scaffold, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../../address_scan/domain/address_scan_payload.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../swap/models/swap_models.dart';
import '../../swap/providers/swap_state_provider.dart';
import '../../swap/widgets/mobile/mobile_swap_asset_selector_modal.dart';
import '../../swap/widgets/swap_asset_icon.dart';
import '../../swap/widgets/swap_asset_selector_modal.dart';
import '../../swap/widgets/swap_near_intents_attribution.dart';

enum _PayModalSurface { assetSelector, addressScanner, contactPicker }

const _payHeaderGap = AppSpacing.md;
const _payStepGap = AppSpacing.sm;
const _payReviewGap = AppSpacing.md;
const _payFooterGap = AppSpacing.sm;
const _payTextFieldMessageReserve = AppSpacing.md;
const _payDesktopTokenVisibleLimit = 4;
const _payMobileTokenVisibleLimit = 3;

enum _PayComposerStep { recipient, quote }

class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({super.key});

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  late final ScrollController _scrollController;
  _PayModalSurface? _payModal;
  String? _selectedPayNetworkId;
  String? _selectedPayAssetKey;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(swapStateProvider.notifier).preparePayFromShieldedZec();
      setState(() {
        _selectedPayNetworkId = null;
        _selectedPayAssetKey = null;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _closePayModal() {
    if (_payModal == null) return;
    setState(() => _payModal = null);
  }

  void _handleDestinationChanged(String value) {
    if (_selectedPayNetworkId != null || _selectedPayAssetKey != null) {
      setState(() {
        _selectedPayNetworkId = null;
        _selectedPayAssetKey = null;
      });
    }
    ref.read(swapStateProvider.notifier).updateDestination(value);
  }

  void _handleNetworkSelected(String chainTicker, SwapState swapState) {
    final asset = _payPreferredAssetForNetwork(
      swapState.supportedExternalAssets,
      chainTicker,
      current: swapState.externalAsset,
    );
    if (asset == null) return;
    setState(() {
      _selectedPayNetworkId = chainTicker;
      _selectedPayAssetKey = asset.identityKey;
    });
    ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
  }

  void _handleAssetSelected(SwapAsset asset) {
    setState(() => _selectedPayAssetKey = asset.identityKey);
    ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
  }

  void _handleAddressScanned(String value) {
    _handleDestinationChanged(value);
    _closePayModal();
  }

  void _handleContactSelected(AddressBookContact contact, SwapState swapState) {
    final asset = _payPreferredAssetForNetwork(
      swapState.supportedExternalAssets,
      contact.network.id,
      current: swapState.externalAsset,
    );
    setState(() {
      _selectedPayNetworkId = contact.network.id;
      _selectedPayAssetKey = asset?.identityKey;
    });
    if (asset != null) {
      ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
    }
    ref.read(swapStateProvider.notifier).updateDestination(contact.address);
    _closePayModal();
  }

  Future<void> _openReview() async {
    final notifier = ref.read(swapStateProvider.notifier);
    await notifier.showReview();
    if (!mounted) return;
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
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            AppPaneScrollScaffold(
              controller: _scrollController,
              toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 488),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    child: PayComposer(
                      state: swapState,
                      selectedNetworkId: _selectedPayNetworkId,
                      selectedAssetKey: _selectedPayAssetKey,
                      zecAvailableZatoshi: sync.spendableBalance,
                      onAmountChanged: swapNotifier.updateReceiveAmount,
                      onReceiveAmountFiatChanged:
                          swapNotifier.updateReceiveAmountFiat,
                      onToggleFiatInputMode: swapNotifier.toggleFiatInputMode,
                      onDestinationChanged: _handleDestinationChanged,
                      onNetworkSelected: (chainTicker) =>
                          _handleNetworkSelected(chainTicker, swapState),
                      onAssetSelected: _handleAssetSelected,
                      onOpenAssetSelector: () => setState(
                        () => _payModal = _PayModalSurface.assetSelector,
                      ),
                      onOpenAddressScanner: () => setState(
                        () => _payModal = _PayModalSurface.addressScanner,
                      ),
                      onOpenContactPicker: () => setState(
                        () => _payModal = _PayModalSurface.contactPicker,
                      ),
                      onReviewPayment: () => unawaited(_openReview()),
                    ),
                  ),
                ),
              ),
            ),
            if (_payModal != null)
              AppPaneModalOverlay(
                onDismiss: _closePayModal,
                child: Material(
                  type: MaterialType.transparency,
                  child: switch (_payModal!) {
                    _PayModalSurface.assetSelector => SwapAssetSelectorModal(
                      assets: _payAssetsForNetwork(
                        swapState.supportedExternalAssets,
                        swapState.externalAsset.chainTicker,
                      ),
                      selected: swapState.externalAsset,
                      onSelected: (asset) {
                        _handleAssetSelected(asset);
                        _closePayModal();
                      },
                    ),
                    _PayModalSurface.addressScanner => AddressQrScanModal(
                      onAddressScanned: _handleAddressScanned,
                      onCancel: _closePayModal,
                    ),
                    _PayModalSurface.contactPicker =>
                      AddressBookContactPickerModal(
                        title: _payContactPickerTitle(
                          swapState.supportedExternalAssets,
                          _selectedPayNetworkId,
                        ),
                        networks: _payContactPickerNetworks(
                          swapState.supportedExternalAssets,
                          _selectedPayNetworkId,
                        ),
                        emptyTitle: _payContactPickerEmptyTitle(
                          swapState.supportedExternalAssets,
                          _selectedPayNetworkId,
                        ),
                        onSelected: (contact) =>
                            _handleContactSelected(contact, swapState),
                        onCancel: _closePayModal,
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

class MobilePayScreen extends ConsumerStatefulWidget {
  const MobilePayScreen({super.key});

  @override
  ConsumerState<MobilePayScreen> createState() => _MobilePayScreenState();
}

class _MobilePayScreenState extends ConsumerState<MobilePayScreen> {
  final ValueNotifier<_PayModalSurface?> _payModal =
      ValueNotifier<_PayModalSurface?>(null);
  bool _modalRouteOpen = false;
  String? _selectedPayNetworkId;
  String? _selectedPayAssetKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(swapStateProvider.notifier).preparePayFromShieldedZec();
      setState(() {
        _selectedPayNetworkId = null;
        _selectedPayAssetKey = null;
      });
    });
  }

  @override
  void dispose() {
    _payModal.dispose();
    super.dispose();
  }

  void _openModal(_PayModalSurface surface) {
    setState(() => _payModal.value = surface);
    if (_modalRouteOpen) return;
    _modalRouteOpen = true;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: context.colors.background.neutralScrim,
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => _buildPayModal(),
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

  void _handleDestinationChanged(String value) {
    if (_selectedPayNetworkId != null || _selectedPayAssetKey != null) {
      setState(() {
        _selectedPayNetworkId = null;
        _selectedPayAssetKey = null;
      });
    }
    ref.read(swapStateProvider.notifier).updateDestination(value);
  }

  void _handleNetworkSelected(String chainTicker, SwapState swapState) {
    final asset = _payPreferredAssetForNetwork(
      swapState.supportedExternalAssets,
      chainTicker,
      current: swapState.externalAsset,
    );
    if (asset == null) return;
    setState(() {
      _selectedPayNetworkId = chainTicker;
      _selectedPayAssetKey = asset.identityKey;
    });
    ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
  }

  void _handleAssetSelected(SwapAsset asset) {
    setState(() => _selectedPayAssetKey = asset.identityKey);
    ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
  }

  void _handleAddressScanned(String value) {
    _handleDestinationChanged(value);
    _closePayModal();
  }

  void _handleContactSelected(AddressBookContact contact, SwapState swapState) {
    final asset = _payPreferredAssetForNetwork(
      swapState.supportedExternalAssets,
      contact.network.id,
      current: swapState.externalAsset,
    );
    setState(() {
      _selectedPayNetworkId = contact.network.id;
      _selectedPayAssetKey = asset?.identityKey;
    });
    if (asset != null) {
      ref.read(swapStateProvider.notifier).selectPayExternalAsset(asset);
    }
    ref.read(swapStateProvider.notifier).updateDestination(contact.address);
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
            final content = switch (surface) {
              _PayModalSurface.assetSelector => MobileSwapAssetSelectorModal(
                assets: _payAssetsForNetwork(
                  swapState.supportedExternalAssets,
                  swapState.externalAsset.chainTicker,
                ),
                selected: swapState.externalAsset,
                onSelected: (asset) {
                  _handleAssetSelected(asset);
                  _closePayModal();
                },
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
              _PayModalSurface.contactPicker => AddressBookContactPickerModal(
                title: _payContactPickerTitle(
                  swapState.supportedExternalAssets,
                  _selectedPayNetworkId,
                ),
                networks: _payContactPickerNetworks(
                  swapState.supportedExternalAssets,
                  _selectedPayNetworkId,
                ),
                emptyTitle: _payContactPickerEmptyTitle(
                  swapState.supportedExternalAssets,
                  _selectedPayNetworkId,
                ),
                onSelected: (contact) =>
                    _handleContactSelected(contact, swapState),
                onCancel: _closePayModal,
              ),
            };
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
    final notifier = ref.read(swapStateProvider.notifier);
    await notifier.showReview();
    if (!mounted) return;
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
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Pay',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
              trailing: const SwapNearIntentsAttribution(alignEnd: true),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  96,
                ),
                child: PayComposer(
                  state: swapState,
                  selectedNetworkId: _selectedPayNetworkId,
                  selectedAssetKey: _selectedPayAssetKey,
                  zecAvailableZatoshi: sync.spendableBalance,
                  onAmountChanged: swapNotifier.updateReceiveAmount,
                  onReceiveAmountFiatChanged:
                      swapNotifier.updateReceiveAmountFiat,
                  onToggleFiatInputMode: swapNotifier.toggleFiatInputMode,
                  onDestinationChanged: _handleDestinationChanged,
                  onNetworkSelected: (chainTicker) =>
                      _handleNetworkSelected(chainTicker, swapState),
                  onAssetSelected: _handleAssetSelected,
                  onOpenAssetSelector: () =>
                      _openModal(_PayModalSurface.assetSelector),
                  onOpenAddressScanner: () =>
                      _openModal(_PayModalSurface.addressScanner),
                  onOpenContactPicker: () =>
                      _openModal(_PayModalSurface.contactPicker),
                  onReviewPayment: () => unawaited(_openReview()),
                  tokenVisibleLimit: _payMobileTokenVisibleLimit,
                  showHeader: false,
                  showFooterAttribution: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PayComposer extends StatefulWidget {
  const PayComposer({
    required this.state,
    required this.selectedNetworkId,
    required this.selectedAssetKey,
    required this.zecAvailableZatoshi,
    required this.onAmountChanged,
    required this.onReceiveAmountFiatChanged,
    required this.onToggleFiatInputMode,
    required this.onDestinationChanged,
    required this.onNetworkSelected,
    required this.onAssetSelected,
    required this.onOpenAssetSelector,
    required this.onOpenAddressScanner,
    required this.onOpenContactPicker,
    required this.onReviewPayment,
    this.tokenVisibleLimit = _payDesktopTokenVisibleLimit,
    this.showHeader = true,
    this.showFooterAttribution = true,
    super.key,
  });

  final SwapState state;
  final String? selectedNetworkId;
  final String? selectedAssetKey;
  final BigInt zecAvailableZatoshi;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onReceiveAmountFiatChanged;
  final ValueChanged<SwapAmountInputSide> onToggleFiatInputMode;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onNetworkSelected;
  final ValueChanged<SwapAsset> onAssetSelected;
  final VoidCallback onOpenAssetSelector;
  final VoidCallback onOpenAddressScanner;
  final VoidCallback onOpenContactPicker;
  final VoidCallback onReviewPayment;
  final int tokenVisibleLimit;
  final bool showHeader;
  final bool showFooterAttribution;

  @override
  State<PayComposer> createState() => _PayComposerState();
}

class _PayComposerState extends State<PayComposer> {
  late final TextEditingController _amountController;
  late final TextEditingController _destinationController;
  late final FocusNode _amountFocusNode;
  _PayComposerStep _step = _PayComposerStep.recipient;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _amountInputText(widget.state),
    );
    _destinationController = TextEditingController(
      text: widget.state.destinationText,
    );
    _amountFocusNode = FocusNode(debugLabel: 'PayRecipientAmount');
  }

  @override
  void didUpdateWidget(covariant PayComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_amountController, _amountInputText(widget.state));
    _syncController(_destinationController, widget.state.destinationText);
    final recipientChanged =
        oldWidget.state.destinationText != widget.state.destinationText ||
        oldWidget.selectedNetworkId != widget.selectedNetworkId;
    if (recipientChanged) {
      _step = _PayComposerStep.recipient;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _destinationController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _amountInputText(SwapState state) {
    return state.receiveAmountInputMode == SwapAmountInputMode.fiat
        ? state.receiveFiatText
        : state.receiveAmountText;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = context.colors;
    final amountPrecisionError = state.quoteAmountPrecisionError;
    final destinationError = state.destinationAddressFormatError;
    final destinationText = state.destinationText.trim();
    final selectedNetworkId = widget.selectedNetworkId;
    final selectedNetwork = selectedNetworkId == null
        ? null
        : AddressBookNetwork.tryFromChainTicker(selectedNetworkId);
    final inferredNetworks = _payInferredNetworks(
      state.supportedExternalAssets,
      destinationText,
    );
    final networkOptions = destinationText.isEmpty
        ? const <AddressBookNetwork>[]
        : inferredNetworks.isEmpty
        ? _paySupportedNetworks(state.supportedExternalAssets)
        : inferredNetworks;
    final networkReady = _paySelectedNetworkAcceptsAddress(
      selectedNetwork,
      destinationText,
    );
    final assetReady =
        networkReady &&
        (widget.selectedAssetKey == null ||
            widget.selectedAssetKey == state.externalAsset.identityKey);
    if (_step == _PayComposerStep.quote && !networkReady) {
      _step = _PayComposerStep.recipient;
    }
    final balanceExceeded = _payAmountExceedsAvailableZec(
      state,
      widget.zecAvailableZatoshi,
    );
    final quoteError = amountPrecisionError ?? state.quoteError;
    final canReview = assetReady && state.canReviewQuote && !balanceExceeded;
    final ctaLabel = _payCtaLabel(
      state,
      networkReady: networkReady,
      assetReady: assetReady,
      balanceExceeded: balanceExceeded,
      amountPrecisionError: amountPrecisionError,
      destinationError: destinationError,
    );
    final canContinue =
        destinationText.isNotEmpty &&
        networkReady &&
        destinationError == null &&
        selectedNetwork != null;

    return Column(
      key: const ValueKey('pay_composer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: AppIcon(
                  AppIcons.coins,
                  key: const ValueKey('pay_page_icon'),
                  size: 20,
                  color: colors.icon.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay',
                      key: const ValueKey('pay_page_title'),
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exact output from shielded ZEC',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: _payHeaderGap),
        ],
        if (_step == _PayComposerStep.recipient) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: _payTextFieldMessageReserve),
            child: AppTextField(
              key: const ValueKey('pay_recipient_address_field'),
              label: 'Recipient address',
              controller: _destinationController,
              hintText: 'Address or account',
              showClearButton: false,
              inputHorizontalPadding: AppSpacing.s,
              trailingSlotWidth: _payAddressActionsWidth(
                hasText: destinationText.isNotEmpty,
              ),
              trailingFitsSlot: true,
              trailing: _PayAddressActions(
                hasText: destinationText.isNotEmpty,
                onClear: () => widget.onDestinationChanged(''),
                onOpenContacts: widget.onOpenContactPicker,
                onScan: widget.onOpenAddressScanner,
              ),
              onChanged: widget.onDestinationChanged,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              textStyle: AppTypography.codeMedium.copyWith(
                color: colors.text.accent,
              ),
              tone: destinationError == null || !networkReady
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              messageText: networkReady && destinationError != null
                  ? destinationError
                  : 'Network and token unlock after this address.',
            ),
          ),
          if (destinationText.isNotEmpty) ...[
            const SizedBox(height: _payStepGap),
            _PayNetworkPanel(
              inferred: inferredNetworks.isNotEmpty,
              options: networkOptions,
              selected: selectedNetwork,
              selectedReady: networkReady,
              onSelected: widget.onNetworkSelected,
            ),
          ],
          const SizedBox(height: _payReviewGap),
          AppButton(
            key: const ValueKey('pay_continue_button'),
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            expand: true,
            onPressed: canContinue
                ? () => setState(() => _step = _PayComposerStep.quote)
                : null,
            child: const _PayButtonLabel(label: 'Continue', loading: false),
          ),
        ] else ...[
          _PayAmountStepHeader(
            assets: _payAssetsForNetwork(
              state.supportedExternalAssets,
              selectedNetworkId ?? state.externalAsset.chainTicker,
            ),
            selectedAsset: state.externalAsset,
            onSelected: widget.onAssetSelected,
            onOpenAssetSelector: widget.onOpenAssetSelector,
            tokenVisibleLimit: widget.tokenVisibleLimit,
          ),
          if (assetReady) ...[
            const SizedBox(height: _payStepGap),
            _PayAmountPanel(
              controller: _amountController,
              focusNode: _amountFocusNode,
              asset: state.externalAsset,
              inputMode: state.receiveAmountInputMode,
              rateText: _payRateTextForState(state),
              precisionError: amountPrecisionError,
              onChanged: widget.onAmountChanged,
              onFiatChanged: widget.onReceiveAmountFiatChanged,
              onToggleFiatInputMode: () =>
                  widget.onToggleFiatInputMode(SwapAmountInputSide.receive),
            ),
          ],
          if (assetReady && quoteError != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              quoteError,
              key: const ValueKey('pay_quote_error_message'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
          if (assetReady) ...[
            const SizedBox(height: _payReviewGap),
            AppButton(
              key: const ValueKey('pay_get_quote_button'),
              variant: AppButtonVariant.primary,
              size: AppButtonSize.large,
              expand: true,
              onPressed: canReview ? widget.onReviewPayment : null,
              child: _PayButtonLabel(
                label: ctaLabel,
                loading: state.quoteLoading,
              ),
            ),
          ],
        ],
        if (widget.showFooterAttribution) ...[
          const SizedBox(height: _payFooterGap),
          const Center(child: SwapNearIntentsAttribution(centered: true)),
        ],
      ],
    );
  }
}

class _PayAddressActions extends StatelessWidget {
  const _PayAddressActions({
    required this.hasText,
    required this.onClear,
    required this.onOpenContacts,
    required this.onScan,
  });

  final bool hasText;
  final VoidCallback onClear;
  final VoidCallback onOpenContacts;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (hasText)
          _PayAddressActionButton(
            key: const ValueKey('pay_recipient_clear_button'),
            icon: AppIcons.cross,
            label: 'Clear address',
            onTap: onClear,
          ),
        _PayAddressActionButton(
          key: const ValueKey('pay_recipient_contacts_button'),
          icon: AppIcons.users,
          label: 'Choose contact',
          onTap: onOpenContacts,
        ),
        _PayAddressActionButton(
          key: const ValueKey('pay_recipient_scan_button'),
          icon: AppIcons.qr,
          label: 'Scan QR',
          onTap: onScan,
        ),
      ],
    );
  }
}

class _PayAddressActionButton extends StatelessWidget {
  const _PayAddressActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppIconHoverButton(
      icon: icon,
      semanticLabel: label,
      tooltip: label,
      onTap: onTap,
      size: 32,
      iconSize: 16,
      borderRadius: BorderRadius.circular(AppRadii.xSmall),
      hoverColor: colors.background.neutralSubtleOpacity,
      iconColor: colors.icon.regular,
    );
  }
}

class _PayAmountStepHeader extends StatelessWidget {
  const _PayAmountStepHeader({
    required this.assets,
    required this.selectedAsset,
    required this.onSelected,
    required this.onOpenAssetSelector,
    required this.tokenVisibleLimit,
  });

  final List<SwapAsset> assets;
  final SwapAsset selectedAsset;
  final ValueChanged<SwapAsset> onSelected;
  final VoidCallback onOpenAssetSelector;
  final int tokenVisibleLimit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visibleAssets = _payVisibleTokenChips(
      assets,
      selectedAsset,
      visibleLimit: tokenVisibleLimit,
    );
    final showSelector = assets.length > tokenVisibleLimit;
    return Column(
      key: const ValueKey('pay_amount_step_header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'STEP 2 OF 3 - AMOUNT',
          key: const ValueKey('pay_amount_step_label'),
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Token',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          key: const ValueKey('pay_token_picker'),
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final asset in visibleAssets)
              _PayTokenOptionChip(
                asset: asset,
                selected: asset == selectedAsset,
                onTap: () => onSelected(asset),
              ),
            if (showSelector)
              _PayTokenSelectorChip(
                hiddenCount: assets.length - visibleAssets.length,
                onTap: onOpenAssetSelector,
              ),
          ],
        ),
      ],
    );
  }
}

class _PayTokenSelectorChip extends StatelessWidget {
  const _PayTokenSelectorChip({required this.hiddenCount, required this.onTap});

  final int hiddenCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = hiddenCount > 0 ? 'More' : 'All';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('pay_token_more_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(color: colors.border.subtleOpacity),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.chevronForward,
                size: 14,
                color: colors.icon.regular,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayTokenOptionChip extends StatelessWidget {
  const _PayTokenOptionChip({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final SwapAsset asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('pay_token_option_${asset.identityKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.background.inverse
                : colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(
              color: selected
                  ? colors.border.strong
                  : colors.border.subtleOpacity,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwapAssetIcon(asset: asset, size: 20, badgeScale: 0),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                asset.symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: selected ? colors.text.inverse : colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayAmountPanel extends StatelessWidget {
  const _PayAmountPanel({
    required this.controller,
    required this.focusNode,
    required this.asset,
    required this.inputMode,
    required this.rateText,
    required this.onChanged,
    required this.onFiatChanged,
    required this.onToggleFiatInputMode,
    this.precisionError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SwapAsset asset;
  final SwapAmountInputMode inputMode;
  final String rateText;
  final String? precisionError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onFiatChanged;
  final VoidCallback onToggleFiatInputMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = precisionError != null;
    final inputIsFiat = inputMode == SwapAmountInputMode.fiat;
    final inputSymbol = inputIsFiat ? 'USD' : asset.symbol;

    return Column(
      key: const ValueKey('pay_recipient_amount_field'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How much should they receive?',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: _PayAmountModeToggle(
            assetSymbol: asset.symbol,
            selectedMode: inputMode,
            onToggle: onToggleFiatInputMode,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          key: const ValueKey('pay_recipient_amount_display'),
          builder: (context, constraints) {
            final inputWidth = (constraints.maxWidth - 72)
                .clamp(148.0, 280.0)
                .toDouble();
            return SizedBox(
              height: 104,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: inputWidth,
                      child: TextField(
                        key: const ValueKey('pay_recipient_amount_input'),
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          const CommaToDotInputFormatter(),
                          _PayDecimalAmountInputFormatter(
                            maxFractionDigits: inputIsFiat ? 2 : asset.decimals,
                          ),
                        ],
                        onChanged: inputIsFiat ? onFiatChanged : onChanged,
                        textAlign: TextAlign.center,
                        style: AppTypography.displayLarge.copyWith(
                          color: colors.text.accent,
                        ),
                        cursorColor: colors.text.accent,
                        decoration: InputDecoration.collapsed(
                          hintText: '0',
                          hintStyle: AppTypography.displayLarge.copyWith(
                            color: colors.text.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Text(
                        inputSymbol,
                        key: const ValueKey('pay_recipient_amount_symbol'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          rateText,
          key: const ValueKey('pay_rate_hint'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            precisionError!,
            key: const ValueKey('pay_recipient_amount_message'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

class _PayAmountModeToggle extends StatelessWidget {
  const _PayAmountModeToggle({
    required this.assetSymbol,
    required this.selectedMode,
    required this.onToggle,
  });

  final String assetSymbol;
  final SwapAmountInputMode selectedMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final usdSelected = selectedMode == SwapAmountInputMode.fiat;
    return Container(
      key: const ValueKey('pay_amount_mode_toggle'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: colors.border.subtleOpacity),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PayAmountModeChip(
            key: const ValueKey('pay_amount_mode_usd'),
            label: 'USD',
            selected: usdSelected,
            onTap: usdSelected ? null : onToggle,
          ),
          _PayAmountModeChip(
            key: const ValueKey('pay_amount_mode_token'),
            label: assetSymbol,
            selected: !usdSelected,
            onTap: usdSelected ? onToggle : null,
          ),
        ],
      ),
    );
  }
}

class _PayAmountModeChip extends StatelessWidget {
  const _PayAmountModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 58, minHeight: 28),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? colors.background.inverse : null,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? colors.text.inverse : colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PayNetworkPanel extends StatelessWidget {
  const _PayNetworkPanel({
    required this.inferred,
    required this.options,
    required this.selected,
    required this.selectedReady,
    required this.onSelected,
  });

  final bool inferred;
  final List<AddressBookNetwork> options;
  final AddressBookNetwork? selected;
  final bool selectedReady;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusText = _payNetworkStatusText(
      inferred: inferred,
      selected: selected,
      selectedReady: selectedReady,
    );
    return Container(
      key: const ValueKey('pay_recipient_network_step'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(
          color: selectedReady
              ? colors.border.regular
              : colors.border.subtleOpacity,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recipient network',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              Text(
                inferred ? 'Detected' : 'Manual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: inferred
                      ? colors.text.positiveStrong
                      : colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final network in options)
                _PayNetworkOptionChip(
                  network: network,
                  selected: selected == network,
                  onTap: () => onSelected(network.id),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            statusText,
            style: AppTypography.bodySmall.copyWith(
              color: selectedReady
                  ? colors.text.secondary
                  : colors.text.destructive,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayNetworkOptionChip extends StatelessWidget {
  const _PayNetworkOptionChip({
    required this.network,
    required this.selected,
    required this.onTap,
  });

  final AddressBookNetwork network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('pay_network_option_${network.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.background.inverse
                : colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(
              color: selected
                  ? colors.border.strong
                  : colors.border.subtleOpacity,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AddressBookNetworkIcon(network: network, size: 18),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                network.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? colors.text.inverse : colors.text.accent,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(AppIcons.check, size: 12, color: colors.icon.inverse),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

double _payAddressActionsWidth({required bool hasText}) {
  return hasText ? 96 : 64;
}

List<AddressBookNetwork> _payContactPickerNetworks(
  List<SwapAsset> assets,
  String? selectedNetworkId,
) {
  final supported = _paySupportedNetworks(assets);
  if (selectedNetworkId == null) return supported;
  final selected = AddressBookNetwork.tryFromChainTicker(selectedNetworkId);
  if (selected == null) return supported;
  if (selected.isEvm) {
    final evmNetworks = [
      for (final network in supported)
        if (network.isEvm) network,
    ];
    return evmNetworks.isEmpty ? supported : evmNetworks;
  }
  return supported.contains(selected) ? [selected] : supported;
}

String _payContactPickerTitle(
  List<SwapAsset> assets,
  String? selectedNetworkId,
) {
  final selected = AddressBookNetwork.tryFromChainTicker(
    selectedNetworkId ?? '',
  );
  if (selected != null &&
      _payContactPickerNetworks(assets, selectedNetworkId).contains(selected)) {
    return '${selected.label} recipients';
  }
  return 'Pay recipients';
}

String _payContactPickerEmptyTitle(
  List<SwapAsset> assets,
  String? selectedNetworkId,
) {
  final selected = AddressBookNetwork.tryFromChainTicker(
    selectedNetworkId ?? '',
  );
  if (selected != null &&
      _payContactPickerNetworks(assets, selectedNetworkId).contains(selected)) {
    return 'No ${selected.label} recipients';
  }
  return 'No pay recipients';
}

List<AddressBookNetwork> _paySupportedNetworks(List<SwapAsset> assets) {
  final sorted = sortSwapAssetsForSelection(assets);
  final seen = <String>{};
  final networks = <AddressBookNetwork>[];
  for (final asset in sorted) {
    final network = AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
    if (network == null || !seen.add(network.id)) continue;
    networks.add(network);
  }
  return networks;
}

List<AddressBookNetwork> _payInferredNetworks(
  List<SwapAsset> assets,
  String address,
) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return const [];
  return [
    for (final network in _paySupportedNetworks(assets))
      if (_payNetworkCanValidate(network) &&
          _payNetworkAcceptsAddress(network, trimmed))
        network,
  ];
}

bool _paySelectedNetworkAcceptsAddress(
  AddressBookNetwork? network,
  String address,
) {
  final trimmed = address.trim();
  if (network == null || trimmed.isEmpty) return false;
  if (!_payNetworkCanValidate(network)) return true;
  return _payNetworkAcceptsAddress(network, trimmed);
}

bool _payNetworkAcceptsAddress(AddressBookNetwork network, String address) {
  final finding = addressFormatCheck(network, address);
  return finding == null || finding.severity == AddressFormatSeverity.warning;
}

bool _payNetworkCanValidate(AddressBookNetwork network) {
  if (network.isEvm) return true;
  return switch (network) {
    AddressBookNetwork.bitcoin ||
    AddressBookNetwork.solana ||
    AddressBookNetwork.near ||
    AddressBookNetwork.zcash => true,
    _ => false,
  };
}

String _payNetworkStatusText({
  required bool inferred,
  required AddressBookNetwork? selected,
  required bool selectedReady,
}) {
  if (inferred && selectedReady) {
    return '${selected?.label ?? 'Network'} matches this address.';
  }
  if (inferred) {
    return 'Choose one of the detected networks.';
  }
  if (selectedReady) {
    return 'Network selected manually. Verify it matches the recipient.';
  }
  return 'No exact match. Choose the network manually.';
}

List<SwapAsset> _payAssetsForNetwork(
  List<SwapAsset> assets,
  String chainTicker,
) {
  final normalized = chainTicker.trim().toLowerCase();
  return sortSwapAssetsForSelection(
    assets.where((asset) => asset.chainTicker.toLowerCase() == normalized),
  );
}

SwapAsset? _payPreferredAssetForNetwork(
  List<SwapAsset> assets,
  String chainTicker, {
  required SwapAsset current,
}) {
  final networkAssets = _payAssetsForNetwork(assets, chainTicker);
  if (networkAssets.isEmpty) return null;
  for (final asset in networkAssets) {
    if (asset == current) return current;
  }
  return networkAssets.first;
}

class _PayButtonLabel extends StatelessWidget {
  const _PayButtonLabel({required this.label, required this.loading});

  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1),
          if (loading) ...[
            const SizedBox(width: 4),
            const AppIcon(AppIcons.loader),
          ] else ...[
            const SizedBox(width: 4),
            const AppIcon(AppIcons.chevronForward, size: 20),
          ],
        ],
      ),
    );
  }
}

class _PayDecimalAmountInputFormatter extends TextInputFormatter {
  const _PayDecimalAmountInputFormatter({this.maxFractionDigits});

  final int? maxFractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final max = maxFractionDigits;
    final pattern = max == null
        ? RegExp(r'^\d*(\.\d*)?$')
        : RegExp('^\\d*(\\.\\d{0,$max})?\$');
    if (pattern.hasMatch(text)) return newValue;
    return oldValue;
  }
}

String _payCtaLabel(
  SwapState state, {
  required bool networkReady,
  required bool assetReady,
  required bool balanceExceeded,
  required String? amountPrecisionError,
  required String? destinationError,
}) {
  if (state.destinationText.trim().isEmpty) return 'Enter recipient address';
  if (!networkReady) return 'Select recipient network';
  if (destinationError != null) return 'Check recipient address';
  if (!assetReady) return 'Select recipient token';
  if (state.receiveAmountText.trim().isEmpty) return 'Enter amount';
  if (amountPrecisionError != null) return 'Check amount';
  if (balanceExceeded) return 'Not enough ZEC';
  if (state.quoteLoading) return 'Getting quote';
  return 'Get quote';
}

String _payRateTextForState(SwapState state) {
  final liveQuote = state.reviewQuote;
  if (liveQuote != null) return liveQuote.rateText;

  final externalPerZec =
      state.indicativeExternalPerZec[state.externalAsset] ??
      state.externalAsset.fallbackExternalPerZec;
  if (!externalPerZec.isFinite || externalPerZec <= 0) {
    return 'Rate unavailable';
  }
  if (state.direction.sendsZec) {
    return '1 ZEC = ${state.externalAsset.formatAmount(externalPerZec)} '
        '${state.externalAsset.symbol}';
  }
  return '1 ${state.externalAsset.symbol} = '
      '${SwapAsset.zec.formatAmount(1 / externalPerZec)} ZEC';
}

bool _payAmountExceedsAvailableZec(SwapState state, BigInt availableZatoshi) {
  if (!state.direction.sendsZec) return false;
  final quote = state.quote;
  if (quote == null || quote.sellAmount <= 0 || !quote.sellAmount.isFinite) {
    return false;
  }
  final requiredZatoshi = BigInt.from((quote.sellAmount * 100000000).ceil());
  return requiredZatoshi >= availableZatoshi;
}

List<SwapAsset> _payVisibleTokenChips(
  List<SwapAsset> assets,
  SwapAsset selectedAsset, {
  required int visibleLimit,
}) {
  final source = assets.isEmpty ? <SwapAsset>[selectedAsset] : assets;
  final limit = visibleLimit.clamp(1, source.length).toInt();
  if (source.length <= limit) return source;
  final visible = source.take(limit).toList();
  if (!visible.contains(selectedAsset)) {
    visible[limit - 1] = selectedAsset;
  }
  return visible;
}
