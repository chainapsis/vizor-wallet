import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../models/swap_activity_status_mapper.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../widgets/swap_address_edit_modal.dart';
import '../widgets/swap_asset_selector_modal.dart';
import '../widgets/swap_composer_panel.dart';
import '../widgets/swap_near_intents_attribution.dart';
import '../widgets/swap_slippage_modal.dart';

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key});

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

enum _SwapModalSurface {
  assetSelector,
  addressEditor,
  addressScanner,
  contactPicker,
  slippageSettings,
}

AddressBookNetwork? _addressBookNetworkForSwapDestination(SwapState state) {
  final asset = state.externalAsset;
  return AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
}

List<AddressBookNetwork> _swapContactPickerNetworks(SwapState state) {
  final network = _addressBookNetworkForSwapDestination(state);
  if (network == null) return const [];
  // EVM addresses are interchangeable across EVM chains (the same 0x account
  // works on every one), so let the user pick any saved EVM contact — e.g. a
  // Polygon address as the refund for a Base swap. Non-EVM chains keep the
  // exact-network filter since those address formats are chain-specific.
  if (network.isEvm) {
    return [
      for (final candidate in AddressBookNetwork.values)
        if (candidate.isEvm) candidate,
    ];
  }
  return [network];
}

String _swapContactPickerTitle(SwapState state) {
  final role = state.direction.sendsZec ? 'recipients' : 'refunds';
  return '${state.externalAsset.symbol} $role';
}

String _swapContactPickerEmptyTitle(SwapState state) {
  final role = state.direction.sendsZec ? 'recipients' : 'refunds';
  return 'No saved ${state.externalAsset.symbol} $role';
}

String _swapAddressBookLabel(SwapState state) {
  final role = state.direction.sendsZec ? 'recipient' : 'refund';
  return '${state.externalAsset.symbol} $role';
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  late final ScrollController _scrollController;
  late final FocusNode _shortcutFocusNode;
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_toast_overlay_context',
  );
  _SwapModalSurface? _swapModal;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _shortcutFocusNode = FocusNode(debugLabel: 'SwapScreenShortcuts');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shortcutFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  void _openAssetSelector() {
    setState(() => _swapModal = _SwapModalSurface.assetSelector);
  }

  void _openAddressEditor() {
    setState(() => _swapModal = _SwapModalSurface.addressEditor);
  }

  void _openAddressScanner() {
    setState(() => _swapModal = _SwapModalSurface.addressScanner);
  }

  void _openAddressContactPicker() {
    setState(() => _swapModal = _SwapModalSurface.contactPicker);
  }

  void _openSlippageSettings() {
    setState(() => _swapModal = _SwapModalSurface.slippageSettings);
  }

  void _closeSwapModal() {
    if (_swapModal == null) return;
    setState(() => _swapModal = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shortcutFocusNode.requestFocus();
    });
  }

  void _selectAddressBookContact(AddressBookContact contact) {
    ref.read(swapStateProvider.notifier).updateDestination(contact.address);
    _closeSwapModal();
  }

  Future<void> _rememberSwapAddress(
    String value,
    SwapState swapState,
    String? nickname,
    String profilePictureId,
  ) async {
    final address = value.trim();
    if (address.isEmpty) return;
    final network = _addressBookNetworkForSwapDestination(swapState);
    if (network == null) return;

    // The modal requires a nickname when "remember" is on; fall back to the
    // auto-generated label only as a defensive default (e.g. an empty value
    // slipping through from a future caller).
    final trimmedNickname = nickname?.trim() ?? '';
    final label = trimmedNickname.isEmpty
        ? _swapAddressBookLabel(swapState)
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
        // Don't create a duplicate, but tell the user why nothing was saved —
        // otherwise the chosen label/avatar would vanish with no feedback.
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

    void refreshStatus() {
      final selected = ref.read(swapStateProvider).selectedIntentOrNull;
      if (selected == null || !canRefreshSwapIntentStatus(selected.status)) {
        return;
      }
      unawaited(swapNotifier.refreshSelectedIntentStatus());
    }

    KeyEventResult handleShortcut(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final keyboard = HardwareKeyboard.instance;
      final commandPressed =
          keyboard.isMetaPressed || keyboard.isControlPressed;
      if (!commandPressed) return KeyEventResult.ignored;

      if (event.logicalKey == LogicalKeyboardKey.digit1) {
        context.go('/swap');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.digit2) {
        context.go('/activity');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        refreshStatus();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: handleShortcut,
      child: AppDesktopShell(
        sidebar: const AppMainSidebar(),
        pane: AppDesktopPane(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              AppPaneScrollScaffold(
                controller: _scrollController,
                toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panel = SwapComposerPanel(
                      state: swapState,
                      onAmountChanged: swapNotifier.updateAmount,
                      onAmountFiatChanged: swapNotifier.updateAmountFiat,
                      onReceiveAmountChanged: swapNotifier.updateReceiveAmount,
                      onReceiveAmountFiatChanged:
                          swapNotifier.updateReceiveAmountFiat,
                      onToggleFiatInputMode: swapNotifier.toggleFiatInputMode,
                      onToggleDirection: swapNotifier.toggleDirection,
                      onOpenExternalAssetPicker: _openAssetSelector,
                      onOpenDestinationAddress: _openAddressEditor,
                      assetSelectorOpen:
                          _swapModal == _SwapModalSurface.assetSelector,
                      onOpenSlippageSettings: _openSlippageSettings,
                      slippageSettingsOpen:
                          _swapModal == _SwapModalSurface.slippageSettings,
                      onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                      zecAvailableText: zecAvailableText,
                      zecAvailableZatoshi: sync.spendableBalance,
                    );
                    // Figma container (420×656, 16px vertical padding): the
                    // title is pinned under the toolbar, the attribution and
                    // CTA are pinned at the bottom, and the swap section
                    // flexes to center the widget between them. Pinning only
                    // engages when the pane offers the design height;
                    // shorter panes pack the column and scroll instead.
                    final pinned =
                        constraints.minHeight >= _swapBodyPinnedMinHeight;
                    final column = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SwapPageTitle(),
                        const SizedBox(height: AppSpacing.md),
                        if (pinned)
                          Expanded(child: Center(child: panel))
                        else
                          panel,
                        const SizedBox(height: AppSpacing.md),
                        const _SwapAttributionSlot(),
                        const SizedBox(height: AppSpacing.md),
                        _SwapReviewFooter(
                          state: swapState,
                          zecAvailableZatoshi: sync.spendableBalance,
                          onOpenDestinationAddress: _openAddressEditor,
                          onReviewQuote: openReview,
                        ),
                      ],
                    );
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s,
                          ),
                          child: pinned
                              ? SizedBox(
                                  height: constraints.minHeight,
                                  child: column,
                                )
                              : column,
                        ),
                      ),
                    );
                  },
                ),
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
                        onScan: _openAddressScanner,
                        onOpenContacts: _openAddressContactPicker,
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
                          title: _swapContactPickerTitle(swapState),
                          networks: _swapContactPickerNetworks(swapState),
                          emptyTitle: _swapContactPickerEmptyTitle(swapState),
                          onSelected: _selectAddressBookContact,
                          onCancel: _openAddressEditor,
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
                    key: const ValueKey('swap_toast_overlay_host'),
                    child: SizedBox.expand(key: _toastOverlayContextKey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Design pane height (Figma content area 656 minus 16px vertical padding)
/// at which the pinned title/footer layout engages.
const double _swapBodyPinnedMinHeight = 624;

/// Figma '_Swap near Logo' slot: a 32dp-high box with the lockup centered.
class _SwapAttributionSlot extends StatelessWidget {
  const _SwapAttributionSlot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: Center(child: SwapNearIntentsAttribution(centered: true)),
    );
  }
}

class _SwapPageTitle extends StatelessWidget {
  const _SwapPageTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      'Swap',
      key: const ValueKey('swap_page_title'),
      textAlign: TextAlign.center,
      style: appSerifDisplayStyle(color: colors.text.accent),
    );
  }
}

class _SwapReviewFooter extends StatelessWidget {
  const _SwapReviewFooter({
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onOpenDestinationAddress,
    required this.onReviewQuote,
  });

  final SwapState state;
  final BigInt zecAvailableZatoshi;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onReviewQuote;

  @override
  Widget build(BuildContext context) {
    final balanceExceeded = _reviewAmountExceedsAvailableZec(
      state,
      zecAvailableZatoshi,
    );
    final needsDestinationAddress = state.destinationText.trim().isEmpty;
    final destinationFormatError = state.destinationAddressFormatError;
    final canReview = state.canReviewQuote && !balanceExceeded;
    final onPressed = needsDestinationAddress
        ? onOpenDestinationAddress
        : canReview
        ? onReviewQuote
        : null;
    final loading = state.quoteLoading && !needsDestinationAddress;
    final label = needsDestinationAddress
        ? _destinationAddressActionLabel(state)
        : destinationFormatError ??
              (balanceExceeded
                  ? 'Not enough ZEC'
                  : state.quoteLoading
                  ? 'Getting quote'
                  : 'Review swap');
    final reviewReady =
        !needsDestinationAddress &&
        destinationFormatError == null &&
        !balanceExceeded &&
        !state.quoteLoading;

    return Center(
      child: SizedBox(
        width: 232,
        child: AppButton(
          key: const ValueKey('swap_review_button'),
          onPressed: onPressed,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: 232,
          child: SizedBox(
            width: 168,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _SwapReviewButtonLabel(
                label: label,
                loading: loading,
                showChevron: reviewReady,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapReviewButtonLabel extends StatelessWidget {
  const _SwapReviewButtonLabel({
    required this.label,
    required this.loading,
    this.showChevron = false,
  });

  final String label;
  final bool loading;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1),
        if (loading) ...[
          const SizedBox(width: 4),
          const AppIcon(AppIcons.loader),
        ] else if (showChevron) ...[
          const SizedBox(width: 4),
          const AppIcon(AppIcons.chevronForward, size: 20),
        ],
      ],
    );
  }
}

String _destinationAddressActionLabel(SwapState state) {
  return state.direction.sendsZec
      ? 'Add recipient address'
      : 'Add refund address';
}

bool _reviewAmountExceedsAvailableZec(
  SwapState state,
  BigInt availableZatoshi,
) {
  if (!state.direction.sendsZec) return false;
  return _zecAmountTextExceedsAvailable(state.amountText, availableZatoshi);
}

bool _zecAmountTextExceedsAvailable(
  String amountText,
  BigInt availableZatoshi,
) {
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
