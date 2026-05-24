import 'dart:async';

import 'package:flutter/material.dart'
    show
        Icons,
        IconButton,
        InputDecoration,
        OutlineInputBorder,
        TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/hidden_memos_provider.dart';
import '../../../providers/memo_repository.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../activity_row_mapper.dart';
import '../models/memo_hide_key.dart';
import '../screens/activity_transaction_status_screen.dart';

const _kMemoMaxLength = 100;
const _kSearchDebounce = Duration(milliseconds: 350);

/// View mode for the Memos tab: inbox or hidden.
enum _MemosView { inbox, hidden }

/// A self-contained Memos tab intended to be embedded inside the Activity
/// screen. It owns its own search state and delegates data fetching to
/// [receivedMemosProvider] via [MemoRepository], making it trivially testable
/// by overriding [memoRepositoryProvider] in a [ProviderScope].
///
/// Per-row hide/restore actions and a Hidden segment are integrated via the
/// [hiddenMemosProvider].
class MemosTab extends ConsumerStatefulWidget {
  const MemosTab({super.key});

  @override
  ConsumerState<MemosTab> createState() => _MemosTabState();
}

class _MemosTabState extends ConsumerState<MemosTab> {
  final _searchController = TextEditingController();
  String _committedQuery = '';
  Timer? _debounce;
  _MemosView _view = _MemosView.inbox;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, () {
      if (!mounted) return;
      setState(() {
        _committedQuery = value.trim();
      });
    });
  }

  void _navigateToMemo(BuildContext context, rust_sync.ReceivedMemo memo) {
    unawaited(
      Future.sync(
        () => context.push(
          Uri(
            path: '/activity/tx/${memo.txidHex}',
            queryParameters: {'kind': memo.txKind},
          ).toString(),
          extra: ActivityTransactionStatusArgs(
            txidHex: memo.txidHex,
            txKind: memo.txKind,
            initialTransaction: null,
            initialDetail: null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountUuid =
        ref.watch(accountProvider).value?.activeAccountUuid ?? '';

    final query = (
      accountUuid: accountUuid,
      query: _committedQuery.isEmpty ? null : _committedQuery,
    );
    final memosAsync = ref.watch(receivedMemosProvider(query));
    final hiddenKeys = ref.watch(hiddenMemosProvider).keysFor(accountUuid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBar(
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.xs),
        _ViewToggle(
          view: _view,
          onInbox: () => setState(() => _view = _MemosView.inbox),
          onHidden: () => setState(() => _view = _MemosView.hidden),
        ),
        const SizedBox(height: AppSpacing.s),
        Expanded(
          child: memosAsync.when(
            loading: () => const _MemosMessage(text: 'Loading memos...'),
            error: (e, _) => const _MemosMessage(
              text: 'Memos could not be loaded.',
              isError: true,
            ),
            data: (memos) {
              if (_view == _MemosView.hidden) {
                final hiddenMemos = memos
                    .where(
                      (m) => hiddenKeys.contains(
                        memoHideKey(
                          txidHex: m.txidHex,
                          outputPool: m.outputPool,
                          outputIndex: m.outputIndex,
                        ),
                      ),
                    )
                    .toList();
                if (hiddenMemos.isEmpty) {
                  return const _MemosMessage(text: 'No hidden memos');
                }
                return _MemosList(
                  memos: hiddenMemos,
                  onTap: (memo) => _navigateToMemo(context, memo),
                  trailing: (memo) => _RestoreButton(
                    memo: memo,
                    accountUuid: accountUuid,
                  ),
                );
              }

              // Inbox view: exclude hidden memos.
              final inboxMemos = memos
                  .where(
                    (m) => !hiddenKeys.contains(
                      memoHideKey(
                        txidHex: m.txidHex,
                        outputPool: m.outputPool,
                        outputIndex: m.outputIndex,
                      ),
                    ),
                  )
                  .toList();

              if (inboxMemos.isEmpty) {
                // If there are memos but all are hidden (inbox is empty because
                // every returned memo has been hidden), show a distinct message
                // pointing the user to the Hidden view.
                if (memos.isNotEmpty) {
                  return const _MemosMessage(
                    text: 'All memos hidden — see Hidden',
                  );
                }
                final hasQuery = _committedQuery.isNotEmpty;
                return _MemosMessage(
                  text: hasQuery ? 'No memos match' : 'No memos yet',
                );
              }
              return _MemosList(
                memos: inboxMemos,
                onTap: (memo) => _navigateToMemo(context, memo),
                trailing: (memo) => _HideButton(
                  memo: memo,
                  accountUuid: accountUuid,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.view,
    required this.onInbox,
    required this.onHidden,
  });

  final _MemosView view;
  final VoidCallback onInbox;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _ToggleChip(
          key: const ValueKey('memos_inbox_toggle'),
          label: 'Inbox',
          selected: view == _MemosView.inbox,
          onTap: onInbox,
          colors: colors,
        ),
        const SizedBox(width: AppSpacing.xs),
        _ToggleChip(
          key: const ValueKey('memos_hidden_toggle'),
          label: 'Hidden',
          selected: view == _MemosView.hidden,
          onTap: onHidden,
          colors: colors,
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.text.accent
              : colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: selected ? colors.background.base : colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search memos',
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: colors.text.secondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: colors.border.subtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: colors.border.subtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: colors.text.accent),
        ),
        filled: true,
        fillColor: colors.background.neutralSubtleOpacity,
      ),
      style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
    );
  }
}

class _MemosList extends StatelessWidget {
  const _MemosList({
    required this.memos,
    required this.onTap,
    this.trailing,
  });

  final List<rust_sync.ReceivedMemo> memos;
  final ValueChanged<rust_sync.ReceivedMemo> onTap;
  final Widget Function(rust_sync.ReceivedMemo)? trailing;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: memos.length,
      separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (_, i) => MemoRow(
        key: ValueKey('memo_row_$i'),
        memo: memos[i],
        onTap: () => onTap(memos[i]),
        trailing: trailing?.call(memos[i]),
      ),
    );
  }
}

class _HideButton extends ConsumerWidget {
  const _HideButton({required this.memo, required this.accountUuid});

  final rust_sync.ReceivedMemo memo;
  final String accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return IconButton(
      key: ValueKey('hide_memo_${memo.txidHex}'),
      icon: Icon(
        Icons.visibility_off_outlined,
        size: 18,
        color: colors.text.secondary,
      ),
      onPressed: () {
        final key = memoHideKey(
          txidHex: memo.txidHex,
          outputPool: memo.outputPool,
          outputIndex: memo.outputIndex,
        );
        ref.read(hiddenMemosProvider.notifier).hide(
          accountUuid: accountUuid,
          key: key,
        );
      },
      tooltip: 'Hide memo',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}

class _RestoreButton extends ConsumerWidget {
  const _RestoreButton({required this.memo, required this.accountUuid});

  final rust_sync.ReceivedMemo memo;
  final String accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return IconButton(
      key: ValueKey('restore_memo_${memo.txidHex}'),
      icon: Icon(
        Icons.visibility_outlined,
        size: 18,
        color: colors.text.secondary,
      ),
      onPressed: () {
        final key = memoHideKey(
          txidHex: memo.txidHex,
          outputPool: memo.outputPool,
          outputIndex: memo.outputIndex,
        );
        ref.read(hiddenMemosProvider.notifier).restore(
          accountUuid: accountUuid,
          key: key,
        );
      },
      tooltip: 'Restore memo',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}

class _MemosMessage extends StatelessWidget {
  const _MemosMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Text(
        text,
        style: AppTypography.bodyMedium.copyWith(
          color: isError ? colors.text.destructive : colors.text.secondary,
        ),
      ),
    );
  }
}

/// Public so tests and other features can reference this widget directly.
/// Accepts an optional [trailing] widget (e.g. a hide or restore button).
class MemoRow extends StatelessWidget {
  const MemoRow({super.key, required this.memo, this.onTap, this.trailing});

  final rust_sync.ReceivedMemo memo;
  final VoidCallback? onTap;

  /// Optional trailing action widget (hide button, restore button, etc.).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timestamp = _memoTimestamp(memo);
    final timestampText = formatActivityTimestamp(timestamp);
    final amountText = ZecAmount.fromZatoshi(memo.amountZatoshi).activity.toString();
    final memoText = memo.memo.length > _kMemoMaxLength
        ? '${memo.memo.substring(0, _kMemoMaxLength)}...'
        : memo.memo;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The tappable content area — wraps only text and amount so that
        // the trailing action button can be tapped independently without
        // the row navigation also firing.
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor:
                  onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memoText,
                    key: ValueKey('memo_text_${memo.txidHex}'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.primary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    timestampText,
                    style: AppTypography.labelSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor:
                onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
            child: Text(
              amountText,
              key: ValueKey('memo_amount_${memo.txidHex}'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.brandCrimson,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          trailing!,
        ],
      ],
    );

    // The tappable content (text + amount) carries its own click cursor via the
    // inner MouseRegions, and the trailing IconButton keeps its own button
    // cursor. The outer region defers so the non-interactive gaps/padding do
    // not claim the click cursor regardless of whether a trailing action
    // is present.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: content,
    );
  }
}

DateTime? _memoTimestamp(rust_sync.ReceivedMemo memo) {
  final seconds = memo.blockTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}
