import 'dart:async';

import 'package:flutter/material.dart'
    show Material, MaterialType, showGeneralDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
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
import '../../widgets/swap_near_intents_attribution.dart';
import '../../widgets/mobile/mobile_swap_composer_ticket.dart';
import '../../widgets/mobile/mobile_swap_slippage_stepper_modal.dart';

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

  /// A ValueNotifier (rather than plain setState state) because the
  /// modal route lives on the root navigator and doesn't rebuild with
  /// this screen — its content listens to this directly.
  final ValueNotifier<_SwapModalSurface?> _swapModal =
      ValueNotifier<_SwapModalSurface?>(null);
  bool _modalRouteOpen = false;

  @override
  void dispose() {
    _swapModal.dispose();
    super.dispose();
  }

  void _openModal(_SwapModalSurface surface) {
    setState(() => _swapModal.value = surface);
    if (_modalRouteOpen) return;
    _modalRouteOpen = true;
    // One root-navigator dialog hosts every surface: the scrim must
    // cover the status bar and the floating tab bar (the shell paints
    // the bar above this screen, so an inline overlay can't reach it —
    // same convention as showAppMobileSheet). Surface switches (editor
    // → scanner → contacts → editor) swap content inside the open
    // route instead of re-navigating.
    unawaited(
      showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: context.colors.background.neutralScrim,
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => _buildSwapModal(),
      ).whenComplete(() {
        _modalRouteOpen = false;
        if (mounted) setState(() => _swapModal.value = null);
      }),
    );
  }

  void _closeSwapModal() {
    if (_modalRouteOpen) {
      // State resets in the route's whenComplete.
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    if (_swapModal.value != null) {
      setState(() => _swapModal.value = null);
    }
  }

  void _selectAddressBookContact(AddressBookContact contact) {
    ref.read(swapStateProvider.notifier).updateDestination(contact.address);
    _closeSwapModal();
  }

  /// Content of the root modal route: re-renders on surface switches
  /// via [_swapModal] and on swap state changes via its own Consumer
  /// (the route doesn't rebuild with the screen). Empty space around
  /// the card falls through to the dialog barrier, which dismisses.
  Widget _buildSwapModal() {
    return ValueListenableBuilder<_SwapModalSurface?>(
      valueListenable: _swapModal,
      builder: (context, surface, _) {
        if (surface == null) return const SizedBox.shrink();
        return Consumer(
          builder: (context, ref, _) {
            final swapState = ref.watch(swapStateProvider);
            final swapNotifier = ref.read(swapStateProvider.notifier);
            return Padding(
              // The root route doesn't resize with the shell scaffold,
              // so it keeps the card above the keyboard itself.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: switch (surface) {
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
                      onSubmitted:
                          (value, remember, nickname, profilePictureId) {
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
                      onScan: () =>
                          _openModal(_SwapModalSurface.addressScanner),
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
                    _SwapModalSurface.slippageSettings =>
                      MobileSwapSlippageStepperModal(
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
            );
          },
        );
      },
    );
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
        _closeSwapModal();
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

    final quoteError =
        swapState.quoteAmountPrecisionError ?? swapState.quoteError;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Column(
            children: [
              const MobileTopNav.back(
                title: 'Swap',
                trailing: SwapNearIntentsAttribution(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  // The ticket sits flush under the top nav — Figma
                  // 4686:101436 has no gap above the swap widget.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    // Clears the floating tab bar.
                    96,
                  ),
                  child: Column(
                    children: [
                      MobileSwapComposerTicket(
                        state: swapState,
                        onAmountChanged: swapNotifier.updateAmount,
                        onAmountFiatChanged: swapNotifier.updateAmountFiat,
                        onReceiveAmountChanged:
                            swapNotifier.updateReceiveAmount,
                        onReceiveAmountFiatChanged:
                            swapNotifier.updateReceiveAmountFiat,
                        onToggleFiatInputMode: swapNotifier.toggleFiatInputMode,
                        onToggleDirection: swapNotifier.toggleDirection,
                        onOpenExternalAssetPicker: () =>
                            _openModal(_SwapModalSurface.assetSelector),
                        onOpenDestinationAddress: () =>
                            _openModal(_SwapModalSurface.addressEditor),
                        onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                        zecAvailableText: zecAvailableText,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          AppButton(
                            key: const ValueKey('swap_settings_button'),
                            variant: AppButtonVariant.secondary,
                            onPressed: () =>
                                _openModal(_SwapModalSurface.slippageSettings),
                            trailing: const AppIcon(AppIcons.cog),
                            child: Text(
                              formatSwapSlippage(swapState.slippageBps),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: _MobileSwapReviewButton(
                              state: swapState,
                              zecAvailableZatoshi: sync.spendableBalance,
                              onOpenDestinationAddress: () =>
                                  _openModal(_SwapModalSurface.addressEditor),
                              onReviewQuote: openReview,
                            ),
                          ),
                        ],
                      ),
                      if (quoteError != null) ...[
                        const SizedBox(height: AppSpacing.s),
                        Text(
                          quoteError,
                          key: const ValueKey('swap_quote_error_message'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: context.colors.text.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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
      child: Text(label),
    );
  }
}
