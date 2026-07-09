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
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../../../providers/multisig_realtime_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../onboarding/shared/onboarding_flow_args.dart';
import '../widgets/multisig_backup_wizard.dart';
import '../widgets/multisig_onboarding_flow.dart';
import '../widgets/multisig_setup_security_gate.dart';

class MultisigSessionScreen extends ConsumerStatefulWidget {
  const MultisigSessionScreen({required this.sessionStorageId, super.key});

  final String sessionStorageId;

  @override
  ConsumerState<MultisigSessionScreen> createState() =>
      _MultisigSessionScreenState();
}

class _MultisigSessionScreenState extends ConsumerState<MultisigSessionScreen> {
  Timer? _refreshTimer;
  Timer? _createAdvanceTimer;
  bool _isRefreshing = false;
  bool _isLocking = false;
  bool _isAdvancingCreate = false;
  bool _isConfirmingBackup = false;
  bool _createAutoAdvanceEnabled = false;
  String? _error;
  MultisigCreateAdvanceResult? _createProgress;
  MultisigRealtimeLease? _realtimeLease;
  String? _realtimeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(appSecurityProvider).isUnlocked) return;
      _refresh();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted ||
          !ref.read(appSecurityProvider).isUnlocked ||
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
    _releaseRealtimeLease();
    _refreshTimer?.cancel();
    _createAdvanceTimer?.cancel();
    super.dispose();
  }

  MultisigPendingSession? _currentSession() {
    final sessions = ref.read(multisigPendingSessionsProvider).value;
    if (sessions == null) return null;
    return multisigSessionByStorageId(sessions, widget.sessionStorageId) ??
        multisigSessionById(sessions, widget.sessionStorageId);
  }

  void _scheduleCreateAdvancePoll() {
    _createAdvanceTimer?.cancel();
    if (!_createAutoAdvanceEnabled) return;
    _createAdvanceTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_createAutoAdvanceEnabled) return;
      if (_isRefreshing ||
          _isLocking ||
          _isAdvancingCreate ||
          _isConfirmingBackup) {
        _scheduleCreateAdvancePoll();
        return;
      }
      final session = _currentSession();
      if (session == null || session.state != 'request_create') {
        _createAutoAdvanceEnabled = false;
        return;
      }
      unawaited(_advanceCreate(session, automatic: true));
    });
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
      final session = _currentSession();
      setState(() {
        _isRefreshing = false;
        _error = null;
      });
      if (session?.state == 'request_create' && _createAutoAdvanceEnabled) {
        _scheduleCreateAdvancePoll();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        if (!silent) _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _lockRoster(MultisigPendingSession session) async {
    if (_isLocking) return;
    setState(() {
      _isLocking = true;
      _error = null;
    });
    try {
      await ref
          .read(multisigPendingSessionsProvider.notifier)
          .lockSession(storageId: session.storageId);
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

  Future<void> _advanceCreate(
    MultisigPendingSession session, {
    bool automatic = false,
  }) async {
    if (_isAdvancingCreate) return;
    _createAdvanceTimer?.cancel();
    setState(() {
      if (!automatic) _createAutoAdvanceEnabled = true;
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
        _createAutoAdvanceEnabled = progress.session.state == 'request_create';
        _createProgress = progress;
        _error = null;
      });
      _scheduleCreateAdvancePoll();
    } catch (e) {
      if (!mounted) return;
      // Transient failures (network, expired auth, 409/429) must not halt
      // the automatic create loop: the other participants keep waiting on
      // this one. Advance is idempotent, so keep polling and surface the
      // error; only unretryable local failures stop the loop.
      final retryable = MultisigOperationException.from(e).retryable;
      setState(() {
        _createAutoAdvanceEnabled = _createAutoAdvanceEnabled && retryable;
        _isAdvancingCreate = false;
        _error = friendlyMultisigError(e);
      });
      _scheduleCreateAdvancePoll();
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
      final security = ref.read(appSecurityProvider);
      final hasAccounts =
          ref.read(accountProvider).value?.accounts.isNotEmpty ?? false;
      if (!hasAccounts && !security.isPasswordConfigured) {
        context.go(
          '/multisig/set-password',
          extra: SetPasswordScreenArgs.multisigFinalize(
            sessionStorageId: session.storageId,
            sessionId: session.sessionId,
            backupArtifactJson: completion.backupArtifactJson,
            backupPassphrase: completion.backupPassphrase,
          ),
        );
        return;
      }

      await runWithSyncPausedForAccountMutation(ref, () async {
        await ref
            .read(accountProvider.notifier)
            .finalizeMultisigAccount(
              session.storageId,
              backupArtifactJson: completion.backupArtifactJson,
              backupPassphrase: completion.backupPassphrase,
            );
      });
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConfirmingBackup = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _copyInviteCode(String inviteCode) async {
    await Clipboard.setData(ClipboardData(text: inviteCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
  }

  void _syncRealtimeLease(MultisigPendingSession? session, bool isUnlocked) {
    if (!isUnlocked || session == null || !session.isPending) {
      _releaseRealtimeLease();
      return;
    }

    final target = MultisigRealtimeTarget.fromPendingSession(session);
    final key = target.connectionKey;
    final notifier = ref.read(multisigRealtimeProvider.notifier);
    if (_realtimeKey == key && notifier.updateTarget(target)) {
      return;
    }

    _releaseRealtimeLease();
    _realtimeKey = key;
    _realtimeLease = notifier.acquire(target, reason: 'setup');
  }

  void _releaseRealtimeLease() {
    _realtimeLease?.dispose();
    _realtimeLease = null;
    _realtimeKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(appSecurityProvider);
    final sessionsAsync = ref.watch(multisigPendingSessionsProvider);
    final summaries = ref.watch(multisigPendingSessionSummariesProvider).value;
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
    final summary = summaries == null
        ? null
        : _summaryByStorageId(summaries, widget.sessionStorageId) ??
              _summaryBySessionId(summaries, widget.sessionStorageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRealtimeLease(session, security.isUnlocked);
    });

    final refreshButton = session == null || !security.isUnlocked
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
          );

    final content = !security.isUnlocked
        ? _UnlockSessionContent(
            onUnlocked: () async {
              ref.invalidate(multisigPendingSessionsProvider);
              ref.invalidate(multisigPendingSessionSummariesProvider);
              await ref.read(multisigPendingSessionsProvider.future);
            },
          )
        : sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _EmptyState(message: error.toString()),
            data: (_) {
              if (session == null) {
                return const _EmptyState(message: 'Session not found.');
              }
              return _SessionContent(
                session: session,
                isLocking: _isLocking,
                isAdvancingCreate: _isAdvancingCreate,
                isConfirmingBackup: _isConfirmingBackup,
                createProgress: _createProgress,
                error: _error,
                onCopyInviteCode: () => _copyInviteCode(session.inviteCode),
                onLockRoster: () => _lockRoster(session),
                onAdvanceCreate: () => _advanceCreate(session),
                onConfirmBackup: (completion) =>
                    _confirmBackup(session, completion),
              );
            },
          );

    return MultisigOnboardingTrailingPane(
      backTarget: const OnboardingBackTarget.route(
        label: 'Connect multisig',
        routePath: '/multisig/connect',
      ),
      bodyPadding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MultisigOnboardingTitle(
                      title: 'Multisig setup',
                      subtitle:
                          session?.displayLabel ??
                          summary?.displayLabel ??
                          'Session state is stored locally after create or join.',
                      iconName: AppIcons.users,
                    ),
                  ),
                  if (refreshButton != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    refreshButton,
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockSessionContent extends ConsumerStatefulWidget {
  const _UnlockSessionContent({required this.onUnlocked});

  final Future<void> Function() onUnlocked;

  @override
  ConsumerState<_UnlockSessionContent> createState() =>
      _UnlockSessionContentState();
}

class _UnlockSessionContentState extends ConsumerState<_UnlockSessionContent> {
  final _securityGateController = MultisigSetupSecurityGateController();
  bool _showValidation = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _securityGateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final security = ref.read(appSecurityProvider);
    if (!_securityGateController.isValid(security)) {
      setState(() {
        _showValidation = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _securityGateController.runWithOpenSession(
        ref: ref,
        security: security,
        action: widget.onUnlocked,
      );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(appSecurityProvider);
    final colors = context.colors;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MultisigSetupSecurityGate(
                controller: _securityGateController,
                security: security,
                showValidation: _showValidation,
                enabled: !_isSubmitting,
                onChanged: () {
                  setState(() {
                    _error = null;
                  });
                },
                onSubmitted: _submit,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                onPressed: _isSubmitting ? null : _submit,
                minWidth: 180,
                leading: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppIcons.lock),
                child: Text(_isSubmitting ? 'Unlocking...' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionContent extends StatelessWidget {
  const _SessionContent({
    required this.session,
    required this.isLocking,
    required this.isAdvancingCreate,
    required this.isConfirmingBackup,
    required this.createProgress,
    required this.error,
    required this.onCopyInviteCode,
    required this.onLockRoster,
    required this.onAdvanceCreate,
    required this.onConfirmBackup,
  });

  final MultisigPendingSession session;
  final bool isLocking;
  final bool isAdvancingCreate;
  final bool isConfirmingBackup;
  final MultisigCreateAdvanceResult? createProgress;
  final String? error;
  final VoidCallback onCopyInviteCode;
  final VoidCallback onLockRoster;
  final VoidCallback onAdvanceCreate;
  final ValueChanged<MultisigBackupCompletion> onConfirmBackup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final targetParticipantCount = session.targetParticipantCount;
    final canLock =
        session.isCreator &&
        session.state == 'collecting' &&
        session.participants.length == targetParticipantCount;
    final showBackupPanel = session.state == 'ready';
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InviteCodePanel(session: session, onCopy: onCopyInviteCode),
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
                      canLock ? 'Ready to start' : 'Waiting for participants',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${session.participants.length} of $targetParticipantCount participants joined. '
                      '${session.policyLabel} approvals will be required to send.',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
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
                      child: const Text('Start key generation'),
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

class _InviteCodePanel extends StatelessWidget {
  const _InviteCodePanel({required this.session, required this.onCopy});

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
                    'Invite code',
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SelectableText(
                    session.inviteCode,
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

MultisigPendingSessionSummary? _summaryByStorageId(
  List<MultisigPendingSessionSummary> summaries,
  String storageId,
) {
  for (final summary in summaries) {
    if (summary.storageId == storageId) return summary;
  }
  return null;
}

MultisigPendingSessionSummary? _summaryBySessionId(
  List<MultisigPendingSessionSummary> summaries,
  String sessionId,
) {
  for (final summary in summaries) {
    if (summary.sessionId == sessionId) return summary;
  }
  return null;
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
                  '${session.participants.length} of ${session.targetParticipantCount}',
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
