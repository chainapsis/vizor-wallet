import 'dart:async';

import 'package:flutter/material.dart'
    show
        InputDecoration,
        OutlineInputBorder,
        TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/memo_repository.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../activity_row_mapper.dart';
import '../screens/activity_transaction_status_screen.dart';

const _kMemoMaxLength = 100;
const _kSearchDebounce = Duration(milliseconds: 350);

/// A self-contained Memos tab intended to be embedded inside the Activity
/// screen. It owns its own search state and delegates data fetching to
/// [receivedMemosProvider] via [MemoRepository], making it trivially testable
/// by overriding [memoRepositoryProvider] in a [ProviderScope].
///
/// Task 9 can add per-row hide/restore actions and a "Hidden" segment without
/// restructuring this widget — the list is exposed through a clean [List<
/// rust_sync.ReceivedMemo>] value that a future filter can slice.
class MemosTab extends ConsumerStatefulWidget {
  const MemosTab({super.key});

  @override
  ConsumerState<MemosTab> createState() => _MemosTabState();
}

class _MemosTabState extends ConsumerState<MemosTab> {
  final _searchController = TextEditingController();
  String _committedQuery = '';
  Timer? _debounce;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBar(
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.s),
        Expanded(
          child: memosAsync.when(
            loading: () => const _MemosMessage(text: 'Loading memos...'),
            error: (e, _) => _MemosMessage(
              text: 'Memos could not be loaded.',
              isError: true,
            ),
            data: (memos) {
              if (memos.isEmpty) {
                final hasQuery = _committedQuery.isNotEmpty;
                return _MemosMessage(
                  text: hasQuery ? 'No memos match' : 'No memos yet',
                );
              }
              return _MemosList(
                memos: memos,
                onTap: (memo) => _navigateToMemo(context, memo),
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
  const _MemosList({required this.memos, required this.onTap});

  final List<rust_sync.ReceivedMemo> memos;
  final ValueChanged<rust_sync.ReceivedMemo> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: memos.length,
      separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (_, i) => MemoRow(
        key: ValueKey('memo_row_$i'),
        memo: memos[i],
        onTap: () => onTap(memos[i]),
      ),
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

/// Public so Task 9 can add a hide-action slot without rebuilding this file.
class MemoRow extends StatelessWidget {
  const MemoRow({super.key, required this.memo, this.onTap});

  final rust_sync.ReceivedMemo memo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timestamp = _memoTimestamp(memo);
    final timestampText = formatActivityTimestamp(timestamp);
    final amountText = ZecAmount.fromZatoshi(memo.amountZatoshi).activity.toString();
    final memoText = memo.memo.length > _kMemoMaxLength
        ? '${memo.memo.substring(0, _kMemoMaxLength)}...'
        : memo.memo;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
              const SizedBox(width: AppSpacing.sm),
              Text(
                amountText,
                key: ValueKey('memo_amount_${memo.txidHex}'),
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.brandCrimson,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime? _memoTimestamp(rust_sync.ReceivedMemo memo) {
  final seconds = memo.blockTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}
