import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart';
import '../../models/swap_address_book_helpers.dart';
import '../../models/swap_models.dart';
import '../../providers/swap_state_provider.dart';
import '../../widgets/swap_address_edit_modal.dart';
import '../../widgets/swap_asset_selector_modal.dart';
import '../../widgets/swap_near_intents_attribution.dart';
import '../../widgets/mobile/mobile_swap_composer_ticket.dart';
import '../../widgets/mobile/mobile_swap_slippage_stepper_modal.dart';

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

  /// The asset selector on the standard full-screen sheet
  /// ([showMobileSheet] + [MobileSheetScaffold]). A Consumer keeps the
  /// list in sync with swap state while the sheet is open.
  void _openAssetSelector() {
    unawaited(
      showMobileSheet<void>(
        context: context,
        builder: (sheetContext) => Consumer(
          builder: (context, ref, _) {
            final swapState = ref.watch(swapStateProvider);
            return MobileSheetScaffold(
              title: 'Select asset',
              expand: true,
              child: SwapAssetSelectorModal(
                assets: swapState.supportedExternalAssets,
                selected: swapState.externalAsset,
                loading: swapState.externalAssetsLoading,
                onSelected: (asset) {
                  ref
                      .read(swapStateProvider.notifier)
                      .selectExternalAsset(asset);
                  Navigator.of(sheetContext).pop();
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Slippage editor on a content-sized standard sheet (hugs its form).
  void _openSlippage() {
    final swapState = ref.read(swapStateProvider);
    final swapNotifier = ref.read(swapStateProvider.notifier);
    unawaited(
      showMobileSheet<void>(
        context: context,
        builder: (sheetContext) => MobileSheetScaffold(
          title: 'Slippage',
          formBody: true,
          child: MobileSwapSlippageStepperModal(
            slippageBps: swapState.slippageBps,
            onSubmitted: (value) {
              swapNotifier.updateSlippageBps(value);
              Navigator.of(sheetContext).pop();
            },
            onCancel: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  /// One sheet for the recipient/refund flow: the editor, with the contacts
  /// picker shown as a 2nd-level view inside the same sheet (back chevron),
  /// and the QR scanner pushed full-screen over it. See [_SwapAddressSheet].
  void _openAddressEditor() {
    unawaited(
      showMobileSheet<void>(
        context: context,
        builder: (_) =>
            _SwapAddressSheet(onRememberAddress: _rememberSwapAddress),
      ),
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
                        onOpenExternalAssetPicker: _openAssetSelector,
                        onOpenDestinationAddress: _openAddressEditor,
                        onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                        zecAvailableText: zecAvailableText,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          AppButton(
                            key: const ValueKey('swap_settings_button'),
                            variant: AppButtonVariant.secondary,
                            onPressed: _openSlippage,
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
                              onOpenDestinationAddress: _openAddressEditor,
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

enum _AddressSheetView { editor, contacts }

/// The recipient/refund flow in a single content-sized sheet. The editor is
/// the base view; tapping contacts swaps the sheet content to the picker
/// (a back chevron returns to the editor), and the QR scanner is pushed
/// full-screen over the sheet. Watching swap state means an address chosen
/// via scan/contacts flows into the editor's field.
class _SwapAddressSheet extends ConsumerStatefulWidget {
  const _SwapAddressSheet({required this.onRememberAddress});

  final Future<void> Function(
    String value,
    SwapState swapState,
    String? nickname,
    String profilePictureId,
  )
  onRememberAddress;

  @override
  ConsumerState<_SwapAddressSheet> createState() => _SwapAddressSheetState();
}

class _SwapAddressSheetState extends ConsumerState<_SwapAddressSheet> {
  _AddressSheetView _view = _AddressSheetView.editor;

  void _showEditor() => setState(() => _view = _AddressSheetView.editor);
  void _showContacts() => setState(() => _view = _AddressSheetView.contacts);

  void _openScanner() {
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          pageBuilder: (routeContext, _, _) => MobileAddressScanView(
            resolve: (raw) async {
              final address = normalizeAddressScanPayload(raw);
              if (address == null || address.isEmpty) {
                return const MobileScanOutcome.rejected(
                  'QR code did not include an address.',
                );
              }
              return MobileScanOutcome.accepted(address);
            },
            onScanned: (value) {
              ref.read(swapStateProvider.notifier).updateDestination(value);
              Navigator.of(routeContext).pop();
            },
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final notifier = ref.read(swapStateProvider.notifier);

    if (_view == _AddressSheetView.contacts) {
      final title = swapContactPickerTitle(swapState);
      return MobileSheetScaffold(
        title: title,
        onBack: _showEditor,
        fillBody: true,
        child: AddressBookContactPickerModal(
          title: title,
          networks: swapContactPickerNetworks(swapState),
          emptyTitle: swapContactPickerEmptyTitle(swapState),
          onSelected: (contact) {
            notifier.updateDestination(contact.address);
            _showEditor();
          },
          onCancel: _showEditor,
        ),
      );
    }

    final asset = swapState.externalAsset;
    final title = swapState.direction.sendsZec
        ? '${asset.symbol} recipient address'
        : '${asset.symbol} refund address';
    return MobileSheetScaffold(
      title: title,
      formBody: true,
      child: SwapAddressEditModal(
        state: swapState,
        onSubmitted: (value, remember, nickname, profilePictureId) {
          if (remember) {
            unawaited(
              widget.onRememberAddress(
                value,
                swapState,
                nickname,
                profilePictureId,
              ),
            );
          }
          notifier.updateDestination(value);
          Navigator.of(context).pop();
        },
        onScan: _openScanner,
        onOpenContacts: _showContacts,
        onCancel: () => Navigator.of(context).pop(),
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
      constrainContent: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
