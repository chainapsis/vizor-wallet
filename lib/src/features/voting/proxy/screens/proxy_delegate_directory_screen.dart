import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_form_factor.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/proxy_delegate_widgets.dart';
import 'proxy_add_delegate_dialog.dart';

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

/// PD-2: Vizor's reviewed list, filtered as the user types, with a quiet
/// way to add someone not on it. Shared by both form factors.
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roundId = widget.roundId;
    final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
    if (key == null) return const VotingPaneLoading();
    final directory = ref.watch(proxyDirectoryProvider(key));
    final draft = ref.watch(proxyAllocationDraftProvider(key));
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
        onSearchChanged: (_) => setState(() {}),
        onToggle: draftNotifier.toggle,
        onAddUnlisted: () => showProxyAddDelegateDialog(context, key),
      ),
    );
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.proxyDirectoryTitle,
      action: ProxyPickerFooter(
        chosen: [for (final delegate in draft.delegates) delegate.entry],
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
    required this.onSearchChanged,
    required this.onToggle,
    required this.onAddUnlisted,
    super.key,
  });

  /// Vizor's list.
  final ProxyDirectoryState state;

  /// Current selection.
  final ProxyAllocationDraft draft;

  /// Search field text, which filters the list.
  final TextEditingController searchController;

  /// The search text changed.
  final ValueChanged<String> onSearchChanged;

  /// Adds or removes a delegate.
  final ValueChanged<ProxyDelegateListing> onToggle;

  /// Opens the dialog for someone not on the list.
  final VoidCallback onAddUnlisted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final listed = proxyListMatches(state.browse.listed, '');
    final query = searchController.text;
    final matches = proxyListMatches(listed, query);
    final labelStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(l10n.proxyDirectorySubtitle),
        const SizedBox(height: AppSpacing.s),
        AppTextField(
          key: const ValueKey('proxy_directory_search'),
          label: l10n.proxySearchLabel,
          showLabel: false,
          hintText: l10n.proxySearchHint,
          controller: searchController,
          leading: const AppIcon(AppIcons.search),
          leadingSlotWidth: 40,
          inputHorizontalPadding: AppSpacing.xs,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          showClearButton: true,
          onChanged: onSearchChanged,
          onClear: () => onSearchChanged(''),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.browse.listUnavailable)
          ProxyNotice(
            key: const ValueKey('proxy_list_unavailable'),
            message: l10n.proxyListUnavailable,
            tone: ProxyNoticeTone.warning,
          )
        else ...[
          Row(
            children: [
              Expanded(child: Text(l10n.proxyListLabel, style: labelStyle)),
              Text(
                proxyHandleQuery(query).isEmpty
                    ? l10n.proxyListCount(listed.length)
                    : l10n.proxyListMatches(matches.length, listed.length),
                key: const ValueKey('proxy_directory_count'),
                style: labelStyle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (listed.isEmpty)
            ProxyBodyText(l10n.proxyBrowseEmpty)
          else if (matches.isEmpty)
            ProxyCard(
              key: const ValueKey('proxy_directory_no_matches'),
              child: ProxyBodyText(l10n.proxyNoListMatches(query.trim())),
            )
          else
            ProxyDelegateGroup(
              rows: [
                for (final entry in matches)
                  ProxyDelegateListRow(
                    entry: entry,
                    selected: draft.contains(entry.index),
                    onToggle: draft.contains(entry.index) || !draft.isFull
                        ? () => onToggle(entry)
                        : null,
                  ),
              ],
            ),
        ],
        const SizedBox(height: AppSpacing.s),
        Center(
          child: AppButton(
            key: const ValueKey('proxy_directory_add_unlisted'),
            onPressed: onAddUnlisted,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            growWithContent: true,
            constrainContent: true,
            leading: const AppIcon(AppIcons.plus),
            child: Text(l10n.proxyAddUnlistedLabel),
          ),
        ),
      ],
    );
  }
}

/// Picker footer: the chosen delegates' pictures, how many are chosen, and
/// Continue. The subtitle already says the cap, so the count names it only
/// once it is reached.
class ProxyPickerFooter extends StatelessWidget {
  /// Creates the footer.
  const ProxyPickerFooter({required this.chosen, this.onContinue, super.key});

  /// Delegates chosen, in order.
  final List<ProxyDelegateListing> chosen;

  /// Opens the allocation editor; null while nothing is chosen.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = chosen.length;
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    final summary = Row(
      mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (count > 0) ...[
          _StackedAvatars(chosen: chosen),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              count >= kProxyMaxDelegates
                  ? l10n.proxyChosenFull(count)
                  : l10n.proxyChosenCount(count),
              key: const ValueKey('proxy_picker_count'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      ],
    );
    final button = AppButton(
      key: const ValueKey('proxy_picker_continue'),
      onPressed: onContinue,
      minWidth: mobile ? null : 160,
      expand: mobile,
      // Beside the summary on desktop the button sizes to its label.
      growWithContent: mobile,
      constrainContent: mobile,
      child: Text(l10n.commonContinue),
    );
    if (mobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (count > 0) ...[
            Center(child: summary),
            const SizedBox(height: AppSpacing.xs),
          ],
          button,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: summary),
        const SizedBox(width: AppSpacing.s),
        button,
      ],
    );
  }
}

/// The chosen delegates' pictures, overlapping.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.chosen});

  final List<ProxyDelegateListing> chosen;

  static const _size = 24.0;
  static const _step = 16.0;
  static const _ring = 2.0;

  @override
  Widget build(BuildContext context) {
    final ring = context.colors.background.window;
    return ExcludeSemantics(
      child: SizedBox(
        width: _size + _ring * 2 + _step * (chosen.length - 1),
        height: _size + _ring * 2,
        child: Stack(
          children: [
            for (final (i, entry) in chosen.indexed)
              Positioned(
                left: _step * i,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_size / 4 + _ring),
                    border: Border.all(color: ring, width: _ring),
                  ),
                  child: ProxyDelegateAvatar(
                    fingerprint: entry.key.fingerprint,
                    picture: entry.listPicture,
                    size: _size,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
