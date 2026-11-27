import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// PD-2 on desktop.
class ProxyDelegateDirectoryScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const ProxyDelegateDirectoryScreen({required this.roundId, super.key});

  /// Round being delegated.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: ProxyDelegateDirectoryView(
          roundId: roundId,
          showDesktopToolbar: true,
        ),
      ),
    );
  }
}

/// PD-2: Vizor's list in list order, exact handle search, paste or scan,
/// and the picker, shared by both form factors.
class ProxyDelegateDirectoryView extends ConsumerStatefulWidget {
  /// Creates the view for [roundId].
  const ProxyDelegateDirectoryView({
    required this.roundId,
    required this.showDesktopToolbar,
    super.key,
  });

  /// Round being delegated.
  final String roundId;

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<ProxyDelegateDirectoryView> createState() =>
      _ProxyDelegateDirectoryViewState();
}

class _ProxyDelegateDirectoryViewState
    extends ConsumerState<ProxyDelegateDirectoryView> {
  final _searchController = TextEditingController();
  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  /// Opens the QR scanner and looks up what it reads.
  Future<void> _scan(ProxyDirectoryNotifier notifier) async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Center(
        child: AddressQrScanModal(
          resolve: proxyScanResolver,
          title: context.l10n.proxyScanTitle,
          onAddressScanned: (value) => Navigator.of(dialogContext).pop(value),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (scanned == null || !mounted) return;
    _pasteController.text = scanned;
    await notifier.lookup(scanned);
  }

  @override
  Widget build(BuildContext context) {
    final roundId = widget.roundId;
    final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
    if (key == null) return const VotingPaneLoading();
    final directory = ref.watch(proxyDirectoryProvider(key));
    final draft = ref.watch(proxyAllocationDraftProvider(key));
    final notifier = ref.read(proxyDirectoryProvider(key).notifier);
    final draftNotifier = ref.read(proxyAllocationDraftProvider(key).notifier);
    final body = directory.when(
      skipLoadingOnRefresh: false,
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.lg),
        child: VotingPaneLoading(),
      ),
      error: (error, _) => ProxyNotice(
        message: proxyErrorCopy(context.l10n, error),
        tone: ProxyNoticeTone.error,
        actionLabel: context.l10n.commonTryAgain,
        onAction: () => ref.invalidate(proxyDirectoryProvider(key)),
      ),
      data: (state) => ProxyDelegateDirectoryContent(
        state: state,
        draft: draft,
        searchController: _searchController,
        pasteController: _pasteController,
        onSearch: notifier.search,
        onClearSearch: () {
          _searchController.clear();
          notifier.clearSearch();
        },
        onLookup: notifier.lookup,
        onClearLookup: () {
          _pasteController.clear();
          notifier.clearLookup();
        },
        onScan: () => _scan(notifier),
        onToggle: draftNotifier.toggle,
        onOpen: (entry) =>
            context.push(proxyDelegateProfileRoute(roundId, entry.index)),
      ),
    );
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.proxyDirectoryTitle,
      action: ProxyPickerFooter(
        count: draft.delegates.length,
        onContinue: draft.delegates.isEmpty
            ? null
            : () => context.push(proxyAllocationRoute(roundId)),
      ),
      child: body,
    );
  }
}

/// Session-free PD-2 body shared by the live view and tests.
class ProxyDelegateDirectoryContent extends StatelessWidget {
  /// Creates the body.
  const ProxyDelegateDirectoryContent({
    required this.state,
    required this.draft,
    required this.searchController,
    required this.pasteController,
    required this.onSearch,
    required this.onClearSearch,
    required this.onLookup,
    required this.onClearLookup,
    required this.onToggle,
    required this.onOpen,
    this.onScan,
    super.key,
  });

  /// Browse, search and paste state.
  final ProxyDirectoryState state;

  /// Current selection.
  final ProxyAllocationDraft draft;

  /// Search field text.
  final TextEditingController searchController;

  /// Paste field text.
  final TextEditingController pasteController;

  /// Runs an exact handle search.
  final ValueChanged<String> onSearch;

  /// Returns to the browse list.
  final VoidCallback onClearSearch;

  /// Looks up pasted text.
  final ValueChanged<String> onLookup;

  /// Clears the paste answer.
  final VoidCallback onClearLookup;

  /// Opens the QR scanner; null hides the scan button.
  final VoidCallback? onScan;

  /// Adds or removes a delegate.
  final ValueChanged<ProxyDelegateListing> onToggle;

  /// Opens a delegate's profile.
  final ValueChanged<ProxyDelegateListing> onOpen;

  @override
  Widget build(BuildContext context) {
    final search = state.search;
    final onScan = this.onScan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(context.l10n.proxyDirectorySubtitle),
        const SizedBox(height: AppSpacing.s),
        AppTextField(
          key: const ValueKey('proxy_directory_paste'),
          label: context.l10n.proxyPasteLabel,
          hintText: context.l10n.proxyPasteHint,
          controller: pasteController,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: onLookup,
          showClearButton: true,
          onClear: onClearLookup,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: AppButton(
                key: const ValueKey('proxy_directory_find'),
                onPressed: () => onLookup(pasteController.text),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                child: Text(context.l10n.proxyFindLabel),
              ),
            ),
            if (onScan != null) ...[
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('proxy_directory_scan'),
                onPressed: onScan,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.qr),
                child: Text(context.l10n.proxyScanLabel),
              ),
            ],
          ],
        ),
        ..._lookup(context),
        const SizedBox(height: AppSpacing.s),
        AppTextField(
          key: const ValueKey('proxy_directory_search'),
          label: context.l10n.proxySearchLabel,
          hintText: context.l10n.proxySearchHint,
          controller: searchController,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: onSearch,
          showClearButton: true,
          onClear: onClearSearch,
        ),
        const SizedBox(height: AppSpacing.s),
        ...switch (search) {
          ProxySearchIdle() => _browse(context),
          ProxySearchRunning() => const [
            Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: VotingPaneLoading(),
            ),
          ],
          ProxySearchResults(:final query, :final entries) => _rows(
            entries,
            empty: context.l10n.proxyNoSearchResults(query),
          ),
        },
      ],
    );
  }

  /// The browse list, or why it is empty.
  List<Widget> _browse(BuildContext context) {
    if (state.browse.listUnavailable) {
      return [
        ProxyNotice(
          key: const ValueKey('proxy_list_unavailable'),
          message: context.l10n.proxyListUnavailable,
          tone: ProxyNoticeTone.warning,
        ),
      ];
    }
    return _rows(state.browse.listed, empty: context.l10n.proxyBrowseEmpty);
  }

  /// The paste or scan answer.
  List<Widget> _lookup(BuildContext context) {
    final lookup = state.lookup;
    final shown = switch (lookup) {
      ProxyLookupIdle() => const <Widget>[],
      ProxyLookupRunning() => const [VotingPaneLoading()],
      ProxyLookupFailed(:final error) => [
        ProxyNotice(
          key: const ValueKey('proxy_lookup_failed'),
          message: proxyErrorCopy(context.l10n, error),
          tone: ProxyNoticeTone.error,
        ),
      ],
      // A found answer missing its listing reads as not found.
      ProxyLookupDone(:final answer) => switch (answer) {
        ApiDelegateLookup(:final listing?) => [_row(listing)],
        ApiDelegateLookup(kind: ApiDelegateLookupKind.unrecognized) => [
          ProxyBodyText(
            context.l10n.proxyLookupUnrecognized,
            key: const ValueKey('proxy_lookup_unrecognized'),
          ),
        ],
        _ => [
          ProxyBodyText(
            context.l10n.proxyLookupNotFound,
            key: const ValueKey('proxy_lookup_not_found'),
          ),
        ],
      },
    };
    if (shown.isEmpty) return shown;
    return [const SizedBox(height: AppSpacing.xs), ...shown];
  }

  /// Rows for [entries], or [empty] when there are none.
  List<Widget> _rows(
    List<ProxyDelegateListing> entries, {
    required String empty,
  }) {
    if (entries.isEmpty) return [ProxyBodyText(empty)];
    return [
      for (final (i, entry) in entries.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpacing.xs),
        _row(entry),
      ],
    ];
  }

  /// One delegate's row.
  Widget _row(ProxyDelegateListing entry) => ProxyDelegateRow(
    entry: entry,
    selected: draft.contains(entry.index),
    canAdd: !draft.isFull && !entry.blocked,
    onToggle: () => onToggle(entry),
    onOpen: () => onOpen(entry),
  );
}

/// One delegate in the browse list, search results or a paste answer.
class ProxyDelegateRow extends StatelessWidget {
  /// Creates a row.
  const ProxyDelegateRow({
    required this.entry,
    required this.selected,
    required this.canAdd,
    required this.onToggle,
    required this.onOpen,
    super.key,
  });

  /// Delegate to show.
  final ProxyDelegateListing entry;

  /// Whether the delegate is in the draft.
  final bool selected;

  /// Whether the delegate may be added: the picker is not full and the
  /// delegate is neither suspended nor retired.
  final bool canAdd;

  /// Adds or removes the delegate.
  final VoidCallback onToggle;

  /// Opens the profile.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: GestureDetector(
        key: ValueKey('proxy_delegate_row_${entry.index}'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: ProxyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProxyDelegateSummary(
                entry: entry,
                trailing: AppButton(
                  key: ValueKey('proxy_pick_${entry.index}'),
                  onPressed: selected || canAdd ? onToggle : null,
                  variant: selected
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  leading: AppIcon(selected ? AppIcons.check : AppIcons.plus),
                  child: Text(
                    selected
                        ? context.l10n.proxyAddedLabel
                        : context.l10n.proxyAddLabel,
                  ),
                ),
              ),
              for (final notice in proxyDelegateNotices(
                context.l10n,
                entry,
              )) ...[const SizedBox(height: AppSpacing.xs), notice],
            ],
          ),
        ),
      ),
    );
  }
}

/// Picker footer: how many delegates are chosen, the cap and Continue.
class ProxyPickerFooter extends StatelessWidget {
  /// Creates the footer.
  const ProxyPickerFooter({required this.count, this.onContinue, super.key});

  /// Delegates chosen.
  final int count;

  /// Opens the allocation editor; null while nothing is chosen.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final full = count >= kProxyMaxDelegates;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          full
              ? context.l10n.proxyPickerCountFull(count)
              : context.l10n.proxyPickerCount(count),
          key: const ValueKey('proxy_picker_count'),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('proxy_picker_continue'),
          onPressed: onContinue,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.commonContinue),
        ),
      ],
    );
  }
}
