import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/multisig_pending_session_provider.dart';

const _contentWidth = 820.0;
const _formGap = AppSpacing.sm;

class MultisigSessionsScreen extends ConsumerStatefulWidget {
  const MultisigSessionsScreen({super.key});

  @override
  ConsumerState<MultisigSessionsScreen> createState() =>
      _MultisigSessionsScreenState();
}

class _MultisigSessionsScreenState
    extends ConsumerState<MultisigSessionsScreen> {
  late final TextEditingController _coordinatorController;
  final _createLabelController = TextEditingController();
  final _joinSessionIdController = TextEditingController();
  final _joinLabelController = TextEditingController();
  final _thresholdDrafts = <String, int>{};

  bool _creating = false;
  bool _joining = false;
  String? _busyStorageId;
  String? _errorMessage;

  bool get _mutationInProgress =>
      _creating || _joining || _busyStorageId != null;

  @override
  void initState() {
    super.initState();
    _coordinatorController = TextEditingController(
      text: kDefaultMultisigCoordinatorUrl,
    );
  }

  @override
  void dispose() {
    _coordinatorController.dispose();
    _createLabelController.dispose();
    _joinSessionIdController.dispose();
    _joinLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(multisigPendingSessionsProvider);
    final actionsEnabled = !_mutationInProgress;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(
            key: ValueKey('multisig_sessions_pane_toolbar'),
            leading: AppRouteBackLink(
              key: ValueKey('multisig_sessions_back_button'),
              minWidth: 60,
            ),
          ),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Multisig setup',
                      style: AppTypography.headlineLarge.copyWith(
                        color: context.colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _SessionForms(
                      coordinatorController: _coordinatorController,
                      createLabelController: _createLabelController,
                      joinSessionIdController: _joinSessionIdController,
                      joinLabelController: _joinLabelController,
                      creating: _creating,
                      joining: _joining,
                      actionsEnabled: actionsEnabled,
                      onCreate: () => unawaited(_createSession()),
                      onJoin: () => unawaited(_joinSession()),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _InlineError(message: _errorMessage!),
                    ],
                    const SizedBox(height: AppSpacing.base),
                    sessionsAsync.when(
                      loading: () => const _LoadingSessions(),
                      error: (error, _) =>
                          _InlineError(message: _errorText(error)),
                      data: _buildSessions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessions(List<MultisigPendingSession> sessions) {
    if (sessions.isEmpty) return const _EmptySessions();
    final actionsEnabled = !_mutationInProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sessions.length; index += 1) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          _SessionCard(
            session: sessions[index],
            threshold: _thresholdFor(sessions[index]),
            busy: _busyStorageId == sessions[index].storageId,
            actionsEnabled: actionsEnabled,
            onThresholdChanged: (threshold) {
              setState(() {
                _thresholdDrafts[sessions[index].storageId] = threshold;
              });
            },
            onCopySessionId: () => unawaited(_copySessionId(sessions[index])),
            onRefreshSession: () => unawaited(
              _withSessionOperation(
                sessions[index],
                (notifier, session) =>
                    notifier.refreshSession(session.storageId),
              ),
            ),
            onRefreshAuth: () => unawaited(
              _withSessionOperation(
                sessions[index],
                (notifier, session) => notifier.refreshAuth(session.storageId),
              ),
            ),
            onResume: () => unawaited(
              _withSessionOperation(
                sessions[index],
                (notifier, session) =>
                    notifier.resumeParticipant(session.storageId),
              ),
            ),
            onLock: () => unawaited(_lockSession(sessions[index])),
            onDelete: () => unawaited(
              _withSessionOperation(
                sessions[index],
                (notifier, session) => notifier.delete(session.storageId),
                successMessage: 'Session deleted',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createSession() async {
    if (_mutationInProgress) return;
    setState(() {
      _creating = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(multisigPendingSessionsProvider.notifier)
          .createSession(
            coordinatorUrl: _coordinatorController.text,
            label: _optionalText(_createLabelController),
          );
      if (!mounted) return;
      _createLabelController.clear();
      showAppToast(context, 'Session created');
    } catch (error) {
      _setError(error);
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _joinSession() async {
    if (_mutationInProgress) return;
    setState(() {
      _joining = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(multisigPendingSessionsProvider.notifier)
          .joinSession(
            coordinatorUrl: _coordinatorController.text,
            sessionId: _joinSessionIdController.text,
            label: _optionalText(_joinLabelController),
          );
      if (!mounted) return;
      _joinSessionIdController.clear();
      _joinLabelController.clear();
      showAppToast(context, 'Session joined');
    } catch (error) {
      _setError(error);
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
        });
      }
    }
  }

  Future<void> _lockSession(MultisigPendingSession session) {
    final threshold = _thresholdFor(session);
    return _withSessionOperation(
      session,
      (notifier, pending) => notifier.lockSession(
        storageId: pending.storageId,
        threshold: threshold,
      ),
      successMessage: 'Session locked',
    );
  }

  Future<void> _withSessionOperation(
    MultisigPendingSession session,
    FutureOr<Object?> Function(
      MultisigPendingSessionsNotifier notifier,
      MultisigPendingSession session,
    )
    operation, {
    String? successMessage,
  }) async {
    if (_mutationInProgress) return;
    setState(() {
      _busyStorageId = session.storageId;
      _errorMessage = null;
    });
    try {
      await operation(
        ref.read(multisigPendingSessionsProvider.notifier),
        session,
      );
      if (!mounted || successMessage == null) return;
      showAppToast(context, successMessage);
    } catch (error) {
      _setError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busyStorageId = null;
        });
      }
    }
  }

  Future<void> _copySessionId(MultisigPendingSession session) async {
    await Clipboard.setData(ClipboardData(text: session.sessionId));
    if (!mounted) return;
    showAppToast(context, 'Session ID copied');
  }

  int _thresholdFor(MultisigPendingSession session) {
    final participantCount = math.max(1, session.participants.length);
    final value =
        _thresholdDrafts[session.storageId] ??
        session.threshold ??
        math.min(2, participantCount);
    return math.min(math.max(1, value), participantCount);
  }

  void _setError(Object error) {
    if (!mounted) return;
    setState(() {
      _errorMessage = _errorText(error);
    });
  }
}

class _SessionForms extends StatelessWidget {
  const _SessionForms({
    required this.coordinatorController,
    required this.createLabelController,
    required this.joinSessionIdController,
    required this.joinLabelController,
    required this.creating,
    required this.joining,
    required this.actionsEnabled,
    required this.onCreate,
    required this.onJoin,
  });

  final TextEditingController coordinatorController;
  final TextEditingController createLabelController;
  final TextEditingController joinSessionIdController;
  final TextEditingController joinLabelController;
  final bool creating;
  final bool joining;
  final bool actionsEnabled;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        final createPanel = _CreateSessionPanel(
          labelController: createLabelController,
          creating: creating,
          actionsEnabled: actionsEnabled,
          onCreate: onCreate,
        );
        final joinPanel = _JoinSessionPanel(
          sessionIdController: joinSessionIdController,
          labelController: joinLabelController,
          joining: joining,
          actionsEnabled: actionsEnabled,
          onJoin: onJoin,
        );
        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CoordinatorPanel(controller: coordinatorController),
              const SizedBox(height: _formGap),
              createPanel,
              const SizedBox(height: _formGap),
              joinPanel,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CoordinatorPanel(controller: coordinatorController),
            const SizedBox(height: _formGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: createPanel),
                const SizedBox(width: _formGap),
                Expanded(child: joinPanel),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CoordinatorPanel extends StatelessWidget {
  const _CoordinatorPanel({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _ActionSurface(
      child: AppTextField(
        key: const ValueKey('multisig_coordinator_field'),
        label: 'Coordinator URL',
        controller: controller,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        showClearButton: true,
      ),
    );
  }
}

class _CreateSessionPanel extends StatelessWidget {
  const _CreateSessionPanel({
    required this.labelController,
    required this.creating,
    required this.actionsEnabled,
    required this.onCreate,
  });

  final TextEditingController labelController;
  final bool creating;
  final bool actionsEnabled;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _ActionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SurfaceTitle(iconName: AppIcons.plus, label: 'Create session'),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const ValueKey('multisig_create_label_field'),
            label: 'Label',
            controller: labelController,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            showClearButton: true,
            onSubmitted: actionsEnabled ? (_) => onCreate() : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const ValueKey('multisig_create_session_button'),
              onPressed: actionsEnabled ? onCreate : null,
              size: AppButtonSize.medium,
              leading: AppIcon(
                creating ? AppIcons.loader : AppIcons.plus,
                animated: creating,
              ),
              child: Text(creating ? 'Creating' : 'Create'),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinSessionPanel extends StatelessWidget {
  const _JoinSessionPanel({
    required this.sessionIdController,
    required this.labelController,
    required this.joining,
    required this.actionsEnabled,
    required this.onJoin,
  });

  final TextEditingController sessionIdController;
  final TextEditingController labelController;
  final bool joining;
  final bool actionsEnabled;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return _ActionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SurfaceTitle(iconName: AppIcons.link, label: 'Join session'),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const ValueKey('multisig_join_session_id_field'),
            label: 'Session ID',
            controller: sessionIdController,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            showClearButton: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            key: const ValueKey('multisig_join_label_field'),
            label: 'Label',
            controller: labelController,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            showClearButton: true,
            onSubmitted: actionsEnabled ? (_) => onJoin() : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const ValueKey('multisig_join_session_button'),
              onPressed: actionsEnabled ? onJoin : null,
              size: AppButtonSize.medium,
              leading: AppIcon(
                joining ? AppIcons.loader : AppIcons.link,
                animated: joining,
              ),
              child: Text(joining ? 'Joining' : 'Join'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.threshold,
    required this.busy,
    required this.actionsEnabled,
    required this.onThresholdChanged,
    required this.onCopySessionId,
    required this.onRefreshSession,
    required this.onRefreshAuth,
    required this.onResume,
    required this.onLock,
    required this.onDelete,
  });

  final MultisigPendingSession session;
  final int threshold;
  final bool busy;
  final bool actionsEnabled;
  final ValueChanged<int> onThresholdChanged;
  final VoidCallback onCopySessionId;
  final VoidCallback onRefreshSession;
  final VoidCallback onRefreshAuth;
  final VoidCallback onResume;
  final VoidCallback onLock;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final participantCount = session.participants.length;
    final canLock =
        session.isCreator &&
        session.state == 'collecting' &&
        participantCount > 1;
    return _ActionSurface(
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
                      session.displayLabel,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineSmall.copyWith(
                        color: context.colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${_roleLabel(session.role)} - ${session.shortSessionId}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SessionStateBadge(state: session.state),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DetailPill(label: 'Participants', value: '$participantCount'),
              _DetailPill(label: 'Threshold', value: _thresholdLabel(session)),
              _DetailPill(label: 'Updated', value: _formatLocalTime(session)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ParticipantList(participants: session.participants),
          const SizedBox(height: AppSpacing.sm),
          if (session.isCreator && session.state == 'collecting') ...[
            _ThresholdControl(
              participantCount: participantCount,
              threshold: threshold,
              enabled: actionsEnabled && participantCount > 1,
              onChanged: onThresholdChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _SmallActionButton(
                iconName: AppIcons.copy,
                label: 'Copy session ID',
                onPressed: actionsEnabled ? onCopySessionId : null,
              ),
              _SmallActionButton(
                iconName: AppIcons.sync,
                label: 'Refresh',
                onPressed: actionsEnabled ? onRefreshSession : null,
              ),
              _SmallActionButton(
                iconName: AppIcons.key,
                label: 'Refresh auth',
                onPressed: actionsEnabled ? onRefreshAuth : null,
              ),
              _SmallActionButton(
                iconName: AppIcons.renew,
                label: 'Resume',
                onPressed: actionsEnabled ? onResume : null,
              ),
              if (canLock)
                _SmallActionButton(
                  iconName: AppIcons.lock,
                  label: 'Lock roster',
                  onPressed: actionsEnabled ? onLock : null,
                ),
              _SmallActionButton(
                iconName: AppIcons.trash,
                label: 'Delete',
                destructive: true,
                onPressed: actionsEnabled ? onDelete : null,
              ),
              if (busy) const _BusyIndicator(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThresholdControl extends StatelessWidget {
  const _ThresholdControl({
    required this.participantCount,
    required this.threshold,
    required this.enabled,
    required this.onChanged,
  });

  final int participantCount;
  final int threshold;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Threshold',
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            for (
              var value = 1;
              value <= math.max(1, participantCount);
              value += 1
            )
              AppButton(
                key: ValueKey('multisig_threshold_$value'),
                onPressed: enabled ? () => onChanged(value) : null,
                variant: threshold == value
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                size: AppButtonSize.small,
                minWidth: 32,
                child: Text('$value'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.participants});

  final List<MultisigPendingParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Column(
        children: [
          for (var index = 0; index < participants.length; index += 1) ...[
            if (index > 0)
              DecoratedBox(
                decoration: BoxDecoration(color: colors.border.subtle),
                child: const SizedBox(height: 1),
              ),
            _ParticipantRow(participant: participants[index]),
          ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final MultisigPendingParticipant participant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.user, size: 16, color: colors.icon.regular),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              participant.displayName,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            participant.dkgCompleted ? 'DKG done' : 'Waiting',
            style: AppTypography.labelMedium.copyWith(
              color: participant.dkgCompleted
                  ? colors.text.success
                  : colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          '$label: $value',
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _SessionStateBadge extends StatelessWidget {
  const _SessionStateBadge({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = switch (state) {
      'ready' => (
        bg: colors.background.utilitySuccessAlpha,
        text: colors.text.success,
      ),
      'failed' => (
        bg: colors.background.utilityDestructiveAlpha,
        text: colors.text.destructive,
      ),
      'locked' => (
        bg: colors.background.brandCrimsonAlpha,
        text: colors.text.brandCrimson,
      ),
      _ => (
        bg: colors.background.neutralSubtleOpacity,
        text: colors.text.secondary,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          _stateLabel(state),
          style: AppTypography.labelMedium.copyWith(color: palette.text),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.iconName,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String iconName;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onPressed,
      variant: destructive
          ? AppButtonVariant.destructive
          : AppButtonVariant.secondary,
      size: AppButtonSize.small,
      leading: AppIcon(iconName),
      child: Text(label),
    );
  }
}

class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.loader,
              animated: true,
              size: 16,
              color: context.colors.icon.regular,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'Working',
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSurface extends StatelessWidget {
  const _ActionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: child,
      ),
    );
  }
}

class _SurfaceTitle extends StatelessWidget {
  const _SurfaceTitle({required this.iconName, required this.label});

  final String iconName;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(iconName, size: 18, color: context.colors.icon.regular),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.utilityDestructiveAlphaSubtle,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.utilityDestructiveSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.destructive,
          ),
        ),
      ),
    );
  }
}

class _LoadingSessions extends StatelessWidget {
  const _LoadingSessions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.loader,
              animated: true,
              color: context.colors.icon.regular,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Loading sessions',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return _ActionSurface(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            'No pending sessions',
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

String? _optionalText(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

String _errorText(Object error) {
  if (error is FormatException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return error.toString();
}

String _roleLabel(MultisigPendingRole role) {
  return switch (role) {
    MultisigPendingRole.creator => 'Creator',
    MultisigPendingRole.participant => 'Participant',
  };
}

String _stateLabel(String state) {
  return switch (state) {
    'collecting' => 'Collecting',
    'locked' => 'Locked',
    'ready' => 'Ready',
    'failed' => 'Failed',
    _ => state,
  };
}

String _thresholdLabel(MultisigPendingSession session) {
  final threshold = session.threshold;
  if (threshold == null) return 'Not set';
  return '$threshold of ${session.participants.length}';
}

String _formatLocalTime(MultisigPendingSession session) {
  final time = DateTime.fromMillisecondsSinceEpoch(
    session.updatedLocallyAt,
  ).toLocal();
  return '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
