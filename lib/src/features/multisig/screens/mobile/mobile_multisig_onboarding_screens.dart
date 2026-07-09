import 'dart:async';

import 'package:flutter/material.dart'
    show CircularProgressIndicator, SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/security/password_policy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../core/widgets/password_text_field.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/multisig_account_material_provider.dart';
import '../../../../providers/multisig_operation_error.dart';
import '../../../../providers/multisig_pending_session_provider.dart';
import '../../../../providers/multisig_realtime_provider.dart';
import '../../../../providers/wallet_mutation_guard.dart';
import '../../../../rust/api/multisig.dart' as rust_multisig;
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/mobile_onboarding_scaffold.dart';
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../../onboarding/shared/onboarding_error_messages.dart';
import '../../../onboarding/shared/onboarding_flow_args.dart';
import '../../services/multisig_backup_file_service.dart';
import '../../widgets/multisig_backup_wizard.dart';

const _connectProgress = 0.18;
const _sessionSetupProgress = 0.36;
const _backupProgress = 0.72;

class MobileMultisigConnectScreen extends ConsumerStatefulWidget {
  const MobileMultisigConnectScreen({super.key});

  @override
  ConsumerState<MobileMultisigConnectScreen> createState() =>
      _MobileMultisigConnectScreenState();
}

class _MobileMultisigConnectScreenState
    extends ConsumerState<MobileMultisigConnectScreen> {
  final _backupPasswordController = TextEditingController();
  bool _isPickingBackup = false;
  bool _isRestoringBackup = false;
  bool _restoreNeedsUnlock = false;
  MultisigBackupFileReadResult? _selectedBackup;
  String? _restoreError;

  bool get _busy => _isPickingBackup || _isRestoringBackup;

  String? get _restorePasswordMessage =>
      validateWalletPassword(_backupPasswordController.text);

  bool get _restorePasswordValid =>
      isWalletPasswordValid(_backupPasswordController.text);

  @override
  void dispose() {
    _backupPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickBackup() async {
    if (_busy) return;
    setState(() {
      _isPickingBackup = true;
      _restoreError = null;
    });
    try {
      final selected = await ref.read(multisigBackupFileReaderProvider)();
      if (!mounted) return;
      setState(() {
        _selectedBackup = selected ?? _selectedBackup;
        if (selected != null) {
          _backupPasswordController.clear();
          _restoreNeedsUnlock = false;
        }
        _isPickingBackup = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPickingBackup = false;
        _restoreError = e.toString();
      });
    }
  }

  Future<void> _restoreBackup() async {
    final backup = _selectedBackup;
    if (_busy || backup == null) return;
    final passwordMessage = validateRequiredWalletPassword(
      _backupPasswordController.text,
    );
    if (passwordMessage != null) {
      setState(() => _restoreError = passwordMessage);
      return;
    }
    setState(() {
      _isRestoringBackup = true;
      _restoreError = null;
    });
    try {
      final security = ref.read(appSecurityProvider);
      final hasAccounts =
          ref.read(accountProvider).value?.accounts.isNotEmpty ?? false;
      if (security.requiresUnlock) {
        if (!mounted) return;
        setState(() {
          _isRestoringBackup = false;
          _restoreNeedsUnlock = true;
        });
        return;
      }

      final passphrase = rust_multisig.normalizeMultisigBackupPassword(
        password: _backupPasswordController.text,
        minLength: kWalletPasswordMinLength,
      );
      if (!hasAccounts && !security.isPasswordConfigured) {
        if (!mounted) return;
        context.push(
          '/multisig/set-password',
          extra: SetPasswordScreenArgs.multisigRestore(
            backupArtifactJson: backup.artifactJson,
            backupPassphrase: passphrase,
            backupFilePath: backup.path,
            coordinatorUrl: kDefaultMultisigCoordinatorUrl,
          ),
        );
        return;
      }

      setState(() => _restoreNeedsUnlock = false);
      await _restoreSelectedBackup(backup: backup, passphrase: passphrase);
      if (!mounted) return;
      context.go(hasAccounts ? '/home' : '/onboarding/biometrics');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestoringBackup = false;
        _restoreError = onboardingSubmitErrorMessage(e);
      });
    }
  }

  Future<void> _restoreSelectedBackup({
    required MultisigBackupFileReadResult backup,
    required String passphrase,
  }) {
    return runWithSyncPausedForAccountMutation(ref, () async {
      await ref
          .read(accountProvider.notifier)
          .restoreMultisigAccountFromBackup(
            backupArtifactJson: backup.artifactJson,
            backupPassphrase: passphrase,
            backupFilePath: backup.path,
            coordinatorUrl: kDefaultMultisigCoordinatorUrl,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(multisigPendingSessionSummariesProvider);
    final materials = ref.watch(multisigAccountMaterialsProvider).value;
    final materializedSessionStorageIds = materials == null
        ? const <String>{}
        : materializedMultisigSessionStorageIds(materials);

    return MobileOnboardingStepScaffold(
      progress: _connectProgress,
      title: 'Connect Multisig',
      subtitle: 'Start a shared wallet, continue setup, or restore a backup.',
      onBack: () => context.go('/onboarding/method'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summariesAsync.when(
            loading: () => const _MobileSectionCard(
              iconName: AppIcons.sync,
              title: 'Checking setup',
              body: 'Looking for unfinished multisig sessions on this device.',
              child: Center(child: _SmallSpinner()),
            ),
            error: (error, _) => _InlineError(message: error.toString()),
            data: (summaries) {
              final pendingSummaries = summaries
                  .where(
                    (summary) => multisigSessionSummaryNeedsLocalSetup(
                      summary,
                      materializedSessionStorageIds,
                    ),
                  )
                  .toList(growable: false);

              if (pendingSummaries.isEmpty) return const SizedBox.shrink();

              return _PendingSessionsSection(summaries: pendingSummaries);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileSectionCard(
            iconName: AppIcons.addNew,
            title: 'Create setup',
            body: 'Start a new multisig session and share the invite code.',
            child: AppButton(
              key: const ValueKey('mobile_multisig_connect_create_button'),
              expand: true,
              onPressed: () => context.go('/multisig/create'),
              trailing: const AppIcon(AppIcons.chevronForward),
              child: const Text('Create session'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileSectionCard(
            iconName: AppIcons.link,
            title: 'Join setup',
            body: 'Use an invite code from another participant.',
            child: AppButton(
              key: const ValueKey('mobile_multisig_connect_join_button'),
              expand: true,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go('/multisig/join'),
              trailing: const AppIcon(AppIcons.chevronForward),
              child: const Text('Join session'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileSectionCard(
            iconName: AppIcons.importWallet,
            title: 'Restore backup',
            body: 'Recover this participant from a saved backup file.',
            child: AppButton(
              key: const ValueKey('mobile_multisig_connect_restore_button'),
              expand: true,
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : _pickBackup,
              leading: _isPickingBackup
                  ? const _SmallSpinner()
                  : const AppIcon(AppIcons.importWallet),
              child: Text(_isPickingBackup ? 'Choosing backup' : 'Choose file'),
            ),
          ),
          if (_selectedBackup != null || _restoreError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _RestoreBackupPanel(
              selectedBackup: _selectedBackup,
              passwordController: _backupPasswordController,
              passwordMessage: _restorePasswordMessage,
              canRestore: _restorePasswordValid,
              busy: _busy,
              error: _restoreError,
              unlockContent: _restoreNeedsUnlock
                  ? _MobilePasscodeUnlockCard(
                      title: 'Unlock secure storage',
                      body: 'Enter your passcode to restore this backup.',
                      onUnlocked: _restoreBackup,
                    )
                  : null,
              onPasswordChanged: () {
                setState(() {
                  _restoreError = null;
                  _restoreNeedsUnlock = false;
                });
              },
              onChooseFile: _pickBackup,
              onRestore: _restoreBackup,
            ),
          ],
        ],
      ),
    );
  }
}

class MobileMultisigCreateSessionScreen extends ConsumerStatefulWidget {
  const MobileMultisigCreateSessionScreen({super.key});

  @override
  ConsumerState<MobileMultisigCreateSessionScreen> createState() =>
      _MobileMultisigCreateSessionScreenState();
}

class _MobileMultisigCreateSessionScreenState
    extends ConsumerState<MobileMultisigCreateSessionScreen> {
  late final TextEditingController _coordinatorController;
  late final FocusNode _coordinatorFocus;
  int _participantCount = 3;
  int _threshold = 2;
  bool _isSubmitting = false;
  bool _showValidation = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _coordinatorController = TextEditingController(
      text: kDefaultMultisigCoordinatorUrl,
    );
    _coordinatorFocus = FocusNode();
  }

  @override
  void dispose() {
    _coordinatorController.dispose();
    _coordinatorFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final coordinatorUrl = _coordinatorController.text.trim();
    final security = ref.read(appSecurityProvider);
    final hasAccounts =
        ref.read(accountProvider).value?.accounts.isNotEmpty ?? false;
    final needsInitialPasscode = _needsInitialPasscode(
      security: security,
      hasAccounts: hasAccounts,
    );
    final needsPasscodeUnlock =
        !needsInitialPasscode && security.requiresUnlock;
    if (coordinatorUrl.isEmpty || needsPasscodeUnlock) {
      setState(() {
        _showValidation = true;
        _submitError = null;
      });
      return;
    }

    if (needsInitialPasscode) {
      context.push(
        '/multisig/set-password',
        extra: SetPasswordScreenArgs.multisigCreateSession(
          coordinatorUrl: coordinatorUrl,
          participantCount: _participantCount,
          threshold: _threshold,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final pending = await ref
          .read(multisigPendingSessionsProvider.notifier)
          .createSession(
            coordinatorUrl: coordinatorUrl,
            participantCount: _participantCount,
            threshold: _threshold,
          );
      if (!mounted) return;
      context.go('/multisig/session/${Uri.encodeComponent(pending.storageId)}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = friendlyMultisigError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(appSecurityProvider);
    final hasAccounts =
        ref.watch(accountProvider).value?.accounts.isNotEmpty ?? false;
    final needsInitialPasscode = _needsInitialPasscode(
      security: security,
      hasAccounts: hasAccounts,
    );
    final needsPasscodeUnlock =
        !needsInitialPasscode && security.requiresUnlock;
    return MobileOnboardingStepScaffold(
      progress: _sessionSetupProgress,
      title: 'Create Setup',
      subtitle: 'Choose the signer policy before sharing the invite code.',
      titleStyle: AppTypography.displaySmall,
      onBack: () => context.go('/multisig/connect'),
      bottomArea: AppButton(
        key: const ValueKey('mobile_multisig_create_submit_button'),
        expand: true,
        onPressed: _isSubmitting || needsPasscodeUnlock ? null : _submit,
        leading: _isSubmitting
            ? const _SmallSpinner()
            : const AppIcon(AppIcons.addNew),
        trailing: _isSubmitting ? null : const AppIcon(AppIcons.chevronForward),
        child: Text(_isSubmitting ? 'Creating...' : 'Create session'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileFieldLabel(
            label: 'Coordinator',
            error: _showValidation && _coordinatorController.text.trim().isEmpty
                ? 'Enter a coordinator URL.'
                : null,
            child: MobileTextField(
              controller: _coordinatorController,
              focusNode: _coordinatorFocus,
              hintText: kDefaultMultisigCoordinatorUrl,
              leading: const _FieldLeadingIcon(AppIcons.endpoint),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _submitError = null),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileSessionPolicyCard(
            participantCount: _participantCount,
            threshold: _threshold,
            onParticipantCountChanged: (value) {
              setState(() {
                _participantCount = value;
                if (_threshold > value) _threshold = value;
                if (_threshold < 2) _threshold = 2;
                _submitError = null;
              });
            },
            onThresholdChanged: (value) {
              setState(() {
                _threshold = value;
                _submitError = null;
              });
            },
          ),
          if (needsPasscodeUnlock) ...[
            const SizedBox(height: AppSpacing.sm),
            _MobilePasscodeUnlockCard(
              title: 'Unlock secure storage',
              body: 'Enter your passcode to create this multisig setup.',
              onUnlocked: _submit,
            ),
          ],
          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineError(message: _submitError!),
          ],
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }
}

class _MobileSessionPolicyCard extends StatelessWidget {
  const _MobileSessionPolicyCard({
    required this.participantCount,
    required this.threshold,
    required this.onParticipantCountChanged,
    required this.onThresholdChanged,
  });

  final int participantCount;
  final int threshold;
  final ValueChanged<int> onParticipantCountChanged;
  final ValueChanged<int> onThresholdChanged;

  @override
  Widget build(BuildContext context) {
    return _MobileSectionCard(
      iconName: AppIcons.users,
      title: 'Wallet policy',
      body:
          'Any $threshold of $participantCount participants can approve a send.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Signers total',
            style: AppTypography.labelSmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var value = 2; value <= 5; value++)
                _PolicyPill(
                  label: '$value',
                  selected: participantCount == value,
                  onSelected: () => onParticipantCountChanged(value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Approvals to confirm',
            style: AppTypography.labelSmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var value = 2; value <= participantCount; value++)
                _PolicyPill(
                  label: '$value of $participantCount',
                  selected: threshold == value,
                  onSelected: () => onThresholdChanged(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PolicyPill extends StatelessWidget {
  const _PolicyPill({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onSelected,
      size: AppButtonSize.medium,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      child: Text(label),
    );
  }
}

class MobileMultisigJoinSessionScreen extends ConsumerStatefulWidget {
  const MobileMultisigJoinSessionScreen({super.key});

  @override
  ConsumerState<MobileMultisigJoinSessionScreen> createState() =>
      _MobileMultisigJoinSessionScreenState();
}

class _MobileMultisigJoinSessionScreenState
    extends ConsumerState<MobileMultisigJoinSessionScreen> {
  late final TextEditingController _sessionController;
  late final TextEditingController _coordinatorController;
  late final FocusNode _sessionFocus;
  late final FocusNode _coordinatorFocus;
  bool _showError = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _sessionController = TextEditingController();
    _coordinatorController = TextEditingController(
      text: kDefaultMultisigCoordinatorUrl,
    );
    _sessionFocus = FocusNode();
    _coordinatorFocus = FocusNode();
  }

  @override
  void dispose() {
    _sessionController.dispose();
    _coordinatorController.dispose();
    _sessionFocus.dispose();
    _coordinatorFocus.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_isSubmitting) return;
    final inviteCode = _sessionController.text.trim();
    final coordinatorUrl = _coordinatorController.text.trim();
    final security = ref.read(appSecurityProvider);
    String? normalizedInviteCode;
    if (inviteCode.isNotEmpty) {
      try {
        normalizedInviteCode = normalizeMultisigInviteCode(inviteCode);
      } catch (e) {
        setState(() {
          _showError = true;
          _submitError = friendlyMultisigError(e);
        });
        return;
      }
    }
    final hasAccounts =
        ref.read(accountProvider).value?.accounts.isNotEmpty ?? false;
    final needsInitialPasscode = _needsInitialPasscode(
      security: security,
      hasAccounts: hasAccounts,
    );
    final needsPasscodeUnlock =
        !needsInitialPasscode && security.requiresUnlock;
    if (inviteCode.isEmpty || coordinatorUrl.isEmpty || needsPasscodeUnlock) {
      setState(() {
        _showError = true;
        _submitError = null;
      });
      return;
    }

    if (needsInitialPasscode) {
      context.push(
        '/multisig/set-password',
        extra: SetPasswordScreenArgs.multisigJoinSession(
          coordinatorUrl: coordinatorUrl,
          inviteCode: normalizedInviteCode!,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final pending = await ref
          .read(multisigPendingSessionsProvider.notifier)
          .joinSession(
            coordinatorUrl: coordinatorUrl,
            inviteCode: normalizedInviteCode!,
          );
      if (!mounted) return;
      context.go('/multisig/session/${Uri.encodeComponent(pending.storageId)}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = friendlyMultisigError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(appSecurityProvider);
    final hasAccounts =
        ref.watch(accountProvider).value?.accounts.isNotEmpty ?? false;
    final needsInitialPasscode = _needsInitialPasscode(
      security: security,
      hasAccounts: hasAccounts,
    );
    final needsPasscodeUnlock =
        !needsInitialPasscode && security.requiresUnlock;
    return MobileOnboardingStepScaffold(
      progress: _sessionSetupProgress,
      title: 'Join Setup',
      subtitle: 'Enter the invite code shared by the creator.',
      titleStyle: AppTypography.displaySmall,
      onBack: () => context.go('/multisig/connect'),
      bottomArea: AppButton(
        key: const ValueKey('mobile_multisig_join_submit_button'),
        expand: true,
        onPressed: _isSubmitting || needsPasscodeUnlock ? null : _join,
        leading: _isSubmitting
            ? const _SmallSpinner()
            : const AppIcon(AppIcons.link),
        trailing: _isSubmitting ? null : const AppIcon(AppIcons.chevronForward),
        child: Text(_isSubmitting ? 'Joining...' : 'Join session'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileFieldLabel(
            label: 'Invite code',
            error: _showError && _sessionController.text.trim().isEmpty
                ? 'Enter a session ID.'
                : null,
            child: MobileTextField(
              controller: _sessionController,
              focusNode: _sessionFocus,
              hintText: 'Invite code',
              leading: const _FieldLeadingIcon(AppIcons.link),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _submitError = null),
              onSubmitted: (_) => _coordinatorFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileFieldLabel(
            label: 'Coordinator',
            error: _showError && _coordinatorController.text.trim().isEmpty
                ? 'Enter a coordinator URL.'
                : null,
            child: MobileTextField(
              controller: _coordinatorController,
              focusNode: _coordinatorFocus,
              hintText: kDefaultMultisigCoordinatorUrl,
              leading: const _FieldLeadingIcon(AppIcons.endpoint),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _submitError = null),
              onSubmitted: (_) => _join(),
            ),
          ),
          if (needsPasscodeUnlock) ...[
            const SizedBox(height: AppSpacing.sm),
            _MobilePasscodeUnlockCard(
              title: 'Unlock secure storage',
              body: 'Enter your passcode to join this multisig setup.',
              onUnlocked: _join,
            ),
          ],
          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineError(message: _submitError!),
          ],
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }
}

class MobileMultisigSessionScreen extends ConsumerStatefulWidget {
  const MobileMultisigSessionScreen({
    required this.sessionStorageId,
    super.key,
  });

  final String sessionStorageId;

  @override
  ConsumerState<MobileMultisigSessionScreen> createState() =>
      _MobileMultisigSessionScreenState();
}

class _MobileMultisigSessionScreenState
    extends ConsumerState<MobileMultisigSessionScreen> {
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
        context.push(
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
      context.go(hasAccounts ? '/home' : '/onboarding/biometrics');
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
    showAppToast(context, 'Invite code copied');
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
    _realtimeLease = notifier.acquire(target, reason: 'mobile-setup');
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

    return MobileOnboardingStepScaffold(
      progress: _progressForSession(session),
      title: 'Multisig Setup',
      subtitle:
          session?.displayLabel ??
          summary?.displayLabel ??
          'Session state is stored locally after create or join.',
      onBack: () => context.go('/multisig/connect'),
      bottomArea: session == null || !security.isUnlocked
          ? null
          : AppButton(
              expand: true,
              variant: AppButtonVariant.secondary,
              onPressed: _isRefreshing ? null : () => _refresh(),
              leading: _isRefreshing
                  ? const _SmallSpinner()
                  : const AppIcon(AppIcons.sync),
              child: const Text('Refresh'),
            ),
      child: !security.isUnlocked
          ? _MobilePasscodeUnlockCard(
              title: 'Unlock secure storage',
              body: 'Enter your passcode to continue this multisig setup.',
              errorMessage: friendlyMultisigError,
              onUnlocked: () async {
                ref.invalidate(multisigPendingSessionsProvider);
                ref.invalidate(multisigPendingSessionSummariesProvider);
                await ref.read(multisigPendingSessionsProvider.future);
              },
            )
          : sessionsAsync.when(
              loading: () => const Center(child: _SmallSpinner()),
              error: (error, _) => _InlineError(message: error.toString()),
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
            ),
    );
  }
}

class _MobileSectionCard extends StatelessWidget {
  const _MobileSectionCard({
    required this.iconName,
    required this.title,
    required this.body,
    required this.child,
  });

  final String iconName;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardIcon(iconName),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        body,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _PendingSessionsSection extends StatelessWidget {
  const _PendingSessionsSection({required this.summaries});

  final List<MultisigPendingSessionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return _MobileSectionCard(
      iconName: AppIcons.users,
      title: 'Continue setup',
      body: 'Finish a multisig session already saved on this device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < summaries.length; i++) ...[
            _PendingSessionTile(summary: summaries[i]),
            if (i != summaries.length - 1)
              const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _PendingSessionTile extends StatelessWidget {
  const _PendingSessionTile({required this.summary});

  final MultisigPendingSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go(
        '/multisig/session/${Uri.encodeComponent(summary.storageId)}',
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.input,
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${summary.shortSessionId} · ${_statusLabel(summary.state)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(
                AppIcons.chevronForward,
                size: 18,
                color: colors.icon.regular,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String state) => switch (state) {
    'collecting' => 'Collecting',
    'locked' => 'Locked',
    'ready' => 'Ready',
    _ => state,
  };
}

class _RestoreBackupPanel extends StatelessWidget {
  const _RestoreBackupPanel({
    required this.selectedBackup,
    required this.passwordController,
    required this.passwordMessage,
    required this.canRestore,
    required this.busy,
    required this.error,
    required this.unlockContent,
    required this.onPasswordChanged,
    required this.onChooseFile,
    required this.onRestore,
  });

  final MultisigBackupFileReadResult? selectedBackup;
  final TextEditingController passwordController;
  final String? passwordMessage;
  final bool canRestore;
  final bool busy;
  final String? error;
  final Widget? unlockContent;
  final VoidCallback onPasswordChanged;
  final VoidCallback onChooseFile;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final backup = selectedBackup;
    return _MobileSectionCard(
      iconName: AppIcons.key,
      title: 'Backup file',
      body: backup == null
          ? 'No backup selected'
          : _backupFileName(backup.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            onPressed: busy ? null : onChooseFile,
            variant: AppButtonVariant.secondary,
            expand: true,
            leading: const AppIcon(AppIcons.importWallet),
            child: Text(backup == null ? 'Choose file' : 'Change file'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PasswordTextField(
            label: 'Backup password',
            controller: passwordController,
            enabled: !busy,
            hintText: 'Min. $kWalletPasswordMinLength characters and symbols',
            messageText: passwordMessage,
            tone: passwordMessage == null
                ? AppTextFieldTone.neutral
                : AppTextFieldTone.destructive,
            onChanged: (_) => onPasswordChanged(),
            onSubmitted: (_) {
              if (backup != null && !busy && canRestore) onRestore();
            },
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InlineError(message: error!),
          ],
          if (unlockContent != null) ...[
            const SizedBox(height: AppSpacing.sm),
            unlockContent!,
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              onPressed: backup == null || busy || !canRestore
                  ? null
                  : onRestore,
              expand: true,
              leading: busy
                  ? const _SmallSpinner()
                  : const AppIcon(AppIcons.check),
              child: Text(busy ? 'Restoring account' : 'Restore account'),
            ),
          ],
        ],
      ),
    );
  }

  String _backupFileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}

class _MobilePasscodeUnlockCard extends ConsumerStatefulWidget {
  const _MobilePasscodeUnlockCard({
    required this.title,
    required this.body,
    required this.onUnlocked,
    this.errorMessage = onboardingSubmitErrorMessage,
  });

  final String title;
  final String body;
  final Future<void> Function() onUnlocked;
  final String Function(Object error) errorMessage;

  @override
  ConsumerState<_MobilePasscodeUnlockCard> createState() =>
      _MobilePasscodeUnlockCardState();
}

class _MobilePasscodeUnlockCardState
    extends ConsumerState<_MobilePasscodeUnlockCard> {
  var _entry = '';
  var _submitting = false;
  String? _error;

  void _onDigit(int digit) {
    if (_submitting || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_submitting || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    if (_submitting || _entry.length != kMobilePasscodeLength) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .unlock(_entry);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _submitting = false;
          _entry = '';
          _error = 'Incorrect Passcode';
        });
        return;
      }
      await widget.onUnlocked();
      if (!mounted) return;
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _entry = '';
        _error = widget.errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: AppTypography.labelLarge.copyWith(color: colors.text.primary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          widget.body,
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: kPasscodePromptDigitsHeight,
          child: PasscodePromptField(
            length: kMobilePasscodeLength,
            filled: _entry.length,
            error: _error,
            minGap: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        PasscodeNumpad(
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          canDelete: _entry.isNotEmpty,
          enabled: !_submitting,
        ),
      ],
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
    final targetParticipantCount = session.targetParticipantCount;
    final canLock =
        session.isCreator &&
        session.state == 'collecting' &&
        session.participants.length == targetParticipantCount;
    final showBackupPanel = session.state == 'ready';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InviteCodePanel(session: session, onCopy: onCopyInviteCode),
        const SizedBox(height: AppSpacing.sm),
        _ProgressPanel(session: session),
        const SizedBox(height: AppSpacing.sm),
        _ParticipantsPanel(session: session),
        const SizedBox(height: AppSpacing.sm),
        if (session.state == 'collecting') ...[
          _MobileSectionCard(
            iconName: AppIcons.lock,
            title: canLock ? 'Ready to start' : 'Waiting for participants',
            body:
                '${session.participants.length} of $targetParticipantCount participants joined. '
                '${session.policyLabel} approvals will be required to send.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  onPressed: canLock && !isLocking ? onLockRoster : null,
                  expand: true,
                  leading: isLocking
                      ? const _SmallSpinner()
                      : const AppIcon(AppIcons.lock),
                  child: const Text('Start key generation'),
                ),
              ],
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
          const SizedBox(height: AppSpacing.sm),
          _InlineError(message: error!),
        ],
      ],
    );
  }
}

class _InviteCodePanel extends StatelessWidget {
  const _InviteCodePanel({required this.session, required this.onCopy});

  final MultisigPendingSession session;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _MobileSectionCard(
      iconName: AppIcons.link,
      title: 'Invite code',
      body: 'Share this code with the other participants.',
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              session.inviteCode,
              maxLines: 2,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppButton(
            onPressed: onCopy,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            leading: const AppIcon(AppIcons.copy),
            child: const Text('Copy'),
          ),
        ],
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
      ('collecting', 'People'),
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
          if (index < states.length - 1) const SizedBox(width: AppSpacing.xxs),
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
        : colors.surface.input;
    final text = complete || active ? colors.text.accent : colors.text.muted;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    return _MobileSectionCard(
      iconName: AppIcons.users,
      title: 'Participants',
      body:
          '${session.participants.length} of ${session.targetParticipantCount} joined',
      child: Column(
        children: [
          for (final participant in session.participants)
            _ParticipantRow(
              participant: participant,
              creator:
                  participant.participantId == session.creatorParticipantId,
              local: participant.participantId == session.participantId,
            ),
        ],
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
    final total = session.participants.length;
    final backendDone = session.participants
        .where((participant) => participant.dkgCompleted)
        .length;
    return _MobileSectionCard(
      iconName: AppIcons.sync,
      title: 'Create account',
      body: progress?.detail ?? 'Ready to continue local setup.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: AppSpacing.sm),
          _MiniBadge(label: '$backendDone of $total done'),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: isAdvancing ? null : onAdvance,
            expand: true,
            leading: isAdvancing
                ? const _SmallSpinner()
                : const AppIcon(AppIcons.sync),
            child: Text(progress == null ? 'Start create' : 'Continue'),
          ),
        ],
      ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '$value/$total',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
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
    final badges = [
      if (local) 'You',
      if (creator) 'Creator',
      if (participant.dkgCompleted) 'Ready',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          _CardIcon(AppIcons.user),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  participant.shortParticipantId,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (badges.isNotEmpty) _MiniBadge(label: badges.join(' · ')),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _MobileFieldLabel extends StatelessWidget {
  const _MobileFieldLabel({
    required this.label,
    required this.child,
    this.error,
  });

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: error == null
                ? colors.text.primary
                : colors.text.destructive,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        child,
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            error!,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldLeadingIcon extends StatelessWidget {
  const _FieldLeadingIcon(this.iconName);

  final String iconName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: AppIcon(
        iconName,
        color: context.colors.icon.regular,
        size: AppIconSize.medium,
      ),
    );
  }
}

class _CardIcon extends StatelessWidget {
  const _CardIcon(this.iconName);

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.state.selectedOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: AppIcon(iconName, size: 20, color: colors.icon.accent),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.destructive,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _MobileSectionCard(
      iconName: AppIcons.warning,
      title: 'Nothing to show',
      body: message,
      child: const SizedBox.shrink(),
    );
  }
}

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

double _progressForSession(MultisigPendingSession? session) {
  if (session == null) return _sessionSetupProgress;
  if (session.state == 'ready' && !multisigLocalBackupCompleted(session)) {
    return _backupProgress;
  }
  return switch (session.state) {
    'collecting' => 0.48,
    'request_create' => 0.6,
    'ready' => 0.9,
    _ => _sessionSetupProgress,
  };
}

bool _needsInitialPasscode({
  required AppSecurityState security,
  required bool hasAccounts,
}) {
  return !hasAccounts && !security.isPasswordConfigured;
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
