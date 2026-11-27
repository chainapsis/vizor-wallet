import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// PD-3 on desktop.
class ProxyDelegateProfileScreen extends StatelessWidget {
  /// Creates the screen.
  const ProxyDelegateProfileScreen({
    required this.roundId,
    required this.delegateIndex,
    super.key,
  });

  /// Round being delegated.
  final String roundId;

  /// Registry index of the delegate.
  final int delegateIndex;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: ProxyDelegateProfileView(
          roundId: roundId,
          delegateIndex: delegateIndex,
          showDesktopToolbar: true,
        ),
      ),
    );
  }
}

/// PD-3: a delegate's profile, opened from browse, search or a paste. Shows no ZEC
/// totals, delegation counts or track record.
class ProxyDelegateProfileView extends ConsumerWidget {
  /// Creates the view.
  const ProxyDelegateProfileView({
    required this.roundId,
    required this.delegateIndex,
    required this.showDesktopToolbar,
    super.key,
  });

  /// Round being delegated.
  final String roundId;

  /// Registry index of the delegate.
  final int delegateIndex;

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
    if (key == null) return const VotingPaneLoading();
    final directory = ref.watch(proxyDirectoryProvider(key));
    final draft = ref.watch(proxyAllocationDraftProvider(key));
    final entry = _findEntry(directory.value, draft, delegateIndex);
    final selected = draft.contains(delegateIndex);
    final canAdd = entry != null && !draft.isFull && !entry.blocked;
    return ProxyPaneLayout(
      showDesktopToolbar: showDesktopToolbar,
      title: entry == null
          ? context.l10n.proxyProfileTitle
          : proxyListingName(entry),
      action: entry == null
          ? null
          : AppButton(
              key: const ValueKey('proxy_profile_toggle'),
              onPressed: selected || canAdd
                  ? () => ref
                        .read(proxyAllocationDraftProvider(key).notifier)
                        .toggle(entry)
                  : null,
              variant: selected
                  ? AppButtonVariant.secondary
                  : AppButtonVariant.primary,
              expand: true,
              growWithContent: true,
              constrainContent: true,
              child: Text(
                selected
                    ? context.l10n.proxyRemoveFromDelegationLabel
                    : context.l10n.proxyAddToDelegationLabel,
              ),
            ),
      child: directory.isLoading && entry == null
          ? const VotingPaneLoading()
          : entry == null
          ? ProxyNotice(message: context.l10n.proxyProfileUnavailable)
          : ProxyDelegateProfileContent(entry: entry),
    );
  }
}

/// The entry for [index] from the browse list, the last search, the last
/// paste or the draft.
ProxyDelegateListing? _findEntry(
  ProxyDirectoryState? state,
  ProxyAllocationDraft draft,
  int index,
) {
  final candidates = [
    ...?state?.shown,
    for (final delegate in draft.delegates) delegate.entry,
  ];
  for (final entry in candidates) {
    if (entry.index == index) return entry;
  }
  return null;
}

/// Session-free PD-3 body shared by the live view and tests.
class ProxyDelegateProfileContent extends StatelessWidget {
  /// Creates the body.
  const ProxyDelegateProfileContent({required this.entry, super.key});

  /// Delegate to show.
  final ProxyDelegateListing entry;

  @override
  Widget build(BuildContext context) {
    final statement = entry.statement;
    const gap = SizedBox(height: AppSpacing.s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProxyDelegateSummary(entry: entry, identiconSize: 64),
              if (statement != null) ...[
                gap,
                Text(
                  statement,
                  key: const ValueKey('proxy_profile_statement'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (entry.newThisRound) ...[
          gap,
          ProxyNotice(message: context.l10n.proxyNewThisRound),
        ],
        for (final notice in proxyDelegateNotices(context.l10n, entry)) ...[
          gap,
          notice,
        ],
      ],
    );
  }
}
