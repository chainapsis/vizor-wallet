import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/multisig.dart' as rust_multisig;
import '../services/multisig_backup_file_service.dart';

class MultisigBackupCompletion {
  const MultisigBackupCompletion({
    required this.backupHash,
    required this.destinations,
    required this.backupArtifactJson,
    required this.backupPassphrase,
  });

  final String backupHash;
  final List<String> destinations;
  final String backupArtifactJson;
  final String backupPassphrase;
}

class MultisigBackupWizard extends ConsumerStatefulWidget {
  const MultisigBackupWizard({
    super.key,
    required this.session,
    required this.isCompleting,
    required this.onComplete,
  });

  final MultisigPendingSession session;
  final bool isCompleting;
  final ValueChanged<MultisigBackupCompletion> onComplete;

  @override
  ConsumerState<MultisigBackupWizard> createState() =>
      _MultisigBackupWizardState();
}

class _MultisigBackupWizardState extends ConsumerState<MultisigBackupWizard> {
  final _customPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _useGeneratedPassword = true;
  bool _isGenerating = false;
  bool _isEncrypting = false;
  bool _isVerifying = false;
  bool _isSaving = false;
  rust_multisig.ApiMultisigBackupPassword? _generatedPassword;
  rust_multisig.ApiMultisigBackupArtifact? _artifact;
  String? _verifiedPassphrase;
  String? _verifiedBackupHash;
  String? _savedPath;
  String? _error;

  bool get _busy =>
      _isGenerating ||
      _isEncrypting ||
      _isVerifying ||
      _isSaving ||
      widget.isCompleting;

  @override
  void dispose() {
    _customPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _resetArtifact() {
    _artifact = null;
    _verifiedPassphrase = null;
    _verifiedBackupHash = null;
    _savedPath = null;
    _confirmPasswordController.clear();
  }

  Future<void> _generatePassword() async {
    if (_busy) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final generated = rust_multisig.generateMultisigBackupPassword();
      if (!mounted) return;
      setState(() {
        _generatedPassword = generated;
        _useGeneratedPassword = true;
        _resetArtifact();
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyGeneratedPassword() async {
    final password = _generatedPassword?.displayPassword;
    if (password == null) return;
    await Clipboard.setData(ClipboardData(text: password));
  }

  Future<void> _encryptBackup() async {
    if (_busy) return;
    setState(() {
      _isEncrypting = true;
      _error = null;
      _resetArtifact();
    });
    try {
      if (_useGeneratedPassword && _generatedPassword == null) {
        _generatedPassword = rust_multisig.generateMultisigBackupPassword();
      }
      final source = _backupSource(widget.session);
      final artifact = await rust_multisig.createMultisigShareBackup(
        network: ref.read(rpcEndpointProvider).networkName,
        sessionId: widget.session.sessionId,
        participantId: widget.session.participantId,
        threshold: source.threshold,
        participantCount: source.participantCount,
        rosterHash: source.rosterHash,
        admissionSecretKey: widget.session.identity.admissionSecretKey,
        deliverySecretKey: widget.session.identity.deliverySecretKey,
        keyPackageB64: source.keyPackageB64,
        groupPublicPackageJson: source.groupPublicPackageJson,
        passphrase: _currentPassphrase(),
      );
      if (!mounted) return;
      setState(() {
        _artifact = artifact;
        _isEncrypting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isEncrypting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _verifyPassword() async {
    final artifact = _artifact;
    if (_busy || artifact == null) return;
    setState(() {
      _isVerifying = true;
      _error = null;
      _verifiedPassphrase = null;
      _verifiedBackupHash = null;
      _savedPath = null;
    });
    try {
      final passphrase = rust_multisig.normalizeMultisigBackupPassword(
        password: _confirmPasswordController.text,
        generated: _useGeneratedPassword,
      );
      final source = _backupSource(widget.session);
      final verified = await rust_multisig.verifyMultisigShareBackup(
        network: ref.read(rpcEndpointProvider).networkName,
        artifactJson: artifact.artifactJson,
        passphrase: passphrase,
        expectedSessionId: widget.session.sessionId,
        expectedParticipantId: widget.session.participantId,
        expectedThreshold: source.threshold,
        expectedParticipantCount: source.participantCount,
        expectedRosterHash: source.rosterHash,
        expectedGroupPublicPackageHash: source.groupPublicPackageHash,
      );
      if (!mounted) return;
      setState(() {
        _verifiedPassphrase = passphrase;
        _verifiedBackupHash = verified.backupHash;
        _isVerifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveFile() async {
    final artifact = _artifact;
    final passphrase = _verifiedPassphrase;
    if (_busy || artifact == null || passphrase == null) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await writeMultisigBackupFile(
        suggestedName: defaultMultisigBackupFileName(
          backupHash: artifact.backupHash,
        ),
        artifactJson: artifact.artifactJson,
      );
      final source = _backupSource(widget.session);
      final verified = await rust_multisig.verifyMultisigShareBackup(
        network: ref.read(rpcEndpointProvider).networkName,
        artifactJson: saved.artifactJson,
        passphrase: passphrase,
        expectedSessionId: widget.session.sessionId,
        expectedParticipantId: widget.session.participantId,
        expectedThreshold: source.threshold,
        expectedParticipantCount: source.participantCount,
        expectedRosterHash: source.rosterHash,
        expectedGroupPublicPackageHash: source.groupPublicPackageHash,
      );
      if (!mounted) return;
      setState(() {
        _verifiedBackupHash = verified.backupHash;
        _savedPath = saved.path;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.toString();
      });
    }
  }

  void _complete() {
    final artifact = _artifact;
    final passphrase = _verifiedPassphrase;
    final backupHash = _verifiedBackupHash;
    final savedPath = _savedPath;
    if (_busy ||
        artifact == null ||
        passphrase == null ||
        backupHash == null ||
        savedPath == null) {
      return;
    }
    widget.onComplete(
      MultisigBackupCompletion(
        backupHash: backupHash,
        destinations: ['file:$savedPath'],
        backupArtifactJson: artifact.artifactJson,
        backupPassphrase: passphrase,
      ),
    );
  }

  String _currentPassphrase() {
    if (_useGeneratedPassword) {
      final generated = _generatedPassword;
      if (generated == null) {
        throw StateError('Generate a backup password first.');
      }
      return generated.canonicalPassword;
    }
    return rust_multisig.normalizeMultisigBackupPassword(
      password: _customPasswordController.text,
      generated: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final completed = multisigLocalBackupCompleted(widget.session);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Backup',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  completed ? 'Previously verified' : 'Required',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Save and verify this participant backup before creating the local account.',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                AppButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _useGeneratedPassword = true;
                          _resetArtifact();
                        }),
                  variant: _useGeneratedPassword
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  child: const Text('Generated'),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _useGeneratedPassword = false;
                          _resetArtifact();
                        }),
                  variant: !_useGeneratedPassword
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  child: const Text('Custom'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_useGeneratedPassword)
              _GeneratedPasswordPanel(
                password: _generatedPassword,
                isGenerating: _isGenerating,
                onGenerate: _busy ? null : _generatePassword,
                onCopy: _generatedPassword == null
                    ? null
                    : _copyGeneratedPassword,
              )
            else
              PasswordTextField(
                label: 'Backup password',
                controller: _customPasswordController,
                hintText: 'At least 16 ASCII characters',
                onChanged: (_) => setState(_resetArtifact),
              ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: _busy ? null : _encryptBackup,
              minWidth: 180,
              leading: _isEncrypting
                  ? const _SmallSpinner()
                  : const AppIcon(AppIcons.lock),
              child: Text(_isEncrypting ? 'Encrypting' : 'Encrypt backup'),
            ),
            if (_artifact != null) ...[
              const SizedBox(height: AppSpacing.sm),
              PasswordTextField(
                label: 'Confirm backup password',
                controller: _confirmPasswordController,
                hintText: 'Re-enter the password',
                tone: _verifiedPassphrase == null
                    ? AppTextFieldTone.neutral
                    : AppTextFieldTone.success,
                onChanged: (_) {
                  setState(() {
                    _verifiedPassphrase = null;
                    _verifiedBackupHash = null;
                    _savedPath = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: _busy ? null : _verifyPassword,
                minWidth: 180,
                variant: AppButtonVariant.secondary,
                leading: _isVerifying
                    ? const _SmallSpinner()
                    : const AppIcon(AppIcons.check),
                child: Text(_isVerifying ? 'Verifying' : 'Verify password'),
              ),
            ],
            if (_verifiedPassphrase != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: _busy ? null : _saveFile,
                minWidth: 180,
                variant: AppButtonVariant.secondary,
                leading: _isSaving
                    ? const _SmallSpinner()
                    : const AppIcon(AppIcons.scroll),
                child: Text(_isSaving ? 'Saving' : 'Save backup file'),
              ),
            ],
            if (_savedPath != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _savedPath!,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: _savedPath != null && !_busy ? _complete : null,
              minWidth: 180,
              leading: widget.isCompleting
                  ? const _SmallSpinner()
                  : const AppIcon(AppIcons.checkCircle),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedPasswordPanel extends StatelessWidget {
  const _GeneratedPasswordPanel({
    required this.password,
    required this.isGenerating,
    required this.onGenerate,
    required this.onCopy,
  });

  final rust_multisig.ApiMultisigBackupPassword? password;
  final bool isGenerating;
  final VoidCallback? onGenerate;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              password?.displayPassword ?? 'No password generated',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            if (password != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Checksum ${password!.checksum}',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                AppButton(
                  onPressed: onGenerate,
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  leading: isGenerating
                      ? const _SmallSpinner()
                      : const AppIcon(AppIcons.renew),
                  child: Text(isGenerating ? 'Generating' : 'Generate'),
                ),
                AppButton(
                  onPressed: onCopy,
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  leading: const AppIcon(AppIcons.copy),
                  child: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupSource {
  const _BackupSource({
    required this.threshold,
    required this.participantCount,
    required this.rosterHash,
    required this.groupPublicPackageHash,
    required this.keyPackageB64,
    required this.groupPublicPackageJson,
  });

  final int threshold;
  final int participantCount;
  final String rosterHash;
  final String groupPublicPackageHash;
  final String keyPackageB64;
  final String groupPublicPackageJson;
}

_BackupSource _backupSource(MultisigPendingSession session) {
  final threshold = session.threshold;
  final participantCount = session.participants.length;
  if (threshold == null || threshold <= 0 || participantCount <= 0) {
    throw StateError('Multisig threshold or participants are missing.');
  }
  return _BackupSource(
    threshold: threshold,
    participantCount: participantCount,
    rosterHash: _requiredString(session.rosterHash, 'roster hash'),
    groupPublicPackageHash: _requiredString(
      session.groupPublicPackageHash,
      'group public package hash',
    ),
    keyPackageB64: _requiredString(session.keyPackageB64, 'local key package'),
    groupPublicPackageJson: _requiredString(
      session.groupPublicPackageJson,
      'group public package',
    ),
  );
}

String _requiredString(String? value, String label) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    throw StateError('Missing multisig $label.');
  }
  return trimmed;
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
