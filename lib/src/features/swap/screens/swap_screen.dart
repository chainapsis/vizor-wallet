import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../models/swap_prototype_models.dart';
import '../providers/swap_prototype_provider.dart';
import '../widgets/redacted_receipt_drawer.dart';
import '../widgets/swap_activity_panel.dart';
import '../widgets/swap_address_qr_scan_modal.dart';
import '../widgets/swap_composer_panel.dart';
import '../widgets/swap_copy_feedback.dart';
import '../widgets/swap_near_intents_attribution.dart';

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

const double _swapBodyDesignHeight = 580;

AddressBookNetwork? _addressBookNetworkForSwapDestination(
  SwapPrototypeState state,
) {
  final asset = state.externalAsset;
  return AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
}

List<AddressBookNetwork> _swapContactPickerNetworks(SwapPrototypeState state) {
  final network = _addressBookNetworkForSwapDestination(state);
  return network == null ? const [] : [network];
}

String _swapContactPickerTitle(SwapPrototypeState state) {
  final role = state.direction.sendsZec ? 'Recipients' : 'Refunds';
  return '${state.externalAsset.symbol} $role';
}

String _swapContactPickerEmptyTitle(SwapPrototypeState state) {
  final role = state.direction.sendsZec ? 'recipients' : 'refunds';
  return 'No saved ${state.externalAsset.symbol} $role';
}

String _swapAddressBookLabel(SwapPrototypeState state) {
  final role = state.direction.sendsZec ? 'recipient' : 'refund';
  return '${state.externalAsset.symbol} $role';
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  late final ScrollController _scrollController;
  late final FocusNode _shortcutFocusNode;
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_toast_overlay_context',
  );
  bool _commandPaletteOpen = false;
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

  void _openCommandPalette() {
    setState(() {
      _commandPaletteOpen = true;
      _swapModal = null;
    });
  }

  void _closeCommandPalette() {
    setState(() => _commandPaletteOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shortcutFocusNode.requestFocus();
    });
  }

  void _openAssetSelector() {
    setState(() {
      _commandPaletteOpen = false;
      _swapModal = _SwapModalSurface.assetSelector;
    });
  }

  void _openAddressEditor() {
    setState(() {
      _commandPaletteOpen = false;
      _swapModal = _SwapModalSurface.addressEditor;
    });
  }

  void _openAddressScanner() {
    setState(() {
      _commandPaletteOpen = false;
      _swapModal = _SwapModalSurface.addressScanner;
    });
  }

  void _openAddressContactPicker() {
    setState(() {
      _commandPaletteOpen = false;
      _swapModal = _SwapModalSurface.contactPicker;
    });
  }

  void _openSlippageSettings() {
    setState(() {
      _commandPaletteOpen = false;
      _swapModal = _SwapModalSurface.slippageSettings;
    });
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
    ref.read(swapPrototypeProvider.notifier).updateDestination(contact.address);
    _closeSwapModal();
  }

  Future<void> _rememberSwapAddress(
    String value,
    SwapPrototypeState swapState,
  ) async {
    final address = value.trim();
    if (address.isEmpty) return;
    final network = _addressBookNetworkForSwapDestination(swapState);
    if (network == null) return;

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
      if (alreadySaved) return;

      await ref
          .read(addressBookProvider.notifier)
          .addContact(
            label: _swapAddressBookLabel(swapState),
            network: network,
            address: address,
            profilePictureId: kDefaultProfilePictureId,
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
        setState(() {
          _commandPaletteOpen = false;
          _swapModal = null;
        });
      },
    );
    final swapState = ref.watch(swapPrototypeProvider);
    final swapNotifier = ref.read(swapPrototypeProvider.notifier);
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
    final selectedIntent = swapState.selectedIntentOrNull;

    void openReview() {
      unawaited(() async {
        await swapNotifier.showReview();
        if (!context.mounted) return;
        final next = ref.read(swapPrototypeProvider);
        if (next.reviewVisible &&
            next.reviewQuote != null &&
            next.reviewAddressPlan != null) {
          await context.push('/swap/review');
        }
      }());
    }

    void refreshStatus() {
      final selected = ref.read(swapPrototypeProvider).selectedIntentOrNull;
      if (selected == null || !canRefreshSwapIntentStatus(selected.status)) {
        return;
      }
      unawaited(swapNotifier.refreshSelectedIntentStatus());
    }

    void reviewFreshQuote() {
      swapNotifier.prepareRetryFromSelectedIntent();
      context.go('/swap');
    }

    void runPaletteAction(VoidCallback action) {
      _closeCommandPalette();
      _closeSwapModal();
      action();
    }

    final activeReceiptText = selectedIntent == null
        ? ''
        : redactedReceiptText(selectedIntent.receipt);
    final activeDepositAddress = selectedIntent?.depositAddress;
    final canReviewFreshQuote =
        selectedIntent?.status == SwapIntentStatus.incompleteDeposit ||
        selectedIntent?.status == SwapIntentStatus.refunded ||
        selectedIntent?.status == SwapIntentStatus.expired ||
        selectedIntent?.status == SwapIntentStatus.failed;
    final commandItems = [
      _SwapCommandItem(
        id: 'open_swap',
        title: 'Open Swap',
        detail: 'Composer and quote review',
        iconName: AppIcons.sync,
        onRun: () => runPaletteAction(() => context.go('/swap')),
      ),
      _SwapCommandItem(
        id: 'open_activity',
        title: 'Open Activity',
        detail: 'Status, receipt, and recovery',
        iconName: AppIcons.history,
        onRun: () => runPaletteAction(() => context.go('/activity')),
      ),
      _SwapCommandItem(
        id: 'refresh_status',
        title: 'Refresh Status',
        detail: selectedIntent?.statusLabel ?? 'No active swap',
        iconName: AppIcons.renew,
        enabled:
            selectedIntent != null &&
            canRefreshSwapIntentStatus(selectedIntent.status) &&
            !swapState.statusRefreshing,
        onRun: () => runPaletteAction(() {
          context.go('/activity');
          refreshStatus();
        }),
      ),
      _SwapCommandItem(
        id: 'copy_receipt',
        title: 'Copy Receipt',
        detail: 'Redacted activity evidence',
        iconName: AppIcons.copy,
        enabled: activeReceiptText.isNotEmpty,
        onRun: () => runPaletteAction(() {
          copySwapText(
            context,
            text: activeReceiptText,
            toastMessage: 'Receipt Copied',
          );
        }),
      ),
      _SwapCommandItem(
        id: 'copy_deposit',
        title: 'Copy Deposit Address',
        detail: activeDepositAddress ?? 'No active deposit address',
        iconName: AppIcons.copy,
        enabled:
            activeDepositAddress != null && activeDepositAddress.isNotEmpty,
        onRun: () => runPaletteAction(() {
          copySwapText(
            context,
            text: activeDepositAddress!,
            toastMessage: 'Address Copied',
          );
        }),
      ),
      _SwapCommandItem(
        id: 'review_fresh_quote',
        title: 'Review Fresh Quote',
        detail: 'Reuse the selected swap route draft',
        iconName: AppIcons.renew,
        enabled: canReviewFreshQuote,
        onRun: () => runPaletteAction(reviewFreshQuote),
      ),
    ];

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
      if (event.logicalKey == LogicalKeyboardKey.keyK) {
        _commandPaletteOpen ? _closeCommandPalette() : _openCommandPalette();
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
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AppRouteBackLink(minWidth: 60),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewportHeight = constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : null;
                          final primary = _SwapComposerStack(
                            viewportHeight: viewportHeight,
                            state: swapState,
                            onAmountChanged: swapNotifier.updateAmount,
                            onAmountFiatChanged: swapNotifier.updateAmountFiat,
                            onReceiveAmountChanged:
                                swapNotifier.updateReceiveAmount,
                            onReceiveAmountFiatChanged:
                                swapNotifier.updateReceiveAmountFiat,
                            onToggleFiatInputMode:
                                swapNotifier.toggleFiatInputMode,
                            onDirectionChanged: swapNotifier.selectDirection,
                            onToggleDirection: swapNotifier.toggleDirection,
                            onOpenExternalAssetPicker: _openAssetSelector,
                            onOpenDestinationAddress: _openAddressEditor,
                            assetSelectorOpen:
                                _swapModal == _SwapModalSurface.assetSelector,
                            onOpenSlippageSettings: _openSlippageSettings,
                            slippageSettingsOpen:
                                _swapModal ==
                                _SwapModalSurface.slippageSettings,
                            onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                            onReviewQuote: openReview,
                            zecAvailableText: zecAvailableText,
                            zecAvailableZatoshi: sync.spendableBalance,
                          );

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  child: _SwapViewportFrame(
                                    minHeight: viewportHeight,
                                    alignment: Alignment.center,
                                    child: primary,
                                  ),
                                ),
                              ),
                              if ((viewportHeight ?? 0) >= 520)
                                const Positioned(
                                  left: 0,
                                  bottom: 0.48,
                                  child: SwapNearIntentsAttribution(),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_commandPaletteOpen)
                AppPaneModalOverlay(
                  onDismiss: _closeCommandPalette,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _SwapCommandPalette(commands: commandItems),
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
                        onSubmitted: (value, remember) {
                          if (remember) {
                            unawaited(_rememberSwapAddress(value, swapState));
                          }
                          swapNotifier.updateDestination(value);
                          _closeSwapModal();
                        },
                        onScan: _openAddressScanner,
                        onOpenContacts: _openAddressContactPicker,
                        onCancel: _closeSwapModal,
                      ),
                      _SwapModalSurface.addressScanner =>
                        SwapAddressQrScanModal(
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

class _SwapViewportFrame extends StatelessWidget {
  const _SwapViewportFrame({
    required this.minHeight,
    required this.alignment,
    required this.child,
  });

  final double? minHeight;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Align(alignment: alignment, child: child);
    final height = minHeight;
    if (height == null) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: content,
    );
  }
}

class _SwapCommandItem {
  const _SwapCommandItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.iconName,
    required this.onRun,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String detail;
  final String iconName;
  final VoidCallback onRun;
  final bool enabled;
}

class _SwapCommandPalette extends StatefulWidget {
  const _SwapCommandPalette({required this.commands});

  final List<_SwapCommandItem> commands;

  @override
  State<_SwapCommandPalette> createState() => _SwapCommandPaletteState();
}

class _SwapCommandPaletteState extends State<_SwapCommandPalette> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  var _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode(debugLabel: 'SwapCommandPaletteQuery');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queryFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  List<_SwapCommandItem> get _filteredCommands {
    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.commands;
    return [
      for (final command in widget.commands)
        if (command.title.toLowerCase().contains(query) ||
            command.detail.toLowerCase().contains(query))
          command,
    ];
  }

  void _selectRelative(int delta) {
    final commands = _filteredCommands;
    if (commands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % commands.length;
      if (_selectedIndex < 0) _selectedIndex += commands.length;
    });
  }

  void _runSelected() {
    final commands = _filteredCommands;
    if (commands.isEmpty) return;
    final command = commands[_clampedSelectedIndex(commands)];
    if (!command.enabled) return;
    command.onRun();
  }

  int _clampedSelectedIndex(List<_SwapCommandItem> commands) {
    if (commands.isEmpty) return 0;
    return _selectedIndex.clamp(0, commands.length - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final commands = _filteredCommands;
    final selectedIndex = _clampedSelectedIndex(commands);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _selectRelative(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _selectRelative(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _runSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        key: const ValueKey('swap_command_palette'),
        width: 520,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.ground,
          border: Border.all(color: colors.border.regular),
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIcon(AppIcons.endpoint, size: 18, color: colors.icon.muted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Command palette',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  'Swap',
                  style: AppTypography.codeSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              key: const ValueKey('swap_command_palette_query'),
              label: 'Command',
              showLabel: false,
              hintText: 'Search command',
              controller: _queryController,
              focusNode: _queryFocusNode,
              leading: const AppIcon(AppIcons.link),
              onChanged: (_) {
                setState(() => _selectedIndex = 0);
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSelected(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: commands.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        'No matching commands',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: commands.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xxs),
                      itemBuilder: (context, index) {
                        final command = commands[index];
                        return _SwapCommandRow(
                          command: command,
                          selected: index == selectedIndex,
                          onTap: command.enabled ? command.onRun : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapCommandRow extends StatelessWidget {
  const _SwapCommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final _SwapCommandItem command;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = command.enabled;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: ValueKey('swap_command_${command.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.46,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: selected ? colors.state.selectedOpacity : null,
              border: Border.all(
                color: selected ? colors.border.regular : colors.border.subtle,
              ),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Row(
              children: [
                AppIcon(
                  command.iconName,
                  size: 18,
                  color: enabled ? colors.icon.regular : colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        command.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: enabled
                              ? colors.text.accent
                              : colors.text.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        command.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyExtraSmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  AppIcons.arrowForwardIos,
                  size: 12,
                  color: selected
                      ? colors.icon.brandCrimson
                      : colors.icon.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapComposerStack extends StatelessWidget {
  const _SwapComposerStack({
    required this.viewportHeight,
    required this.state,
    required this.onAmountChanged,
    required this.onAmountFiatChanged,
    required this.onReceiveAmountChanged,
    required this.onReceiveAmountFiatChanged,
    required this.onToggleFiatInputMode,
    required this.onDirectionChanged,
    required this.onToggleDirection,
    required this.onOpenExternalAssetPicker,
    required this.onOpenDestinationAddress,
    required this.assetSelectorOpen,
    required this.onOpenSlippageSettings,
    required this.slippageSettingsOpen,
    required this.onUseMaxZecAmount,
    required this.onReviewQuote,
    required this.zecAvailableText,
    required this.zecAvailableZatoshi,
  });

  final double? viewportHeight;
  final SwapPrototypeState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onAmountFiatChanged;
  final ValueChanged<String> onReceiveAmountChanged;
  final ValueChanged<String> onReceiveAmountFiatChanged;
  final ValueChanged<SwapAmountInputSide> onToggleFiatInputMode;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenExternalAssetPicker;
  final VoidCallback onOpenDestinationAddress;
  final bool assetSelectorOpen;
  final VoidCallback onOpenSlippageSettings;
  final bool slippageSettingsOpen;
  final VoidCallback onUseMaxZecAmount;
  final VoidCallback onReviewQuote;
  final String zecAvailableText;
  final BigInt zecAvailableZatoshi;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: _SwapComposerBody(
        bodyHeight: _swapBodyHeight,
        state: state,
        zecAvailableZatoshi: zecAvailableZatoshi,
        onOpenDestinationAddress: onOpenDestinationAddress,
        onReviewQuote: onReviewQuote,
        child: SwapComposerPanel(
          state: state,
          onAmountChanged: onAmountChanged,
          onAmountFiatChanged: onAmountFiatChanged,
          onReceiveAmountChanged: onReceiveAmountChanged,
          onReceiveAmountFiatChanged: onReceiveAmountFiatChanged,
          onToggleFiatInputMode: onToggleFiatInputMode,
          onDirectionChanged: onDirectionChanged,
          onToggleDirection: onToggleDirection,
          onOpenExternalAssetPicker: onOpenExternalAssetPicker,
          onOpenDestinationAddress: onOpenDestinationAddress,
          assetSelectorOpen: assetSelectorOpen,
          onOpenSlippageSettings: onOpenSlippageSettings,
          slippageSettingsOpen: slippageSettingsOpen,
          onUseMaxZecAmount: onUseMaxZecAmount,
          zecAvailableText: zecAvailableText,
          zecAvailableZatoshi: zecAvailableZatoshi,
        ),
      ),
    );
  }

  double? get _swapBodyHeight {
    final height = viewportHeight;
    if (height == null || !height.isFinite) return null;
    if (height <= 0) return null;
    return height;
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
      style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
    );
  }
}

class _SwapComposerBody extends StatelessWidget {
  const _SwapComposerBody({
    required this.bodyHeight,
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onOpenDestinationAddress,
    required this.onReviewQuote,
    required this.child,
  });

  final double? bodyHeight;
  final SwapPrototypeState state;
  final BigInt zecAvailableZatoshi;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onReviewQuote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final footer = _SwapReviewFooter(
      state: state,
      zecAvailableZatoshi: zecAvailableZatoshi,
      onOpenDestinationAddress: onOpenDestinationAddress,
      onReviewQuote: onReviewQuote,
    );
    final height = bodyHeight;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SwapPageTitle(),
          const SizedBox(height: AppSpacing.md),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
    if (height == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [content, const SizedBox(height: 38), footer],
        ),
      );
    }

    final effectiveHeight = _effectiveSwapBodyHeight(height, state);
    return SizedBox(
      height: effectiveHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Column(
          children: [
            Expanded(child: content),
            const SizedBox(height: AppSpacing.sm),
            footer,
          ],
        ),
      ),
    );
  }
}

double _effectiveSwapBodyHeight(double height, SwapPrototypeState state) {
  final hasQuoteError =
      state.quoteError != null || state.previewQuoteError != null;
  final clampedHeight = height < _swapBodyDesignHeight
      ? height
      : _swapBodyDesignHeight;
  return hasQuoteError ? clampedHeight + 72 : clampedHeight;
}

class _SwapReviewFooter extends StatelessWidget {
  const _SwapReviewFooter({
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onOpenDestinationAddress,
    required this.onReviewQuote,
  });

  final SwapPrototypeState state;
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
    final canReview = state.canReviewQuote && !balanceExceeded;
    final onPressed = needsDestinationAddress
        ? onOpenDestinationAddress
        : canReview
        ? onReviewQuote
        : null;
    final label = needsDestinationAddress
        ? _destinationAddressActionLabel(state)
        : balanceExceeded
        ? 'Insufficient ZEC'
        : state.quoteLoading
        ? 'Getting quote'
        : 'Get a quote';

    return Center(
      child: SizedBox(
        width: 256,
        child: AppButton(
          key: const ValueKey('swap_review_button'),
          onPressed: onPressed,
          variant: needsDestinationAddress
              ? AppButtonVariant.secondary
              : AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: 256,
          child: SizedBox(
            width: 184,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _SwapReviewButtonLabel(
                label: label,
                loading: state.quoteLoading && !needsDestinationAddress,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapReviewButtonLabel extends StatelessWidget {
  const _SwapReviewButtonLabel({required this.label, required this.loading});

  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1),
        if (loading) ...[
          const SizedBox(width: 4),
          const AppIcon(AppIcons.loader),
        ],
      ],
    );
  }
}

String _destinationAddressActionLabel(SwapPrototypeState state) {
  return state.direction.sendsZec
      ? 'Add Recipient Address'
      : 'Add Refund Address';
}

bool _reviewAmountExceedsAvailableZec(
  SwapPrototypeState state,
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
