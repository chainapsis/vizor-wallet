import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../send/models/send_prefill_args.dart';
import '../models/swap_prototype_models.dart';
import '../providers/swap_prototype_provider.dart';
import '../widgets/redacted_receipt_drawer.dart';
import '../widgets/swap_deposit_qr_panel.dart';
import '../widgets/swap_composer_panel.dart';
import '../widgets/swap_queue_panel.dart';
import '../widgets/swap_review_modal.dart';

enum _SwapPageTab { swap, activity, requests }

enum SwapScreenInitialTab { swap, activity, requests }

extension _SwapPageTabLabel on _SwapPageTab {
  String get label => switch (this) {
    _SwapPageTab.swap => 'Swap',
    _SwapPageTab.activity => 'Activity',
    _SwapPageTab.requests => 'Requests',
  };
}

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key, this.initialTab = SwapScreenInitialTab.swap});

  final SwapScreenInitialTab initialTab;

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  late _SwapPageTab _selectedTab;
  late final ScrollController _scrollController;
  late final FocusNode _shortcutFocusNode;
  bool _commandPaletteOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = switch (widget.initialTab) {
      SwapScreenInitialTab.swap => _SwapPageTab.swap,
      SwapScreenInitialTab.activity => _SwapPageTab.activity,
      SwapScreenInitialTab.requests => _SwapPageTab.requests,
    };
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

  void _selectTab(_SwapPageTab tab) {
    setState(() => _selectedTab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _openCommandPalette() {
    setState(() => _commandPaletteOpen = true);
  }

  void _closeCommandPalette() {
    setState(() => _commandPaletteOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shortcutFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapPrototypeProvider);
    final swapNotifier = ref.read(swapPrototypeProvider.notifier);
    final liveFundsEnabled = ref.watch(swapLiveFundsEnabledProvider);
    final selectedIntent = swapState.selectedIntentOrNull;
    final reviewQuote = swapState.reviewQuote;
    final reviewAddressPlan = swapState.reviewAddressPlan;
    void startIntent() {
      unawaited(() async {
        final started = await swapNotifier.startIntent();
        if (!mounted || !started) return;
        _selectTab(_SwapPageTab.activity);
      }());
    }

    void refreshStatus() {
      unawaited(swapNotifier.refreshSelectedIntentStatus());
    }

    void submitDepositTransaction() {
      unawaited(swapNotifier.submitSelectedDepositTransaction());
    }

    void reviewFreshQuote() {
      swapNotifier.prepareRetryFromSelectedIntent();
      _selectTab(_SwapPageTab.swap);
    }

    void retryShield() {
      unawaited(swapNotifier.retryShieldSelectedIntent());
    }

    void stageExternalRequest() {
      final staged = swapNotifier.stageSelectedExternalRequest();
      if (staged) _selectTab(_SwapPageTab.swap);
    }

    void openPaymentRequest() {
      final request = swapState.selectedRequestOrNull;
      if (request == null) return;
      final address = request.paymentAddress;
      if (!request.canOpenPayment || address == null) return;
      context.go(
        '/send',
        extra: SendPrefillArgs(
          id: request.id,
          source: request.source,
          address: address,
          amountText: request.paymentAmountText,
          memoText: request.paymentMemoText,
          label: request.paymentLabel,
          message: request.paymentMessage,
        ),
      );
    }

    void importRequestFromClipboard() {
      unawaited(() async {
        final data = await Clipboard.getData('text/plain');
        final text = data?.text?.trim() ?? '';
        if (text.isEmpty) return;
        swapNotifier.updateRequestImportText(text);
        swapNotifier.importExternalRequest();
        if (!mounted) return;
        _selectTab(_SwapPageTab.requests);
      }());
    }

    void runPaletteAction(VoidCallback action) {
      _closeCommandPalette();
      action();
    }

    final activeReceiptText = selectedIntent == null
        ? ''
        : redactedReceiptText(selectedIntent.receipt);
    final activeDepositAddress = selectedIntent?.depositAddress;
    final selectedRequest = swapState.selectedRequestOrNull;
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
        onRun: () => runPaletteAction(() => _selectTab(_SwapPageTab.swap)),
      ),
      _SwapCommandItem(
        id: 'open_activity',
        title: 'Open Activity',
        detail: 'Status, receipt, and recovery',
        iconName: AppIcons.history,
        onRun: () => runPaletteAction(() => _selectTab(_SwapPageTab.activity)),
      ),
      _SwapCommandItem(
        id: 'open_requests',
        title: 'Open Requests',
        detail: 'ZIP-321 and external handoffs',
        iconName: AppIcons.link,
        onRun: () => runPaletteAction(() => _selectTab(_SwapPageTab.requests)),
      ),
      _SwapCommandItem(
        id: 'import_clipboard_request',
        title: 'Import Clipboard Request',
        detail: 'Parse ZIP-321 into Requests',
        iconName: AppIcons.importWallet,
        onRun: () => runPaletteAction(importRequestFromClipboard),
      ),
      _SwapCommandItem(
        id: 'refresh_status',
        title: 'Refresh Status',
        detail: selectedIntent?.statusLabel ?? 'No active swap',
        iconName: AppIcons.renew,
        enabled: selectedIntent != null && !swapState.statusRefreshing,
        onRun: () => runPaletteAction(() {
          _selectTab(_SwapPageTab.activity);
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
          unawaited(Clipboard.setData(ClipboardData(text: activeReceiptText)));
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
          unawaited(
            Clipboard.setData(ClipboardData(text: activeDepositAddress!)),
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
      _SwapCommandItem(
        id: 'open_payment_send',
        title: 'Open Payment In Send',
        detail: selectedRequest?.title ?? 'No request selected',
        iconName: AppIcons.plane,
        enabled: selectedRequest?.canOpenPayment ?? false,
        onRun: () => runPaletteAction(openPaymentRequest),
      ),
    ];

    KeyEventResult handleShortcut(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final keyboard = HardwareKeyboard.instance;
      final commandPressed =
          keyboard.isMetaPressed || keyboard.isControlPressed;
      if (!commandPressed) return KeyEventResult.ignored;

      if (event.logicalKey == LogicalKeyboardKey.digit1) {
        _selectTab(_SwapPageTab.swap);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.digit2) {
        _selectTab(_SwapPageTab.activity);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.digit3) {
        _selectTab(_SwapPageTab.requests);
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
      child: Stack(
        children: [
          AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useWideLayout = constraints.maxWidth >= 1040;
                  final viewportHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : null;
                  final primary = _SwapComposerStack(
                    selectedTab: _selectedTab == _SwapPageTab.activity
                        ? _SwapPageTab.activity
                        : _SwapPageTab.swap,
                    viewportHeight: viewportHeight,
                    state: swapState,
                    openCount: swapState.openIntentCount,
                    onTabChanged: _selectTab,
                    onAmountChanged: swapNotifier.updateAmount,
                    onDestinationChanged: swapNotifier.updateDestination,
                    onDirectionChanged: swapNotifier.selectDirection,
                    onToggleDirection: swapNotifier.toggleDirection,
                    onExternalAssetChanged: swapNotifier.selectExternalAsset,
                    onSlippageChanged: swapNotifier.updateSlippageBps,
                    onReviewQuote: swapNotifier.showReview,
                    onRefreshStatus: refreshStatus,
                    onDepositTxHashChanged: swapNotifier.updateDepositTxHash,
                    onSubmitDepositTransaction: submitDepositTransaction,
                    onReviewFreshQuote: reviewFreshQuote,
                    onRetryShield: retryShield,
                    onIntentSelected: swapNotifier.selectIntent,
                    liveFundsEnabled: liveFundsEnabled,
                  );

                  final requests = useWideLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _SwapRequestInboxStack(
                                state: swapState,
                                onImportTextChanged:
                                    swapNotifier.updateRequestImportText,
                                onImportRequest:
                                    swapNotifier.importExternalRequest,
                                onPasteRequest: importRequestFromClipboard,
                                onStageRequest: stageExternalRequest,
                                onOpenPayment: openPaymentRequest,
                                onRejectRequest:
                                    swapNotifier.rejectSelectedExternalRequest,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            SizedBox(
                              width: 340,
                              child: _SwapRequestListPanel(
                                requests: swapState.externalRequests,
                                selectedRequestId:
                                    swapState.selectedRequestOrNull?.id,
                                onRequestSelected:
                                    swapNotifier.selectExternalRequest,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SwapRequestInboxStack(
                              state: swapState,
                              onImportTextChanged:
                                  swapNotifier.updateRequestImportText,
                              onImportRequest:
                                  swapNotifier.importExternalRequest,
                              onPasteRequest: importRequestFromClipboard,
                              onStageRequest: stageExternalRequest,
                              onOpenPayment: openPaymentRequest,
                              onRejectRequest:
                                  swapNotifier.rejectSelectedExternalRequest,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _SwapRequestListPanel(
                              requests: swapState.externalRequests,
                              selectedRequestId:
                                  swapState.selectedRequestOrNull?.id,
                              onRequestSelected:
                                  swapNotifier.selectExternalRequest,
                            ),
                          ],
                        );

                  return SingleChildScrollView(
                    controller: _scrollController,
                    child: switch (_selectedTab) {
                      _SwapPageTab.swap => _SwapViewportFrame(
                        minHeight: viewportHeight,
                        alignment: Alignment.center,
                        child: primary,
                      ),
                      _SwapPageTab.activity => _SwapViewportFrame(
                        minHeight: viewportHeight,
                        alignment: Alignment.topCenter,
                        child: primary,
                      ),
                      _SwapPageTab.requests => requests,
                    },
                  );
                },
              ),
            ),
          ),
          if (swapState.reviewVisible &&
              reviewQuote != null &&
              reviewAddressPlan != null)
            AppPaneModalOverlay(
              onDismiss: swapNotifier.cancelReviewQuote,
              child: Material(
                type: MaterialType.transparency,
                child: _SwapReviewModalEntrance(
                  child: SwapReviewModal(
                    quote: reviewQuote,
                    addressPlan: reviewAddressPlan,
                    expired: swapState.quoteExpired,
                    amountWarning: swapState.reviewAmountDifferenceWarning,
                    startError: swapState.statusError,
                    onReviewAgain: swapNotifier.showReview,
                    onCancelReview: swapNotifier.cancelReviewQuote,
                    onStartIntent: startIntent,
                  ),
                ),
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
        ],
      ),
    );
  }
}

class _SwapReviewModalEntrance extends StatelessWidget {
  const _SwapReviewModalEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('swap_review_modal_entrance'),
      tween: Tween<double>(begin: -28, end: 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, dx, child) {
        final opacity = 1 - (dx.abs() / 28);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
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

class _SwapPageTabs extends StatelessWidget {
  const _SwapPageTabs({
    required this.selected,
    required this.openCount,
    required this.onChanged,
  });

  final _SwapPageTab selected;
  final int openCount;
  final ValueChanged<_SwapPageTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const tabs = [_SwapPageTab.swap, _SwapPageTab.activity];
    return Container(
      key: const ValueKey('swap_ticket_tabs'),
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          for (final tab in tabs) ...[
            Expanded(
              child: _SwapPageTabButton(
                tab: tab,
                selected: selected == tab,
                badgeCount: tab == _SwapPageTab.activity ? openCount : 0,
                onTap: () => onChanged(tab),
              ),
            ),
            if (tab != tabs.last) const SizedBox(width: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _SwapRequestInboxStack extends StatelessWidget {
  const _SwapRequestInboxStack({
    required this.state,
    required this.onImportTextChanged,
    required this.onImportRequest,
    required this.onPasteRequest,
    required this.onStageRequest,
    required this.onOpenPayment,
    required this.onRejectRequest,
  });

  final SwapPrototypeState state;
  final ValueChanged<String> onImportTextChanged;
  final VoidCallback onImportRequest;
  final VoidCallback onPasteRequest;
  final VoidCallback onStageRequest;
  final VoidCallback onOpenPayment;
  final VoidCallback onRejectRequest;

  @override
  Widget build(BuildContext context) {
    final request = state.selectedRequestOrNull;
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_request_inbox_panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request inbox',
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request?.title ?? 'No request selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (request != null)
                _ExternalRequestStatusBadge(status: request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _RequestImportPanel(
            text: state.requestImportText,
            error: state.requestImportError,
            onChanged: onImportTextChanged,
            onImport: onImportRequest,
            onPaste: onPasteRequest,
          ),
          if (request == null) ...[
            const SizedBox(height: AppSpacing.sm),
            const _RequestEmptyState(),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _RequestMetric(label: 'Source', value: request.source),
                _RequestMetric(label: 'Route', value: request.route),
                _RequestMetric(label: 'Received', value: request.receivedAt),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _RequestActionPlanPanel(request: request),
            const SizedBox(height: AppSpacing.xs),
            _RequestRiskPanel(request: request),
            const SizedBox(height: AppSpacing.xs),
            _RequestFieldList(rows: request.disclosures),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    key: const ValueKey('swap_request_primary_button'),
                    onPressed: request.canStageSwap
                        ? onStageRequest
                        : request.canOpenPayment
                        ? onOpenPayment
                        : null,
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.medium,
                    leading: const AppIcon(AppIcons.arrowForwardIos),
                    child: Text(_requestPrimaryActionLabel(request)),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  key: const ValueKey('swap_request_reject_button'),
                  onPressed: request.isOpen ? onRejectRequest : null,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  leading: const AppIcon(AppIcons.block),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestEmptyState extends StatelessWidget {
  const _RequestEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_request_empty_state'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        'Paste a ZIP-321 payment request to review it here.',
        style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
      ),
    );
  }
}

class _RequestImportPanel extends StatefulWidget {
  const _RequestImportPanel({
    required this.text,
    required this.error,
    required this.onChanged,
    required this.onImport,
    required this.onPaste,
  });

  final String text;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onImport;
  final VoidCallback onPaste;

  @override
  State<_RequestImportPanel> createState() => _RequestImportPanelState();
}

class _RequestImportPanelState extends State<_RequestImportPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant _RequestImportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            key: const ValueKey('swap_request_import_field'),
            label: 'Import request',
            hintText: 'Paste zcash: payment URI',
            controller: _controller,
            onChanged: widget.onChanged,
            showClearButton: true,
            onClear: () => widget.onChanged(''),
            minLines: 1,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => widget.onImport(),
            tone: widget.error == null
                ? AppTextFieldTone.neutral
                : AppTextFieldTone.destructive,
            messageText: widget.error,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            children: [
              AppButton(
                key: const ValueKey('swap_request_paste_button'),
                onPressed: widget.onPaste,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                leading: const AppIcon(AppIcons.copy),
                child: const Text('Paste'),
              ),
              const SizedBox(height: AppSpacing.xxs),
              AppButton(
                key: const ValueKey('swap_request_import_button'),
                onPressed: widget.text.trim().isEmpty ? null : widget.onImport,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                leading: const AppIcon(AppIcons.importWallet),
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwapRequestListPanel extends StatelessWidget {
  const _SwapRequestListPanel({
    required this.requests,
    required this.selectedRequestId,
    required this.onRequestSelected,
  });

  final List<SwapExternalRequest> requests;
  final String? selectedRequestId;
  final ValueChanged<String> onRequestSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_request_list_panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'External requests',
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (requests.isEmpty)
            Text(
              'No saved requests',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          for (final request in requests) ...[
            _ExternalRequestRow(
              request: request,
              selected: request.id == selectedRequestId,
              onTap: () => onRequestSelected(request.id),
            ),
            if (request != requests.last)
              const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _ExternalRequestRow extends StatelessWidget {
  const _ExternalRequestRow({
    required this.request,
    required this.selected,
    required this.onTap,
  });

  final SwapExternalRequest request;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_request_row_${request.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.base,
            border: Border.all(
              color: selected
                  ? colors.border.brandCrimsonStrong
                  : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: selected
                            ? colors.text.accent
                            : colors.text.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  _ExternalRequestStatusBadge(status: request.status),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${request.source} / ${request.route}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                request.requestedAction,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalRequestStatusBadge extends StatelessWidget {
  const _ExternalRequestStatusBadge({required this.status});

  final SwapExternalRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = switch (status) {
      SwapExternalRequestStatus.needsReview => colors.text.warning,
      SwapExternalRequestStatus.accepted => colors.text.success,
      SwapExternalRequestStatus.rejected ||
      SwapExternalRequestStatus.unsupported => colors.text.destructive,
    };
    return Container(
      key: const ValueKey('swap_request_status_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        border: Border.all(color: statusColor.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(color: statusColor),
      ),
    );
  }
}

class _SwapActivityEmptyState extends StatelessWidget {
  const _SwapActivityEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_empty_state'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.history, size: 20, color: colors.icon.brandCrimson),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No swap activity yet',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Review a live quote to create an activity record with deposit, delivery, and recovery details.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _requestPrimaryActionLabel(SwapExternalRequest request) {
  if (request.canStageSwap) {
    return request.direction == SwapDirection.externalToZec
        ? 'Stage receive'
        : 'Stage swap';
  }
  if (request.canOpenPayment) return 'Open send';
  return 'Unsupported';
}

enum _RequestActionPlanTone { swap, payment, blocked }

class _RequestActionPlan {
  const _RequestActionPlan({
    required this.title,
    required this.detail,
    required this.leadLabel,
    required this.receiveLabel,
    required this.returnLabel,
    required this.iconName,
    required this.tone,
  });

  factory _RequestActionPlan.fromRequest(SwapExternalRequest request) {
    if (request.canStageSwap) {
      final direction = request.direction!;
      final externalAsset = request.externalAsset!;
      final amountText = request.amountText ?? '';
      if (direction == SwapDirection.externalToZec) {
        return _RequestActionPlan(
          title: 'Receive ZEC request',
          detail:
              'Stage the quote, then send ${externalAsset.symbol} to a one-time source-chain address. ZEC lands on the wallet t-address, then prompts shielding.',
          leadLabel: 'Pay $amountText ${externalAsset.symbol}',
          receiveLabel: 'Receive ZEC to wallet t-address',
          returnLabel: 'Refund ${request.destinationText ?? 'source address'}',
          iconName: AppIcons.shieldKeyhole,
          tone: _RequestActionPlanTone.swap,
        );
      }

      return _RequestActionPlan(
        title: 'Send ZEC request',
        detail:
            'Stage the quote, then send ZEC from this wallet to a one-time transparent deposit address.',
        leadLabel: 'Pay $amountText ZEC',
        receiveLabel: 'Deliver ${externalAsset.symbol}',
        returnLabel: 'Refund to wallet source',
        iconName: AppIcons.zcashCurrency,
        tone: _RequestActionPlanTone.swap,
      );
    }

    if (request.canOpenPayment) {
      return const _RequestActionPlan(
        title: 'ZEC payment handoff',
        detail:
            'Open Send with the parsed address, amount, and memo. No swap route or swap session is created.',
        leadLabel: 'Pay ZEC',
        receiveLabel: 'Shielded recipient',
        returnLabel: 'No swap route',
        iconName: AppIcons.plane,
        tone: _RequestActionPlanTone.payment,
      );
    }

    return const _RequestActionPlan(
      title: 'Connector blocked',
      detail:
          'No wallet session is opened. Import explicit payment or swap requests instead.',
      leadLabel: 'No account reveal',
      receiveLabel: 'No background session',
      returnLabel: 'Manual import only',
      iconName: AppIcons.block,
      tone: _RequestActionPlanTone.blocked,
    );
  }

  final String title;
  final String detail;
  final String leadLabel;
  final String receiveLabel;
  final String returnLabel;
  final String iconName;
  final _RequestActionPlanTone tone;
}

class _RequestActionPlanPanel extends StatelessWidget {
  const _RequestActionPlanPanel({required this.request});

  final SwapExternalRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plan = _RequestActionPlan.fromRequest(request);
    final toneColor = switch (plan.tone) {
      _RequestActionPlanTone.swap => colors.text.warning,
      _RequestActionPlanTone.payment => colors.text.success,
      _RequestActionPlanTone.blocked => colors.text.destructive,
    };
    final iconColor = switch (plan.tone) {
      _RequestActionPlanTone.swap => colors.icon.warning,
      _RequestActionPlanTone.payment => colors.icon.success,
      _RequestActionPlanTone.blocked => colors.icon.destructive,
    };
    return Container(
      key: const ValueKey('swap_request_action_plan'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.08),
        border: Border.all(color: toneColor.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(plan.iconName, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: AppTypography.labelLarge.copyWith(color: toneColor),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  plan.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    _RequestActionChip(label: plan.leadLabel),
                    _RequestActionChip(label: plan.receiveLabel),
                    _RequestActionChip(label: plan.returnLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestActionChip extends StatelessWidget {
  const _RequestActionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: colors.text.primary),
      ),
    );
  }
}

class _RequestRiskPanel extends StatelessWidget {
  const _RequestRiskPanel({required this.request});

  final SwapExternalRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final toneColor = switch (request.status) {
      SwapExternalRequestStatus.rejected ||
      SwapExternalRequestStatus.unsupported => colors.text.destructive,
      _ => colors.text.warning,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.08),
        border: Border.all(color: toneColor.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 18, color: toneColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.riskLabel,
                  style: AppTypography.labelLarge.copyWith(color: toneColor),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  request.riskDetail,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestFieldList extends StatelessWidget {
  const _RequestFieldList({required this.rows});

  final List<SwapPrototypeField> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      row.label,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestMetric extends StatelessWidget {
  const _RequestMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
  }
}

class _SwapActivityStack extends StatelessWidget {
  const _SwapActivityStack({
    required this.state,
    required this.selectedIntent,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onRetryShield,
    required this.liveFundsEnabled,
  });

  final SwapPrototypeState state;
  final SwapPrototypeIntent selectedIntent;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final VoidCallback onRetryShield;
  final bool liveFundsEnabled;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = _ActivityDepositInstruction.fromIntent(
      selectedIntent,
    );
    final statusPlan = _ActivityStatusPlan.fromIntent(selectedIntent);
    final resolution = _ActivityResolution.fromIntent(selectedIntent);
    final showDepositControls = _showDepositControls(selectedIntent.status);
    final showSupportDetails = _showActivityReceipt(selectedIntent.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActiveSwapSummaryPanel(
          intent: selectedIntent,
          plan: statusPlan,
          statusRefreshing: state.statusRefreshing,
          onRefreshStatus: onRefreshStatus,
        ),
        if (state.statusError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _ActivityStatusErrorPanel(message: state.statusError!),
        ],
        const SizedBox(height: AppSpacing.xs),
        if (resolution != null) ...[
          _ActivityResolutionPanel(
            resolution: resolution,
            intent: selectedIntent,
            onReviewFreshQuote: onReviewFreshQuote,
            onRetryShield: onRetryShield,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showDepositControls && depositInstruction != null) ...[
          _ActivityDepositActionPanel(
            state: state,
            instruction: depositInstruction,
            onDepositTxHashChanged: onDepositTxHashChanged,
            onSubmitDepositTransaction: onSubmitDepositTransaction,
            liveFundsEnabled: liveFundsEnabled,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showSupportDetails) ...[
          _ActivitySupportDetailsSection(intent: selectedIntent),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ActivityStatusErrorPanel extends StatelessWidget {
  const _ActivityStatusErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.text.destructive.withValues(alpha: 0.08),
        border: Border.all(
          color: colors.text.destructive.withValues(alpha: 0.26),
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 16, color: colors.icon.destructive),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStatusPlan {
  const _ActivityStatusPlan({
    required this.title,
    required this.detail,
    required this.iconName,
    required this.tone,
  });

  static _ActivityStatusPlan fromIntent(SwapPrototypeIntent intent) {
    final sourceSymbol = _pairSymbol(intent.pair, 0);

    return switch (intent.status) {
      SwapIntentStatus.awaitingDeposit => _ActivityStatusPlan(
        title: 'Send $sourceSymbol deposit',
        detail: 'Use the one-time address, then submit the tx hash.',
        iconName: AppIcons.link,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.awaitingExternalDeposit => _ActivityStatusPlan(
        title: 'Send $sourceSymbol deposit',
        detail: 'Use the source-chain address, then submit the tx hash.',
        iconName: AppIcons.link,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.depositObserved => const _ActivityStatusPlan(
        title: 'Deposit received',
        detail: 'Refresh until settlement advances.',
        iconName: AppIcons.eye,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.processing => const _ActivityStatusPlan(
        title: 'Swap is processing',
        detail: 'No new approval is needed.',
        iconName: AppIcons.renew,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.incompleteDeposit => _ActivityStatusPlan(
        title: 'Top up deposit',
        detail: 'Send only the missing amount or wait for refund.',
        iconName: AppIcons.warning,
        tone: _ActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.shieldingPending => const _ActivityStatusPlan(
        title: 'Shield ZEC in wallet',
        detail: 'Close the transparent wallet balance.',
        iconName: AppIcons.shieldKeyhole,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.shieldingConfirming => const _ActivityStatusPlan(
        title: 'Shielding is confirming',
        detail: 'Wait for the shield transaction to confirm.',
        iconName: AppIcons.shieldKeyhole,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.shieldingFailed => const _ActivityStatusPlan(
        title: 'Retry wallet shielding',
        detail: 'Do not resend external funds.',
        iconName: AppIcons.warning,
        tone: _ActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.complete => const _ActivityStatusPlan(
        title: 'Swap complete',
        detail: 'Receipt is available for records.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.refunded => const _ActivityStatusPlan(
        title: 'Refund sent',
        detail: 'Verify the refund before retrying.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.expired => const _ActivityStatusPlan(
        title: 'Deposit window closed',
        detail: 'No funds moved if no deposit was sent.',
        iconName: AppIcons.block,
        tone: _ActivityStatusPlanTone.destructive,
      ),
      SwapIntentStatus.failed => const _ActivityStatusPlan(
        title: 'Do not reuse this quote',
        detail: 'Start a fresh quote when ready.',
        iconName: AppIcons.block,
        tone: _ActivityStatusPlanTone.destructive,
      ),
    };
  }

  static String _pairSymbol(String pair, int index) {
    final parts = pair.split(' -> ');
    if (parts.length > index && parts[index].trim().isNotEmpty) {
      return parts[index].trim();
    }
    return index == 0 ? 'deposit asset' : 'receive asset';
  }

  final String title;
  final String detail;
  final String iconName;
  final _ActivityStatusPlanTone tone;
}

enum _ActivityStatusPlanTone { action, warning, success, destructive }

class _ActivityStatusPlanPanel extends StatelessWidget {
  const _ActivityStatusPlanPanel({required this.intent, required this.plan});

  final SwapPrototypeIntent intent;
  final _ActivityStatusPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (plan.tone) {
      _ActivityStatusPlanTone.action ||
      _ActivityStatusPlanTone.warning => colors.text.warning,
      _ActivityStatusPlanTone.success => colors.text.success,
      _ActivityStatusPlanTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (plan.tone) {
      _ActivityStatusPlanTone.action ||
      _ActivityStatusPlanTone.warning => colors.icon.warning,
      _ActivityStatusPlanTone.success => colors.icon.success,
      _ActivityStatusPlanTone.destructive => colors.icon.destructive,
    };
    return Column(
      key: const ValueKey('swap_activity_status_plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                border: Border.all(color: color.withValues(alpha: 0.22)),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: AppIcon(plan.iconName, size: 18, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headlineSmall.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    intent.nextAction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyExtraSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _ActivityMilestoneRail(status: intent.status, tone: plan.tone),
      ],
    );
  }
}

class _ActivityMilestoneRail extends StatelessWidget {
  const _ActivityMilestoneRail({required this.status, required this.tone});

  final SwapIntentStatus status;
  final _ActivityStatusPlanTone tone;

  @override
  Widget build(BuildContext context) {
    final states = _statesFor(status);
    return Row(
      children: [
        for (var index = 0; index < states.length; index++) ...[
          Expanded(
            child: _ActivityMilestone(
              label: const ['Deposit', 'Swap', 'Receive'][index],
              state: states[index],
              tone: tone,
            ),
          ),
          if (index != states.length - 1) const SizedBox(width: AppSpacing.xxs),
        ],
      ],
    );
  }

  List<_ActivityMilestoneState> _statesFor(SwapIntentStatus status) {
    return switch (status) {
      SwapIntentStatus.awaitingDeposit ||
      SwapIntentStatus.awaitingExternalDeposit => const [
        _ActivityMilestoneState.active,
        _ActivityMilestoneState.pending,
        _ActivityMilestoneState.pending,
      ],
      SwapIntentStatus.depositObserved || SwapIntentStatus.processing => const [
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.active,
        _ActivityMilestoneState.pending,
      ],
      SwapIntentStatus.incompleteDeposit => const [
        _ActivityMilestoneState.warning,
        _ActivityMilestoneState.pending,
        _ActivityMilestoneState.pending,
      ],
      SwapIntentStatus.shieldingPending ||
      SwapIntentStatus.shieldingConfirming => const [
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.active,
      ],
      SwapIntentStatus.shieldingFailed => const [
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.warning,
      ],
      SwapIntentStatus.complete || SwapIntentStatus.refunded => const [
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.done,
        _ActivityMilestoneState.done,
      ],
      SwapIntentStatus.expired || SwapIntentStatus.failed => const [
        _ActivityMilestoneState.failed,
        _ActivityMilestoneState.pending,
        _ActivityMilestoneState.pending,
      ],
    };
  }
}

enum _ActivityMilestoneState { pending, active, done, warning, failed }

class _ActivityMilestone extends StatelessWidget {
  const _ActivityMilestone({
    required this.label,
    required this.state,
    required this.tone,
  });

  final String label;
  final _ActivityMilestoneState state;
  final _ActivityStatusPlanTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (state) {
      _ActivityMilestoneState.done => colors.text.success,
      _ActivityMilestoneState.failed => colors.text.destructive,
      _ActivityMilestoneState.warning => colors.text.warning,
      _ActivityMilestoneState.active => switch (tone) {
        _ActivityStatusPlanTone.success => colors.text.success,
        _ActivityStatusPlanTone.destructive => colors.text.destructive,
        _ => colors.text.warning,
      },
      _ActivityMilestoneState.pending => colors.text.secondary,
    };
    final iconName = switch (state) {
      _ActivityMilestoneState.done => AppIcons.checkCircle,
      _ActivityMilestoneState.failed => AppIcons.block,
      _ActivityMilestoneState.warning => AppIcons.warning,
      _ActivityMilestoneState.active => AppIcons.renew,
      _ActivityMilestoneState.pending => AppIcons.time,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: state == _ActivityMilestoneState.pending
            ? colors.background.base
            : color.withValues(alpha: 0.08),
        border: Border.all(
          color: state == _ActivityMilestoneState.pending
              ? colors.border.subtle
              : color.withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(iconName, size: 13, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityResolution {
  const _ActivityResolution({
    required this.title,
    required this.message,
    required this.detail,
    required this.iconName,
    required this.tone,
    this.primaryAction,
  });

  static _ActivityResolution? fromIntent(SwapPrototypeIntent intent) {
    return switch (intent.status) {
      SwapIntentStatus.incompleteDeposit => _ActivityResolution(
        title: 'Resolve incomplete deposit',
        message: 'The deposit is below the quoted amount.',
        detail:
            'Send only the missing amount with the same one-time deposit details, or wait for the refund path.',
        iconName: AppIcons.warning,
        tone: _ActivityResolutionTone.warning,
        primaryAction: _ActivityResolutionAction.copyTopUpDetails,
      ),
      SwapIntentStatus.refunded => _ActivityResolution(
        title: 'Refund complete',
        message: 'The swap is closed and the refund has been submitted.',
        detail:
            'Check the origin-chain refund transaction before starting a fresh quote.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityResolutionTone.success,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.failed => _ActivityResolution(
        title: 'Route failed',
        message: 'The swap could not complete this route.',
        detail:
            'No funds moved according to status. Review the receipt, then start a new quote.',
        iconName: AppIcons.block,
        tone: _ActivityResolutionTone.destructive,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.expired => _ActivityResolution(
        title: 'Deposit window closed',
        message: 'The deposit window for this quote has closed.',
        detail:
            'If you did not send funds, no action is needed. If you sent funds near expiry, refresh once and keep this deposit address for support.',
        iconName: AppIcons.block,
        tone: _ActivityResolutionTone.destructive,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.shieldingFailed => _ActivityResolution(
        title: 'Shielding failed',
        message:
            'ZEC arrived at the staging address, but wallet shielding did not complete.',
        detail:
            'Do not send the external deposit again. Retry shielding from the staging address or keep this recovery record open.',
        iconName: AppIcons.shieldKeyhole,
        tone: _ActivityResolutionTone.warning,
        primaryAction: _ActivityResolutionAction.retryShield,
      ),
      _ => null,
    };
  }

  final String title;
  final String message;
  final String detail;
  final String iconName;
  final _ActivityResolutionTone tone;
  final _ActivityResolutionAction? primaryAction;
}

enum _ActivityResolutionTone { warning, success, destructive }

enum _ActivityResolutionAction {
  copyTopUpDetails,
  reviewFreshQuote,
  retryShield,
}

class _ActivityResolutionPanel extends StatelessWidget {
  const _ActivityResolutionPanel({
    required this.resolution,
    required this.intent,
    required this.onReviewFreshQuote,
    required this.onRetryShield,
  });

  final _ActivityResolution resolution;
  final SwapPrototypeIntent intent;
  final VoidCallback onReviewFreshQuote;
  final VoidCallback onRetryShield;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (resolution.tone) {
      _ActivityResolutionTone.warning => colors.text.warning,
      _ActivityResolutionTone.success => colors.text.success,
      _ActivityResolutionTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (resolution.tone) {
      _ActivityResolutionTone.warning => colors.icon.warning,
      _ActivityResolutionTone.success => colors.icon.success,
      _ActivityResolutionTone.destructive => colors.icon.destructive,
    };
    final action = resolution.primaryAction;
    final actionLabel = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => 'Copy top-up details',
      _ActivityResolutionAction.reviewFreshQuote => 'Review fresh quote',
      _ActivityResolutionAction.retryShield => 'Retry shield',
      null => null,
    };
    final actionIcon = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => AppIcons.copy,
      _ActivityResolutionAction.reviewFreshQuote => AppIcons.renew,
      _ActivityResolutionAction.retryShield => AppIcons.shieldKeyhole,
      null => null,
    };
    final actionKey = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => const ValueKey(
        'swap_resolution_copy_deposit_button',
      ),
      _ActivityResolutionAction.reviewFreshQuote => const ValueKey(
        'swap_resolution_review_again_button',
      ),
      _ActivityResolutionAction.retryShield => const ValueKey(
        'swap_resolution_retry_shield_button',
      ),
      null => null,
    };
    final depositAddress = intent.depositAddress;
    final shieldingRecoveryAddress =
        intent.status == SwapIntentStatus.shieldingFailed
        ? (intent.oneClickRecipient ?? depositAddress)
        : null;
    final actionEnabled =
        action == _ActivityResolutionAction.reviewFreshQuote ||
        action == _ActivityResolutionAction.retryShield ||
        (action == _ActivityResolutionAction.copyTopUpDetails &&
            depositAddress != null &&
            depositAddress.isNotEmpty);
    return Container(
      key: const ValueKey('swap_resolution_panel'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(resolution.iconName, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolution.title,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  resolution.message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  resolution.detail,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (shieldingRecoveryAddress != null &&
                    shieldingRecoveryAddress.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    shieldingRecoveryAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.codeSmall.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ],
                if (actionLabel != null && actionIcon != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: actionKey,
                      onPressed: actionEnabled
                          ? () {
                              if (action ==
                                      _ActivityResolutionAction
                                          .copyTopUpDetails &&
                                  depositAddress != null) {
                                unawaited(
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: _topUpDetailsText(intent),
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (action ==
                                  _ActivityResolutionAction.reviewFreshQuote) {
                                onReviewFreshQuote();
                              }
                              if (action ==
                                  _ActivityResolutionAction.retryShield) {
                                onRetryShield();
                              }
                            }
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: AppIcon(actionIcon),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _topUpDetailsText(SwapPrototypeIntent intent) {
    final lines = [
      if (intent.depositAddress != null)
        'Deposit address: ${intent.depositAddress}',
      if (intent.depositMemo != null) 'Deposit memo: ${intent.depositMemo}',
    ];
    return lines.join('\n');
  }
}

bool _showDepositControls(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.shieldingFailed ||
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => false,
    _ => true,
  };
}

bool _showActivityReceipt(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed ||
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.shieldingFailed => true,
    _ => false,
  };
}

class _ActiveSwapSummaryPanel extends StatelessWidget {
  const _ActiveSwapSummaryPanel({
    required this.intent,
    required this.plan,
    required this.statusRefreshing,
    required this.onRefreshStatus,
  });

  final SwapPrototypeIntent intent;
  final _ActivityStatusPlan plan;
  final bool statusRefreshing;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final statusActions = Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SwapStatusBadge(status: intent.status),
            _ActivityStageBadge(status: intent.status),
            AppButton(
              key: const ValueKey('swap_status_refresh_button'),
              onPressed: statusRefreshing ? null : onRefreshStatus,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              leading: const AppIcon(AppIcons.renew),
              child: Text(statusRefreshing ? 'Refreshing' : 'Refresh'),
            ),
          ],
        );

        return Container(
          key: const ValueKey('swap_active_summary_panel'),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.base,
            border: Border.all(color: colors.border.regular),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                statusActions,
                const SizedBox(height: AppSpacing.xs),
                _ActiveSwapTitle(intent: intent),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _ActiveSwapTitle(intent: intent)),
                    const SizedBox(width: AppSpacing.xs),
                    statusActions,
                  ],
                ),
              const SizedBox(height: AppSpacing.sm),
              _ActivityStatusPlanPanel(intent: intent, plan: plan),
              const SizedBox(height: AppSpacing.sm),
              _ActiveSwapTradeLine(intent: intent),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveSwapTitle extends StatelessWidget {
  const _ActiveSwapTitle({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current swap',
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          intent.pair,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          intent.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _SwapStatusBadge extends StatelessWidget {
  const _SwapStatusBadge({required this.status});

  final SwapIntentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = switch (status) {
      SwapIntentStatus.complete => colors.text.success,
      SwapIntentStatus.failed ||
      SwapIntentStatus.expired ||
      SwapIntentStatus.refunded => colors.text.destructive,
      _ => colors.text.warning,
    };
    return Container(
      key: const ValueKey('swap_active_summary_status_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        border: Border.all(color: statusColor.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(color: statusColor),
      ),
    );
  }
}

class _ActivityStageBadge extends StatelessWidget {
  const _ActivityStageBadge({required this.status});

  final SwapIntentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _activityStageLabel(status);
    final color = switch (status) {
      SwapIntentStatus.complete => colors.text.success,
      SwapIntentStatus.failed ||
      SwapIntentStatus.expired ||
      SwapIntentStatus.refunded => colors.text.destructive,
      SwapIntentStatus.incompleteDeposit ||
      SwapIntentStatus.shieldingFailed => colors.text.warning,
      _ => colors.text.accent,
    };
    return Container(
      key: const ValueKey('swap_activity_stage_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: color.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(color: color),
      ),
    );
  }
}

String _activityStageLabel(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => 'Step 1 of 3',
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing => 'Step 2 of 3',
    SwapIntentStatus.incompleteDeposit => 'Needs attention',
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.shieldingFailed ||
    SwapIntentStatus.complete => 'Step 3 of 3',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}

class _ActiveSwapTradeLine extends StatelessWidget {
  const _ActiveSwapTradeLine({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActiveTradeAmount(
              label: 'You send',
              value: intent.sellAmount,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: AppIcon(
              AppIcons.arrowForwardIos,
              size: 14,
              color: colors.icon.muted,
            ),
          ),
          Expanded(
            child: _ActiveTradeAmount(
              label: 'You receive',
              value: intent.receiveEstimate,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTradeAmount extends StatelessWidget {
  const _ActiveTradeAmount({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _ActivityDepositInstruction {
  const _ActivityDepositInstruction({
    required this.sendLabel,
    required this.depositSymbol,
    required this.depositAddressLabel,
    required this.address,
    required this.railLabel,
    required this.reuseWarning,
    required this.deliveryLabel,
    required this.deliveryValue,
    required this.txHashLabel,
    required this.txHashHint,
    required this.submitLabel,
    required this.showQr,
    this.memo,
  });

  static _ActivityDepositInstruction? fromIntent(SwapPrototypeIntent intent) {
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final receiveSymbol = direction.toSymbol(externalAsset);
    final deliveryLabel = direction.sendsZec
        ? '$receiveSymbol destination'
        : 'Receive address';
    final deliveryValue = direction.sendsZec
        ? intent.oneClickRecipient ?? 'external destination'
        : intent.oneClickRecipient ??
              'wallet receive address; shield prompt follows';
    final depositAddressLabel = direction.sendsZec
        ? '$depositSymbol deposit'
        : '$depositSymbol source deposit';

    return _ActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? 'Send $depositSymbol'
          : 'Send $depositSymbol from source chain',
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      railLabel: externalAsset.railLabel,
      reuseWarning: 'Do not reuse this address',
      memo: intent.depositMemo,
      deliveryLabel: deliveryLabel,
      deliveryValue: deliveryValue,
      txHashLabel: '$depositSymbol deposit tx hash',
      txHashHint: '$depositSymbol source-chain transaction hash',
      submitLabel: 'Submit $depositSymbol deposit',
      showQr: !direction.sendsZec,
    );
  }

  final String sendLabel;
  final String depositSymbol;
  final String depositAddressLabel;
  final String address;
  final String railLabel;
  final String reuseWarning;
  final String? memo;
  final String deliveryLabel;
  final String deliveryValue;
  final String txHashLabel;
  final String txHashHint;
  final String submitLabel;
  final bool showQr;
}

class _ActivityDepositActionPanel extends StatelessWidget {
  const _ActivityDepositActionPanel({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.liveFundsEnabled,
  });

  final SwapPrototypeState state;
  final _ActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final bool liveFundsEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (instruction.showQr) ...[
          SwapDepositQrPanel(
            key: const ValueKey('swap_activity_deposit_qr_panel'),
            title: 'Send ${instruction.depositSymbol} to this deposit address',
            qrData: instruction.address,
            addressLabel: instruction.depositAddressLabel,
            address: instruction.address,
            railLabel: instruction.railLabel,
            reuseWarning: instruction.reuseWarning,
            memo: instruction.memo,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _ActivityDepositInstructionPanel(instruction: instruction),
        const SizedBox(height: AppSpacing.xs),
        _DepositTxHashDisclosure(
          state: state,
          instruction: instruction,
          onDepositTxHashChanged: onDepositTxHashChanged,
          onSubmitDepositTransaction: onSubmitDepositTransaction,
          liveFundsEnabled: liveFundsEnabled,
        ),
      ],
    );
  }
}

class _ActivityDepositInstructionPanel extends StatelessWidget {
  const _ActivityDepositInstructionPanel({required this.instruction});

  final _ActivityDepositInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            instruction.sendLabel,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ActivityInstructionRow(
            label: instruction.depositAddressLabel,
            value: instruction.address,
          ),
          if (instruction.memo != null)
            _ActivityInstructionRow(label: 'Memo', value: instruction.memo!),
          _ActivityInstructionRow(
            label: instruction.deliveryLabel,
            value: instruction.deliveryValue,
          ),
        ],
      ),
    );
  }
}

class _ActivityInstructionRow extends StatelessWidget {
  const _ActivityInstructionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          _CopyValueButton(label: label, value: value),
        ],
      ),
    );
  }
}

class _DepositTxHashDisclosure extends StatefulWidget {
  const _DepositTxHashDisclosure({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.liveFundsEnabled,
  });

  final SwapPrototypeState state;
  final _ActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final bool liveFundsEnabled;

  @override
  State<_DepositTxHashDisclosure> createState() =>
      _DepositTxHashDisclosureState();
}

class _DepositTxHashDisclosureState extends State<_DepositTxHashDisclosure> {
  late bool _expanded = widget.state.depositTxHashText.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant _DepositTxHashDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.depositTxHashText.trim().isNotEmpty && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSubmit =
        widget.state.canSubmitDepositTx && widget.liveFundsEnabled;
    final submitLabel = widget.state.depositSubmitting
        ? 'Submitting'
        : widget.instruction.submitLabel;
    return Container(
      key: const ValueKey('swap_deposit_tx_hash_disclosure'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.background.raised,
                  border: Border.all(color: colors.border.subtle),
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                ),
                child: AppIcon(
                  AppIcons.link,
                  size: 16,
                  color: colors.icon.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Already sent?',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.liveFundsEnabled
                          ? 'Add the deposit transaction hash to speed up status checks.'
                          : 'Live submit disabled',
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('swap_deposit_tx_hash_toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                trailing: AppIcon(
                  _expanded ? AppIcons.arrowUpward : AppIcons.arrowDown,
                ),
                child: Text(_expanded ? 'Hide' : 'Add tx hash'),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    key: const ValueKey('swap_deposit_tx_hash_field'),
                    label: widget.instruction.txHashLabel,
                    initialValue: widget.state.depositTxHashText,
                    hintText: widget.instruction.txHashHint,
                    showClearButton: true,
                    onChanged: widget.onDepositTxHashChanged,
                    onClear: () => widget.onDepositTxHashChanged(''),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (canSubmit) {
                        widget.onSubmitDepositTransaction();
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      key: const ValueKey('swap_deposit_submit_button'),
                      onPressed: canSubmit
                          ? widget.onSubmitDepositTransaction
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: const AppIcon(AppIcons.link),
                      child: Text(submitLabel),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivitySupportDetailsSection extends StatefulWidget {
  const _ActivitySupportDetailsSection({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  State<_ActivitySupportDetailsSection> createState() =>
      _ActivitySupportDetailsSectionState();
}

class _ActivitySupportDetailsSectionState
    extends State<_ActivitySupportDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_support_details_section'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Support details',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              AppButton(
                key: const ValueKey('swap_support_details_toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.scroll),
                trailing: AppIcon(
                  _expanded ? AppIcons.arrowUpward : AppIcons.arrowDown,
                ),
                child: Text(_expanded ? 'Hide' : 'Show'),
              ),
            ],
          ),
          if (!_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                'Receipt and recovery bundle are available if support needs them.',
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: RedactedReceiptDrawer(
                rows: widget.intent.receipt,
                intent: widget.intent,
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyValueButton extends StatelessWidget {
  const _CopyValueButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keyLabel = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return Semantics(
      button: true,
      label: 'Copy $label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('swap_copy_$keyLabel'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            unawaited(Clipboard.setData(ClipboardData(text: value)));
          },
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.raised,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(AppIcons.copy, size: 14, color: colors.icon.muted),
          ),
        ),
      ),
    );
  }
}

class _SwapPageTabButton extends StatelessWidget {
  const _SwapPageTabButton({
    required this.tab,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final _SwapPageTab tab;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_page_tab_${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.state.selectedOpacity : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Flexible(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: selected
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: AppSpacing.xxs),
                Container(
                  key: tab == _SwapPageTab.activity
                      ? const ValueKey('swap_activity_open_count')
                      : null,
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: colors.background.brandCrimsonAlpha,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.brandCrimson,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapComposerStack extends StatelessWidget {
  const _SwapComposerStack({
    required this.selectedTab,
    required this.viewportHeight,
    required this.state,
    required this.openCount,
    required this.onTabChanged,
    required this.onAmountChanged,
    required this.onDestinationChanged,
    required this.onDirectionChanged,
    required this.onToggleDirection,
    required this.onExternalAssetChanged,
    required this.onSlippageChanged,
    required this.onReviewQuote,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onRetryShield,
    required this.onIntentSelected,
    required this.liveFundsEnabled,
  });

  final _SwapPageTab selectedTab;
  final double? viewportHeight;
  final SwapPrototypeState state;
  final int openCount;
  final ValueChanged<_SwapPageTab> onTabChanged;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final ValueChanged<SwapAsset> onExternalAssetChanged;
  final ValueChanged<int> onSlippageChanged;
  final VoidCallback onReviewQuote;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final VoidCallback onRetryShield;
  final ValueChanged<String> onIntentSelected;
  final bool liveFundsEnabled;

  @override
  Widget build(BuildContext context) {
    final selectedIntent = state.selectedIntentOrNull;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwapPageTabs(
            selected: selectedTab,
            openCount: openCount,
            onChanged: onTabChanged,
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (selectedTab == _SwapPageTab.swap) ...[
            _SwapComposerBody(
              bodyHeight: _swapBodyHeight,
              state: state,
              onReviewQuote: onReviewQuote,
              child: SwapComposerPanel(
                state: state,
                onAmountChanged: onAmountChanged,
                onDestinationChanged: onDestinationChanged,
                onDirectionChanged: onDirectionChanged,
                onToggleDirection: onToggleDirection,
                onExternalAssetChanged: onExternalAssetChanged,
                onSlippageChanged: onSlippageChanged,
              ),
            ),
          ] else ...[
            SwapQueuePanel(
              intents: state.intents,
              selectedIntentId: selectedIntent?.id,
              onIntentSelected: onIntentSelected,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (selectedIntent == null)
              const _SwapActivityEmptyState()
            else
              _SwapActivityStack(
                state: state,
                selectedIntent: selectedIntent,
                onRefreshStatus: onRefreshStatus,
                onDepositTxHashChanged: onDepositTxHashChanged,
                onSubmitDepositTransaction: onSubmitDepositTransaction,
                onReviewFreshQuote: onReviewFreshQuote,
                onRetryShield: onRetryShield,
                liveFundsEnabled: liveFundsEnabled,
              ),
          ],
        ],
      ),
    );
  }

  double? get _swapBodyHeight {
    final height = viewportHeight;
    if (height == null || !height.isFinite) return null;
    const tabsAndGapHeight = 48.0;
    final target = height - tabsAndGapHeight;
    if (target <= 0) return null;
    return target;
  }
}

class _SwapComposerBody extends StatelessWidget {
  const _SwapComposerBody({
    required this.bodyHeight,
    required this.state,
    required this.onReviewQuote,
    required this.child,
  });

  final double? bodyHeight;
  final SwapPrototypeState state;
  final VoidCallback onReviewQuote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final footer = _SwapReviewFooter(
      state: state,
      onReviewQuote: onReviewQuote,
    );
    final height = bodyHeight;
    if (height == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: AppSpacing.xs),
          footer,
        ],
      );
    }

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: footer),
        ],
      ),
    );
  }
}

class _SwapReviewFooter extends StatelessWidget {
  const _SwapReviewFooter({required this.state, required this.onReviewQuote});

  final SwapPrototypeState state;
  final VoidCallback onReviewQuote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppButton(
          key: const ValueKey('swap_review_button'),
          onPressed: state.canReviewQuote ? onReviewQuote : null,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: constraints.maxWidth,
          leading: state.quoteLoading ? const AppIcon(AppIcons.loader) : null,
          trailing: state.quoteLoading
              ? null
              : const AppIcon(AppIcons.arrowForwardIos),
          child: Text(state.quoteLoading ? 'Getting quote' : 'Review swap'),
        );
      },
    );
  }
}
