import 'dart:async';

import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        Divider,
        ScaffoldMessenger,
        SelectableText,
        SnackBar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../models/multisig_finalize_args.dart';
import '../widgets/multisig_backup_wizard.dart';
import '../widgets/multisig_flow_scaffold.dart';

class MultisigSessionScreen extends ConsumerStatefulWidget {
  const MultisigSessionScreen({required this.sessionStorageId, super.key});

  final String sessionStorageId;

  @override
  ConsumerState<MultisigSessionScreen> createState() =>
      _MultisigSessionScreenState();
}

class _MultisigSessionScreenState extends ConsumerState<MultisigSessionScreen> {
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isLocking = false;
  bool _isAdvancingCreate = false;
  bool _isConfirmingBackup = false;
  int? _selectedThreshold;
  String? _error;
  MultisigCreateAdvanceResult? _createProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted ||
          _isRefreshing ||
          _isLocking ||
          _isAdvancingCreate ||
          _isConfirmingBackup) {
        return;
      }
      _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      if (!silent) _error = null;
    });
    try {
      await ref
          .read(multisigPendingSessionsProvider.notifier)
          .refreshSession(widget.sessionStorageId);
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        if (!silent) _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _lockRoster(MultisigPendingSession session) async {
    final threshold = _selectedThreshold;
    if (threshold == null || _isLocking) return;
    setState(() {
      _isLocking = true;
      _error = null;
    });
    try {
      await ref
          .read(multisigPendingSessionsProvider.notifier)
          .lockSession(storageId: session.storageId, threshold: threshold);
      if (!mounted) return;
      setState(() => _isLocking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocking = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _advanceCreate(MultisigPendingSession session) async {
    if (_isAdvancingCreate) return;
    setState(() {
      _isAdvancingCreate = true;
      _error = null;
    });
    try {
      final progress = await ref
          .read(multisigPendingSessionsProvider.notifier)
          .advanceCreate(session.storageId);
      if (!mounted) return;
      setState(() {
        _isAdvancingCreate = false;
        _createProgress = progress;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAdvancingCreate = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _confirmBackup(
    MultisigPendingSession session,
    MultisigBackupCompletion completion,
  ) async {
    if (_isConfirmingBackup) return;
    setState(() {
      _isConfirmingBackup = true;
      _error = null;
    });
    try {
      if (!multisigLocalBackupCompleted(session)) {
        await ref
            .read(multisigPendingSessionsProvider.notifier)
            .markLocalBackupVerified(
              storageId: session.storageId,
              backupHash: completion.backupHash,
              destinations: completion.destinations,
            );
      }
      if (!mounted) return;
      context.go(
        '/multisig/session/${Uri.encodeComponent(session.storageId)}/birthday',
        extra: MultisigFinalizeArgs(
          sessionStorageId: session.storageId,
          sessionId: session.sessionId,
          backupArtifactJson: completion.backupArtifactJson,
          backupPassphrase: completion.backupPassphrase,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConfirmingBackup = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _copySessionId(String sessionId) async {
    await Clipboard.setData(ClipboardData(text: sessionId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session ID copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(multisigPendingSessionsProvider);
    final session = sessionsAsync.value == null
        ? null
        : multisigSessionByStorageId(
                sessionsAsync.value!,
                widget.sessionStorageId,
              ) ??
              multisigSessionById(
                sessionsAsync.value!,
                widget.sessionStorageId,
              );
    final participantsCount = session?.participants.length ?? 0;
    if (session != null && _selectedThreshold == null) {
      final maxThreshold = participantsCount <= 0 ? 1 : participantsCount;
      final defaultThreshold =
          session.threshold ?? (participantsCount >= 2 ? 2 : 1);
      _selectedThreshold = defaultThreshold.clamp(1, maxThreshold).toInt();
    }

    return MultisigFlowScaffold(
      title: 'Multisig setup',
      subtitle: session == null
          ? 'Session state is stored locally after create or join.'
          : session.displayLabel,
      iconName: AppIcons.users,
      trailing: session == null
          ? null
          : AppButton(
              onPressed: _isRefreshing ? null : () => _refresh(),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              leading: _isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon(AppIcons.sync),
              child: const Text('Refresh'),
            ),
      child: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _EmptyState(message: error.toString()),
        data: (_) {
          if (session == null) {
            return const _EmptyState(message: 'Session not found.');
          }
          return _SessionContent(
            session: session,
            selectedThreshold: _selectedThreshold,
            isLocking: _isLocking,
            isAdvancingCreate: _isAdvancingCreate,
            isConfirmingBackup: _isConfirmingBackup,
            createProgress: _createProgress,
            error: _error,
            onThresholdChanged: (value) {
              if (value == null) return;
              setState(() => _selectedThreshold = value);
            },
            onCopySessionId: () => _copySessionId(session.sessionId),
            onLockRoster: () => _lockRoster(session),
            onAdvanceCreate: () => _advanceCreate(session),
            onConfirmBackup: (completion) =>
                _confirmBackup(session, completion),
          );
        },
      ),
    );
  }
}

class _SessionContent extends StatelessWidget {
  const _SessionContent({
    required this.session,
    required this.selectedThreshold,
    required this.isLocking,
    required this.isAdvancingCreate,
    required this.isConfirmingBackup,
    required this.createProgress,
    required this.error,
    required this.onThresholdChanged,
    required this.onCopySessionId,
    required this.onLockRoster,
    required this.onAdvanceCreate,
    required this.onConfirmBackup,
  });

  final MultisigPendingSession session;
  final int? selectedThreshold;
  final bool isLocking;
  final bool isAdvancingCreate;
  final bool isConfirmingBackup;
  final MultisigCreateAdvanceResult? createProgress;
  final String? error;
  final ValueChanged<int?> onThresholdChanged;
  final VoidCallback onCopySessionId;
  final VoidCallback onLockRoster;
  final VoidCallback onAdvanceCreate;
  final ValueChanged<MultisigBackupCompletion> onConfirmBackup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canLock =
        session.isCreator &&
        session.state == 'collecting' &&
        session.participants.length > 1 &&
        selectedThreshold != null;
    final showBackupPanel = session.state == 'ready';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionIdPanel(session: session, onCopy: onCopySessionId),
          const SizedBox(height: AppSpacing.md),
          _ProgressPanel(session: session),
          const SizedBox(height: AppSpacing.md),
          _ParticipantsPanel(session: session),
          const SizedBox(height: AppSpacing.md),
          if (session.state == 'collecting') ...[
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border.subtle),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Threshold',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (
                          var value = 1;
                          value <= session.participants.length;
                          value++
                        )
                          _ThresholdChoice(
                            value: value,
                            total: session.participants.length,
                            selected: selectedThreshold == value,
                            onSelected: () => onThresholdChanged(value),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      onPressed: canLock && !isLocking ? onLockRoster : null,
                      minWidth: 180,
                      leading: isLocking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const AppIcon(AppIcons.lock),
                      child: const Text('Lock roster'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (session.state == 'request_create') ...[
            _CreatePanel(
              session: session,
              progress: createProgress,
              isAdvancing: isAdvancingCreate,
              onAdvance: onAdvanceCreate,
            ),
          ],
          if (showBackupPanel) ...[
            MultisigBackupWizard(
              session: session,
              isCompleting: isConfirmingBackup,
              onComplete: onConfirmBackup,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              error!,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionIdPanel extends StatelessWidget {
  const _SessionIdPanel({required this.session, required this.onCopy});

  final MultisigPendingSession session;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session ID',
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SelectableText(
                    session.sessionId,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              onPressed: onCopy,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              leading: const AppIcon(AppIcons.copy),
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.session});

  final MultisigPendingSession session;

  @override
  Widget build(BuildContext context) {
    final states = const [
      ('collecting', 'Participants'),
      ('request_create', 'Create'),
      ('local_backup', 'Backup'),
      ('ready', 'Ready'),
    ];
    final activeState =
        session.state == 'ready' && !multisigLocalBackupCompleted(session)
        ? 'local_backup'
        : session.state;
    final activeIndex = states.indexWhere((entry) => entry.$1 == activeState);
    return Row(
      children: [
        for (var index = 0; index < states.length; index++) ...[
          Expanded(
            child: _ProgressStep(
              label: states[index].$2,
              active: index == activeIndex,
              complete: activeIndex > index,
            ),
          ),
          if (index < states.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.active,
    required this.complete,
  });

  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = complete || active
        ? colors.state.selectedOpacity
        : colors.background.base;
    final text = complete || active ? colors.text.accent : colors.text.muted;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(color: text),
        ),
      ),
    );
  }
}

class _ParticipantsPanel extends StatelessWidget {
  const _ParticipantsPanel({required this.session});

  final MultisigPendingSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Participants',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${session.participants.length}',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final participant in session.participants) ...[
              _ParticipantRow(
                participant: participant,
                creator:
                    participant.participantId == session.creatorParticipantId,
                local: participant.participantId == session.participantId,
              ),
              if (participant != session.participants.last) const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreatePanel extends StatelessWidget {
  const _CreatePanel({
    required this.session,
    required this.progress,
    required this.isAdvancing,
    required this.onAdvance,
  });

  final MultisigPendingSession session;
  final MultisigCreateAdvanceResult? progress;
  final bool isAdvancing;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = session.participants.length;
    final backendDone = session.participants
        .where((participant) => participant.dkgCompleted)
        .length;
    final waiting = progress?.waitingForParticipants ?? const [];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Create account',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const Spacer(),
                _MiniBadge(label: '$backendDone of $total done'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _CreateStatusRow(
              iconName: AppIcons.sync,
              title: _phaseLabel(progress?.phase),
              detail: progress?.detail ?? 'Ready to continue local setup.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _ProtocolCounter(
                    label: 'Round 1',
                    value: progress?.round1Count ?? 0,
                    total: total,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _ProtocolCounter(
                    label: 'Round 2',
                    value: progress?.round2Count ?? 0,
                    total: total > 0 ? total - 1 : 0,
                  ),
                ),
              ],
            ),
            if (waiting.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final participant in waiting)
                    _MiniBadge(label: participant.displayName),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: isAdvancing ? null : onAdvance,
              minWidth: 180,
              leading: isAdvancing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon(AppIcons.sync),
              child: Text(progress == null ? 'Start create' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateStatusRow extends StatelessWidget {
  const _CreateStatusRow({
    required this.iconName,
    required this.title,
    required this.detail,
  });

  final String iconName;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(iconName, color: colors.icon.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                detail,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProtocolCounter extends StatelessWidget {
  const _ProtocolCounter({
    required this.label,
    required this.value,
    required this.total,
  });

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Text(
            '$value/$total',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.creator,
    required this.local,
  });

  final MultisigPendingParticipant participant;
  final bool creator;
  final bool local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          AppIcon(AppIcons.user, color: colors.icon.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              participant.displayName,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
          if (local) _MiniBadge(label: 'You'),
          if (creator) ...[
            const SizedBox(width: AppSpacing.xxs),
            _MiniBadge(label: 'Creator'),
          ],
        ],
      ),
    );
  }
}

String _phaseLabel(String? phase) {
  return switch (phase) {
    'waiting_for_seed' => 'Waiting for seed',
    'waiting_for_round1' => 'Waiting for round 1',
    'waiting_for_round2' => 'Waiting for round 2',
    'finalized' => 'Finalized',
    'dkg_complete' => 'Create complete',
    'local_backup' => 'Backup required',
    'ready' => 'Ready',
    'in_progress' => 'Creating',
    _ => 'Ready',
  };
}

class _ThresholdChoice extends StatelessWidget {
  const _ThresholdChoice({
    required this.value,
    required this.total,
    required this.selected,
    required this.onSelected,
  });

  final int value;
  final int total;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onSelected,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      size: AppButtonSize.medium,
      child: Text('$value of $total'),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.state.selectedOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: colors.text.accent),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Text(
        message,
        style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
      ),
    );
  }
}
