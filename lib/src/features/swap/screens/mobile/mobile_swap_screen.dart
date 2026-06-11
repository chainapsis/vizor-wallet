import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../models/swap_address_book_helpers.dart';
import '../../models/swap_models.dart';
import '../../providers/swap_state_provider.dart';
import '../../widgets/swap_address_edit_modal.dart';
import '../../widgets/swap_asset_selector_modal.dart';
import '../../widgets/swap_composer_panel.dart';
import '../../widgets/swap_near_intents_attribution.dart';
import '../../widgets/swap_slippage_modal.dart';

enum _SwapModalSurface {
  assetSelector,
  addressEditor,
  addressScanner,
  contactPicker,
  slippageSettings,
}

/// Mobile swap composer — Figma `Swap` / `Swap v1` (4691:102452,
/// 4686:101421): the same NEAR-intents composer as the desktop pane,
/// laid out for the phone with the modal surfaces presented over the
/// tab. Review pushes /swap/review.
class MobileSwapScreen extends ConsumerStatefulWidget {
  const MobileSwapScreen({super.key});

  @override
  ConsumerState<MobileSwapScreen> createState() => _MobileSwapScreenState();
}

class _MobileSwapScreenState extends ConsumerState<MobileSwapScreen> {
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'mobile_swap_toast_overlay_context',
  );
  _SwapModalSurface? _swapModal;

  void _openModal(_SwapModalSurface surface) {
    setState(() => _swapModal = surface);
  }

  void _closeSwapModal() {
    if (_swapModal == null) return;
    setState(() => _swapModal = null);
  }

  void _selectAddressBookContact(AddressBookContact contact) {
    ref.read(swapStateProvider.notifier).updateDestination(contact.address);
    _closeSwapModal();
  }

  /// Same convenience save as the desktop swap screen.
  Future<void> _rememberSwapAddress(
    String value,
    SwapState swapState,
    String? nickname,
    String profilePictureId,
  ) async {
    final address = value.trim();
    if (address.isEmpty) return;
    final network = addressBookNetworkForSwapDestination(swapState);
    if (network == null) return;

    final trimmedNickname = nickname?.trim() ?? '';
    final label = trimmedNickname.isEmpty
        ? swapAddressBookLabel(swapState)
        : trimmedNickname;

    try {
      final current =
          ref.read(addressBookProvider).asData?.value ??
          await ref.read(addressBookProvider.future);
      if (current == null) return;
      final normalizedAddress = address.toLowerCase();
      final alreadySaved = current.contacts.any(
        (contact) =>
            contact.network == network &&
            contact.address.trim().toLowerCase() == normalizedAddress,
      );
      if (alreadySaved) {
        final toastContext = _toastOverlayContextKey.currentContext;
        if (toastContext != null && toastContext.mounted) {
          showAppToast(toastContext, 'Already in your address book');
        }
        return;
      }

      await ref
          .read(addressBookProvider.notifier)
          .addContact(
            label: label,
            network: network,
            address: address,
            profilePictureId: profilePictureId,
          );
    } catch (_) {
      // Saving a convenience contact must not block the swap form update.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next || !mounted) return;
        setState(() => _swapModal = null);
      },
    );
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
    final zecAvailableText = ZecAmount.fromZatoshi(
      sync.spendableBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();

    void openReview() {
      unawaited(() async {
        await swapNotifier.showReview();
        if (!context.mounted) return;
        final next = ref.read(swapStateProvider);
        if (next.reviewVisible &&
            next.reviewQuote != null &&
            next.reviewAddressPlan != null) {
          await context.push('/swap/review');
        }
      }());
    }

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Column(
            children: [
              const MobileTopNav.back(title: 'Swap'),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panelWidth = constraints.maxWidth - AppSpacing.sm * 2;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.s,
                        AppSpacing.sm,
                        // Clears the floating tab bar.
                        96,
                      ),
                      child: Column(
                        children: [
                          SwapComposerPanel(
                            width: panelWidth,
                            state: swapState,
                            onAmountChanged: swapNotifier.updateAmount,
                            onAmountFiatChanged: swapNotifier.updateAmountFiat,
                            onReceiveAmountChanged:
                                swapNotifier.updateReceiveAmount,
                            onReceiveAmountFiatChanged:
                                swapNotifier.updateReceiveAmountFiat,
                            onToggleFiatInputMode:
                                swapNotifier.toggleFiatInputMode,
                            onToggleDirection: swapNotifier.toggleDirection,
                            onOpenExternalAssetPicker: () =>
                                _openModal(_SwapModalSurface.assetSelector),
                            onOpenDestinationAddress: () =>
                                _openModal(_SwapModalSurface.addressEditor),
                            onOpenSlippageSettings: () =>
                                _openModal(_SwapModalSurface.slippageSettings),
                            onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                            assetSelectorOpen:
                                _swapModal == _SwapModalSurface.assetSelector,
                            slippageSettingsOpen:
                                _swapModal ==
                                _SwapModalSurface.slippageSettings,
                            zecAvailableText: zecAvailableText,
                            zecAvailableZatoshi: sync.spendableBalance,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _MobileSwapReviewButton(
                            state: swapState,
                            zecAvailableZatoshi: sync.spendableBalance,
                            onOpenDestinationAddress: () =>
                                _openModal(_SwapModalSurface.addressEditor),
                            onReviewQuote: openReview,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Center(child: SwapNearIntentsAttribution()),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_swapModal != null)
            AppPaneModalOverlay(
              onDismiss: _closeSwapModal,
              child: Material(
                type: MaterialType.transparency,
                child: switch (_swapModal!) {
                  _SwapModalSurface.assetSelector => SwapAssetSelectorModal(
                    assets: swapState.supportedExternalAssets,
                    selected: swapState.externalAsset,
                    onSelected: (asset) {
                      swapNotifier.selectExternalAsset(asset);
                      _closeSwapModal();
                    },
                  ),
                  _SwapModalSurface.addressEditor => SwapAddressEditModal(
                    state: swapState,
                    onSubmitted: (value, remember, nickname, profilePictureId) {
                      if (remember) {
                        unawaited(
                          _rememberSwapAddress(
                            value,
                            swapState,
                            nickname,
                            profilePictureId,
                          ),
                        );
                      }
                      swapNotifier.updateDestination(value);
                      _closeSwapModal();
                    },
                    onScan: () => _openModal(_SwapModalSurface.addressScanner),
                    onOpenContacts: () =>
                        _openModal(_SwapModalSurface.contactPicker),
                    onCancel: _closeSwapModal,
                  ),
                  _SwapModalSurface.addressScanner => AddressQrScanModal(
                    onAddressScanned: (value) {
                      swapNotifier.updateDestination(value);
                      _closeSwapModal();
                    },
                    onCancel: _closeSwapModal,
                  ),
                  _SwapModalSurface.contactPicker =>
                    AddressBookContactPickerModal(
                      title: swapContactPickerTitle(swapState),
                      networks: swapContactPickerNetworks(swapState),
                      emptyTitle: swapContactPickerEmptyTitle(swapState),
                      onSelected: _selectAddressBookContact,
                      onCancel: () =>
                          _openModal(_SwapModalSurface.addressEditor),
                    ),
                  _SwapModalSurface.slippageSettings => SwapSlippageModal(
                    slippageBps: swapState.slippageBps,
                    onSubmitted: (value) {
                      swapNotifier.updateSlippageBps(value);
                      _closeSwapModal();
                    },
                    onCancel: _closeSwapModal,
                  ),
                },
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: AppToastHost(
                key: const ValueKey('mobile_swap_toast_overlay_host'),
                child: SizedBox.expand(key: _toastOverlayContextKey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same enable/label logic as the desktop `_SwapReviewFooter`, sized
/// for the mobile column.
class _MobileSwapReviewButton extends StatelessWidget {
  const _MobileSwapReviewButton({
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onOpenDestinationAddress,
    required this.onReviewQuote,
  });

  final SwapState state;
  final BigInt zecAvailableZatoshi;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onReviewQuote;

  bool get _balanceExceeded {
    if (!state.direction.sendsZec) return false;
    final amount = parseZecAmount(state.amountText.trim());
    if (amount == null || amount <= BigInt.zero) return false;
    return amount >= zecAvailableZatoshi;
  }

  @override
  Widget build(BuildContext context) {
    final needsDestinationAddress = state.destinationText.trim().isEmpty;
    final destinationFormatError = state.destinationAddressFormatError;
    final balanceExceeded = _balanceExceeded;
    final canReview = state.canReviewQuote && !balanceExceeded;
    final onPressed = needsDestinationAddress
        ? onOpenDestinationAddress
        : canReview
        ? onReviewQuote
        : null;
    final label = needsDestinationAddress
        ? (state.direction.sendsZec
              ? 'Add recipient address'
              : 'Add refund address')
        : destinationFormatError ??
              (balanceExceeded
                  ? 'Not enough ZEC'
                  : state.quoteLoading
                  ? 'Getting quote'
                  : 'Continue to review');

    return AppButton(
      key: const ValueKey('mobile_swap_review_button'),
      expand: true,
      onPressed: onPressed,
      variant: needsDestinationAddress
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      trailing: needsDestinationAddress
          ? null
          : const AppIcon(AppIcons.chevronForward),
      child: Text(label),
    );
  }
}
