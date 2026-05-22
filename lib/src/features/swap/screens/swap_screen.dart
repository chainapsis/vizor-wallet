import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../models/swap_prototype_models.dart';
import '../providers/swap_prototype_provider.dart';
import '../widgets/redacted_receipt_drawer.dart';
import '../widgets/swap_activity_panel.dart';
import '../widgets/swap_composer_panel.dart';
import '../widgets/swap_copy_feedback.dart';
import '../widgets/swap_review_modal.dart';

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key});

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  late final ScrollController _scrollController;
  late final FocusNode _shortcutFocusNode;
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_toast_overlay_context',
  );
  bool _commandPaletteOpen = false;

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
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next || !mounted) return;
        setState(() {
          _commandPaletteOpen = false;
        });
      },
    );
    final swapState = ref.watch(swapPrototypeProvider);
    final swapNotifier = ref.read(swapPrototypeProvider.notifier);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    String? accountLabelFor(String? accountUuid) {
      if (accountUuid == null || accountUuid.trim().isEmpty) return null;
      for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
        if (account.uuid == accountUuid) {
          return account.name;
        }
      }
      return null;
    }

    bool isHardwareIntent(SwapPrototypeIntent intent) {
      final accountUuid = intent.accountUuid;
      if (accountUuid == null || accountUuid.trim().isEmpty) return false;
      final currentAccountState =
          ref.read(accountProvider).value ?? accountState;
      final accountHardwareByUuid = {
        for (final account in currentAccountState?.accounts ?? const [])
          account.uuid: account.isHardware,
      };
      return accountHardwareByUuid[accountUuid] ?? false;
    }

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
    final reviewQuote = swapState.reviewQuote;
    final reviewAddressPlan = swapState.reviewAddressPlan;
    final reviewAccountLabel = accountLabelFor(swapState.reviewAccountUuid);

    void startIntent() {
      unawaited(() async {
        final started = await swapNotifier.startIntent();
        if (!context.mounted || !started) return;
        final startedIntent = ref
            .read(swapPrototypeProvider)
            .selectedIntentOrNull;
        if (startedIntent != null) {
          final needsKeystoneDeposit =
              isHardwareIntent(startedIntent) &&
              startedIntent.direction == SwapDirection.zecToExternal &&
              !(startedIntent.depositTxHash?.trim().isNotEmpty ?? false);
          context.go(
            Uri(
              path: '/activity/swap/${Uri.encodeComponent(startedIntent.id)}',
              queryParameters: {if (needsKeystoneDeposit) 'sign': 'zecDeposit'},
            ).toString(),
          );
          return;
        }
        context.go('/activity');
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
      child: Stack(
        children: [
          AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : null;
                  final primary = _SwapComposerStack(
                    viewportHeight: viewportHeight,
                    state: swapState,
                    onAmountChanged: swapNotifier.updateAmount,
                    onReceiveAmountChanged: swapNotifier.updateReceiveAmount,
                    onDestinationChanged: swapNotifier.updateDestination,
                    onDirectionChanged: swapNotifier.selectDirection,
                    onToggleDirection: swapNotifier.toggleDirection,
                    onExternalAssetChanged: swapNotifier.selectExternalAsset,
                    onSlippageChanged: swapNotifier.updateSlippageBps,
                    onUseMaxZecAmount: swapNotifier.useMaxZecAmount,
                    onReviewQuote: swapNotifier.showReview,
                    zecAvailableText: zecAvailableText,
                    zecAvailableZatoshi: sync.spendableBalance,
                  );

                  return SingleChildScrollView(
                    controller: _scrollController,
                    child: _SwapViewportFrame(
                      minHeight: viewportHeight,
                      alignment: Alignment.center,
                      child: primary,
                    ),
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
                    accountLabel: reviewAccountLabel,
                    expired: swapState.quoteExpired,
                    starting: swapState.startSubmitting,
                    amountWarning: swapState.reviewAmountDifferenceWarning,
                    startError: swapState.statusError,
                    startBlockedReason:
                        _reviewQuoteExceedsAvailableZec(
                          reviewQuote,
                          sync.spendableBalance,
                        )
                        ? 'Required pay exceeds available ZEC. Review a smaller target amount.'
                        : null,
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

class _SwapComposerStack extends StatelessWidget {
  const _SwapComposerStack({
    required this.viewportHeight,
    required this.state,
    required this.onAmountChanged,
    required this.onReceiveAmountChanged,
    required this.onDestinationChanged,
    required this.onDirectionChanged,
    required this.onToggleDirection,
    required this.onExternalAssetChanged,
    required this.onSlippageChanged,
    required this.onUseMaxZecAmount,
    required this.onReviewQuote,
    required this.zecAvailableText,
    required this.zecAvailableZatoshi,
  });

  final double? viewportHeight;
  final SwapPrototypeState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onReceiveAmountChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final ValueChanged<SwapAsset> onExternalAssetChanged;
  final ValueChanged<int> onSlippageChanged;
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
        onReviewQuote: onReviewQuote,
        child: SwapComposerPanel(
          state: state,
          onAmountChanged: onAmountChanged,
          onReceiveAmountChanged: onReceiveAmountChanged,
          onDestinationChanged: onDestinationChanged,
          onDirectionChanged: onDirectionChanged,
          onToggleDirection: onToggleDirection,
          onExternalAssetChanged: onExternalAssetChanged,
          onSlippageChanged: onSlippageChanged,
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

class _SwapComposerBody extends StatelessWidget {
  const _SwapComposerBody({
    required this.bodyHeight,
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onReviewQuote,
    required this.child,
  });

  final double? bodyHeight;
  final SwapPrototypeState state;
  final BigInt zecAvailableZatoshi;
  final VoidCallback onReviewQuote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final footer = _SwapReviewFooter(
      state: state,
      zecAvailableZatoshi: zecAvailableZatoshi,
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
  const _SwapReviewFooter({
    required this.state,
    required this.zecAvailableZatoshi,
    required this.onReviewQuote,
  });

  final SwapPrototypeState state;
  final BigInt zecAvailableZatoshi;
  final VoidCallback onReviewQuote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final balanceExceeded = _reviewAmountExceedsAvailableZec(
          state,
          zecAvailableZatoshi,
        );
        final canReview = state.canReviewQuote && !balanceExceeded;
        return AppButton(
          key: const ValueKey('swap_review_button'),
          onPressed: canReview ? onReviewQuote : null,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: constraints.maxWidth,
          leading: state.quoteLoading ? const AppIcon(AppIcons.loader) : null,
          trailing: state.quoteLoading
              ? null
              : const AppIcon(AppIcons.arrowForwardIos),
          child: Text(
            balanceExceeded
                ? 'Insufficient ZEC'
                : state.quoteLoading
                ? 'Getting quote'
                : 'Review swap',
          ),
        );
      },
    );
  }
}

bool _reviewAmountExceedsAvailableZec(
  SwapPrototypeState state,
  BigInt availableZatoshi,
) {
  if (!state.direction.sendsZec) return false;
  return _zecAmountTextExceedsAvailable(state.amountText, availableZatoshi);
}

bool _reviewQuoteExceedsAvailableZec(SwapQuote quote, BigInt availableZatoshi) {
  if (!quote.direction.sendsZec) return false;
  final amountText = quote.sellAmountText.split(' ').first.trim();
  return _zecAmountTextExceedsAvailable(amountText, availableZatoshi);
}

bool _zecAmountTextExceedsAvailable(
  String amountText,
  BigInt availableZatoshi,
) {
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
