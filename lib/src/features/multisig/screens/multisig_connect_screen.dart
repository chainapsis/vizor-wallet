import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/multisig.dart' as rust_multisig;
import '../../onboarding/shared/onboarding_error_messages.dart';
import '../../onboarding/shared/onboarding_flow_args.dart';
import '../services/multisig_backup_file_service.dart';
import '../widgets/multisig_onboarding_flow.dart';

class MultisigConnectScreen extends ConsumerStatefulWidget {
  const MultisigConnectScreen({super.key});

  @override
  ConsumerState<MultisigConnectScreen> createState() =>
      _MultisigConnectScreenState();
}

class _MultisigConnectScreenState extends ConsumerState<MultisigConnectScreen> {
  final _backupPasswordController = TextEditingController();
  bool _restoreGeneratedPassword = true;
  bool _isPickingBackup = false;
  bool _isRestoringBackup = false;
  MultisigBackupFileReadResult? _selectedBackup;
  String? _restoreError;

  bool get _busy => _isPickingBackup || _isRestoringBackup;

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
    setState(() {
      _isRestoringBackup = true;
      _restoreError = null;
    });
    try {
      final passphrase = rust_multisig.normalizeMultisigBackupPassword(
        password: _backupPasswordController.text,
        generated: _restoreGeneratedPassword,
      );
      final security = ref.read(appSecurityProvider);
      final hasAccounts =
          ref.read(accountProvider).value?.accounts.isNotEmpty ?? false;
      if (!hasAccounts && !security.isPasswordConfigured) {
        if (!mounted) return;
        context.go(
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

      await runWithSyncPausedForAccountMutation(ref, () async {
        await ref
            .read(accountProvider.notifier)
            .restoreMultisigAccountFromBackup(
              backupArtifactJson: backup.artifactJson,
              backupPassphrase: passphrase,
              backupFilePath: backup.path,
              coordinatorUrl: kDefaultMultisigCoordinatorUrl,
            );
      });
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestoringBackup = false;
        _restoreError = onboardingSubmitErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(multisigPendingSessionSummariesProvider);
    final materials = ref.watch(multisigAccountMaterialsProvider).value;
    final materializedSessionStorageIds = materials == null
        ? const <String>{}
        : materializedMultisigSessionStorageIds(materials);

    return MultisigOnboardingTrailingPane(
      backTarget: const OnboardingBackTarget.route(
        label: 'Welcome',
        routePath: '/welcome',
      ),
      bodyPadding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const MultisigOnboardingTitle(
                  title: 'Connect multisig',
                  subtitle: 'Continue a setup or start a new session.',
                  iconName: AppIcons.users,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('multisig_connect_create_button'),
                        onPressed: () => context.go('/multisig/create'),
                        leading: const AppIcon(AppIcons.addNew),
                        child: const Text('Create session'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('multisig_connect_join_button'),
                        onPressed: () => context.go('/multisig/join'),
                        variant: AppButtonVariant.secondary,
                        leading: const AppIcon(AppIcons.link),
                        child: const Text('Join session'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  key: const ValueKey('multisig_connect_restore_button'),
                  onPressed: _busy ? null : _pickBackup,
                  variant: AppButtonVariant.secondary,
                  leading: _isPickingBackup
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.importWallet),
                  child: Text(
                    _isPickingBackup ? 'Choosing backup' : 'Restore backup',
                  ),
                ),
                if (_selectedBackup != null || _restoreError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _RestoreBackupPanel(
                    selectedBackup: _selectedBackup,
                    generatedPassword: _restoreGeneratedPassword,
                    passwordController: _backupPasswordController,
                    busy: _busy,
                    error: _restoreError,
                    onGeneratedPasswordChanged: (value) {
                      setState(() {
                        _restoreGeneratedPassword = value;
                        _restoreError = null;
                      });
                    },
                    onPasswordChanged: () {
                      setState(() => _restoreError = null);
                    },
                    onChooseFile: _pickBackup,
                    onRestore: _restoreBackup,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                summariesAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    ),
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

                    if (pendingSummaries.isEmpty) {
                      return const _EmptyPendingSessions();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Pending sessions',
                          style: AppTypography.labelLarge.copyWith(
                            color: context.colors.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        for (var i = 0; i < pendingSummaries.length; i++) ...[
                          _PendingSessionTile(summary: pendingSummaries[i]),
                          if (i != pendingSummaries.length - 1)
                            const SizedBox(height: AppSpacing.xs),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreBackupPanel extends StatelessWidget {
  const _RestoreBackupPanel({
    required this.selectedBackup,
    required this.generatedPassword,
    required this.passwordController,
    required this.busy,
    required this.error,
    required this.onGeneratedPasswordChanged,
    required this.onPasswordChanged,
    required this.onChooseFile,
    required this.onRestore,
  });

  final MultisigBackupFileReadResult? selectedBackup;
  final bool generatedPassword;
  final TextEditingController passwordController;
  final bool busy;
  final String? error;
  final ValueChanged<bool> onGeneratedPasswordChanged;
  final VoidCallback onPasswordChanged;
  final VoidCallback onChooseFile;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backup = selectedBackup;
    final errorText = error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.state.selectedOpacity,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: AppIcon(
                        AppIcons.key,
                        size: 20,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Backup file',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        backup == null
                            ? 'No backup selected'
                            : _backupFileName(backup.path),
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  onPressed: busy ? null : onChooseFile,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.medium,
                  leading: const AppIcon(AppIcons.importWallet),
                  child: Text(backup == null ? 'Choose file' : 'Change'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    onPressed: busy
                        ? null
                        : () => onGeneratedPasswordChanged(true),
                    variant: generatedPassword
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    expand: true,
                    leading: const AppIcon(AppIcons.renew),
                    child: const Text('Generated'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AppButton(
                    onPressed: busy
                        ? null
                        : () => onGeneratedPasswordChanged(false),
                    variant: generatedPassword
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.primary,
                    size: AppButtonSize.medium,
                    expand: true,
                    leading: const AppIcon(AppIcons.edit),
                    child: const Text('Custom'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordTextField(
              label: 'Backup password',
              controller: passwordController,
              enabled: !busy,
              hintText: generatedPassword
                  ? 'eight generated words'
                  : 'backup password',
              onChanged: (_) => onPasswordChanged(),
              onSubmitted: (_) {
                if (backup != null && !busy) onRestore();
              },
            ),
            if (errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                errorText,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Center(
              child: AppButton(
                onPressed: backup == null || busy ? null : onRestore,
                leading: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppIcons.check),
                child: Text(busy ? 'Restoring account' : 'Restore account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _backupFileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}

class _PendingSessionTile extends StatelessWidget {
  const _PendingSessionTile({required this.summary});

  final MultisigPendingSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(
          '/multisig/session/${Uri.encodeComponent(summary.storageId)}',
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.raised,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
            border: Border.all(color: colors.border.subtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.state.selectedOpacity,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: AppIcon(
                        AppIcons.users,
                        size: 20,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary.displayLabel,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${summary.shortSessionId} · ${_statusLabel(summary.state)}',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 18,
                  color: colors.icon.regular,
                ),
              ],
            ),
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

class _EmptyPendingSessions extends StatelessWidget {
  const _EmptyPendingSessions();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No pending multisig sessions',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
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
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.destructive,
      ),
    );
  }
}
