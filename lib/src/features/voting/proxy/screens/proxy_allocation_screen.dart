import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';
import '../../voting_flow_models.dart';
import '../../voting_routes.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// PD-5 editor on desktop.
class ProxyAllocationScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const ProxyAllocationScreen({required this.roundId, super.key});

  /// Round being delegated.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: ProxyAllocationView(roundId: roundId, showDesktopToolbar: true),
      ),
    );
  }
}

/// PD-5 editor: a share per chosen delegate and what is left to keep,
/// previewed by the planner. Done returns to the round's questions with the split.
class ProxyAllocationView extends ConsumerStatefulWidget {
  /// Creates the view for [roundId].
  const ProxyAllocationView({
    required this.roundId,
    required this.showDesktopToolbar,
    super.key,
  });

  /// Round being delegated.
  final String roundId;

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<ProxyAllocationView> createState() =>
      _ProxyAllocationViewState();
}

class _ProxyAllocationViewState extends ConsumerState<ProxyAllocationView> {
  final _controllers = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The share field controller for [delegate], created on first use.
  TextEditingController _controllerFor(ProxyDraftDelegate delegate) {
    return _controllers.putIfAbsent(
      delegate.entry.index,
      () => TextEditingController(text: _percentText(delegate.percentBps)),
    );
  }

  /// Disposes controllers of removed rows after their fields unmount.
  void _dropStaleControllers(ProxyAllocationDraft draft) {
    final stale = [
      for (final index in _controllers.keys)
        if (!draft.contains(index)) index,
    ];
    if (stale.isEmpty) return;
    final controllers = [
      for (final index in stale) _controllers.remove(index)!,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  /// Splits 100% evenly and shows the new shares in the fields.
  void _splitEvenly(VotingSessionKey key) {
    final notifier = ref.read(proxyAllocationDraftProvider(key).notifier);
    notifier.splitEvenly();
    for (final delegate
        in ref.read(proxyAllocationDraftProvider(key)).delegates) {
      _controllerFor(delegate).text = _percentText(delegate.percentBps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roundId = widget.roundId;
    final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
    if (key == null) return const VotingPaneLoading();
    final draft = ref.watch(proxyAllocationDraftProvider(key));
    _dropStaleControllers(draft);
    final notifier = ref.read(proxyAllocationDraftProvider(key).notifier);
    final round = ref.watch(proxyRoundContextProvider(key));
    final preview = ref.watch(proxyAllocationPreviewProvider(key));
    final now = ref.watch(proxyClockProvider)();
    final closed =
        round.value != null &&
        proxyDelegationWindowAt(now: now, voteEnd: round.value!.voteEndTime) ==
            ProxyDelegationWindow.closed;
    final canUse =
        draft.issue == null &&
        preview.value != null &&
        !preview.hasError &&
        !closed;
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.proxyAllocationTitle,
      // The split is part of the ballot: it goes back to the round's
      // questions, and the vote review confirms it.
      action: AppButton(
        key: const ValueKey('proxy_allocation_done'),
        onPressed: canUse ? () => context.go(votingPollRoute(roundId)) : null,
        expand: true,
        growWithContent: true,
        constrainContent: true,
        child: Text(context.l10n.commonDone),
      ),
      child: round.when(
        loading: () => const VotingPaneLoading(),
        error: (error, _) => ProxyNotice(
          message: proxyErrorCopy(context.l10n, error),
          tone: ProxyNoticeTone.error,
          actionLabel: context.l10n.commonTryAgain,
          onAction: () => ref.invalidate(proxyRoundContextProvider(key)),
        ),
        data: (round) => ProxyAllocationContent(
          round: round,
          draft: draft,
          preview: preview,
          now: now,
          controllerFor: _controllerFor,
          onPercentChanged: (position, text) =>
              notifier.setPercent(position, parseProxyPercent(text)),
          onRemove: (position) =>
              notifier.toggle(draft.delegates[position].entry),
          onAddDelegate: draft.isFull
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(proxyDelegateDirectoryRoute(roundId));
                  }
                },
          onSplitEvenly: () => _splitEvenly(key),
        ),
      ),
    );
  }
}

/// A share as the field shows it, without the `%` sign.
String _percentText(int? bps) {
  if (bps == null) return '';
  return formatProxyPercent(bps).replaceAll('%', '');
}

/// Session-free PD-5 editor body shared by the live view and tests.
class ProxyAllocationContent extends StatelessWidget {
  /// Creates the body.
  const ProxyAllocationContent({
    required this.round,
    required this.draft,
    required this.preview,
    required this.now,
    required this.controllerFor,
    required this.onPercentChanged,
    required this.onRemove,
    required this.onAddDelegate,
    required this.onSplitEvenly,
    super.key,
  });

  /// Round facts.
  final ProxyRoundContext round;

  /// Current selection and split.
  final ProxyAllocationDraft draft;

  /// Planner preview, null while the draft has an issue.
  final AsyncValue<ProxyAllocationPreview?> preview;

  /// Current time.
  final DateTime now;

  /// Text controller for a row.
  final TextEditingController Function(ProxyDraftDelegate) controllerFor;

  /// A row's share changed.
  final void Function(int position, String text) onPercentChanged;

  /// A row was removed.
  final void Function(int position) onRemove;

  /// Returns to the picker; null once [kProxyMaxDelegates] are chosen.
  final VoidCallback? onAddDelegate;

  /// Splits 100% evenly.
  final VoidCallback onSplitEvenly;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final planned = preview.value;
    final issue = draft.issue;
    const gap = SizedBox(height: AppSpacing.s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(
          context.l10n.proxyVotingPower(
            formatProxyBallots(round.eligibleBallots),
          ),
          strong: true,
        ),
        gap,
        // The review names the vote end; here only its passing shows.
        if (proxyDelegationWindowAt(now: now, voteEnd: round.voteEndTime) ==
            ProxyDelegationWindow.closed) ...[
          ProxyDelegationTimingNotice(now: now, voteEnd: round.voteEndTime),
          gap,
        ],
        for (final (position, delegate) in draft.delegates.indexed) ...[
          _AllocationRow(
            delegate: delegate,
            controller: controllerFor(delegate),
            amount: _plannedBallots(planned, delegate.entry.index),
            onChanged: (text) => onPercentChanged(position, text),
            onRemove: () => onRemove(position),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              key: const ValueKey('proxy_allocation_add_delegate'),
              onPressed: onAddDelegate,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              child: Text(context.l10n.proxyAddDelegateLabel),
            ),
            AppButton(
              key: const ValueKey('proxy_allocation_split_evenly'),
              onPressed: draft.delegates.isEmpty ? null : onSplitEvenly,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              child: Text(context.l10n.proxySplitEvenlyLabel),
            ),
          ],
        ),
        if (draft.isFull) ...[
          const SizedBox(height: AppSpacing.xs),
          ProxyBodyText(context.l10n.proxyPickerFull),
        ],
        gap,
        ProxyCard(
          key: const ValueKey('proxy_allocation_remainder'),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.proxyKeepForMyselfLabel,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Text(
                [
                  formatProxyPercent(draft.keptBps),
                  if (planned != null) formatProxyBallots(planned.keptBallots),
                ].join(' · '),
                key: const ValueKey('proxy_allocation_kept'),
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        if (issue != null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('proxy_allocation_issue'),
            message: proxyDraftIssueCopy(context.l10n, issue),
            tone: issue == ProxyDraftIssue.overAllocated
                ? ProxyNoticeTone.error
                : ProxyNoticeTone.info,
          ),
        ] else if (preview.hasError) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('proxy_allocation_preview_error'),
            message: proxyErrorCopy(context.l10n, preview.error!),
            tone: ProxyNoticeTone.error,
          ),
        ],
      ],
    );
  }

  /// The planned ballots for delegate [index], if previewed.
  BigInt? _plannedBallots(ProxyAllocationPreview? preview, int index) {
    if (preview == null) return null;
    for (final delegation in preview.delegations) {
      if (delegation.delegateIndex == index) return delegation.ballots;
    }
    return null;
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.delegate,
    required this.controller,
    required this.amount,
    required this.onChanged,
    required this.onRemove,
  });

  final ProxyDraftDelegate delegate;
  final TextEditingController controller;
  final BigInt? amount;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final entry = delegate.entry;
    final amount = this.amount;
    final lookalike = entry.lookalikeOf;
    return ProxyCard(
      key: ValueKey('proxy_allocation_row_${entry.index}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProxyDelegateSummary(
            entry: entry,
            identiconSize: 32,
            trailing: AppButton(
              key: ValueKey('proxy_allocation_remove_${entry.index}'),
              onPressed: onRemove,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              child: Text(context.l10n.commonRemove),
            ),
          ),
          if (lookalike != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ProxyNotice(
              message: context.l10n.proxyLookalike(lookalike),
              tone: ProxyNoticeTone.warning,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 140,
                child: AppTextField(
                  key: ValueKey('proxy_allocation_percent_${entry.index}'),
                  label: context.l10n.proxyPercentLabel,
                  controller: controller,
                  inlineSuffixText: '%',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const <TextInputFormatter>[
                    CommaToDotInputFormatter(),
                    DecimalAmountInputFormatter(
                      maxFractionDigits: 2,
                      maxLength: 6,
                    ),
                  ],
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    amount == null ? '' : formatProxyBallots(amount),
                    key: ValueKey('proxy_allocation_amount_${entry.index}'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
