import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../widgets/multisig_onboarding_flow.dart';

class MultisigCreateSessionScreen extends ConsumerStatefulWidget {
  const MultisigCreateSessionScreen({super.key});

  @override
  ConsumerState<MultisigCreateSessionScreen> createState() =>
      _MultisigCreateSessionScreenState();
}

class _MultisigCreateSessionScreenState
    extends ConsumerState<MultisigCreateSessionScreen> {
  late final TextEditingController _labelController;
  _CreateSetupStep _step = _CreateSetupStep.walletPolicy;
  int _participantCount = 3;
  int _threshold = 2;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _continueToSigner() {
    setState(() {
      _step = _CreateSetupStep.signerAccount;
      _submitError = null;
    });
  }

  void _backToPolicy() {
    setState(() {
      _step = _CreateSetupStep.walletPolicy;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final pending = await ref
          .read(multisigPendingSessionsProvider.notifier)
          .createSession(
            coordinatorUrl: kDefaultMultisigCoordinatorUrl,
            participantCount: _participantCount,
            threshold: _threshold,
            label: _labelController.text,
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
    final isPolicyStep = _step == _CreateSetupStep.walletPolicy;
    return MultisigOnboardingTrailingPane(
      backTarget: isPolicyStep
          ? const OnboardingBackTarget.route(
              label: 'Connect multisig',
              routePath: '/multisig/connect',
            )
          : OnboardingBackTarget.callback(
              label: 'Wallet policy',
              onTap: _backToPolicy,
            ),
      bodyPadding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MultisigOnboardingTitle(
                title: 'Create multisig setup',
                subtitle: 'Choose the wallet policy, then name this signer.',
                iconName: AppIcons.users,
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: isPolicyStep
                          ? _WalletPolicyStep(
                              participantCount: _participantCount,
                              threshold: _threshold,
                              onParticipantCountChanged: (value) {
                                setState(() {
                                  _participantCount = value;
                                  if (_threshold > value) _threshold = value;
                                  if (_threshold < 2) _threshold = 2;
                                });
                              },
                              onThresholdChanged: (value) {
                                setState(() => _threshold = value);
                              },
                              onContinue: _continueToSigner,
                            )
                          : _SignerAccountStep(
                              labelController: _labelController,
                              participantCount: _participantCount,
                              threshold: _threshold,
                              isSubmitting: _isSubmitting,
                              submitError: _submitError,
                              onSubmit: _submit,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CreateSetupStep { walletPolicy, signerAccount }

class _WalletPolicyStep extends StatelessWidget {
  const _WalletPolicyStep({
    required this.participantCount,
    required this.threshold,
    required this.onParticipantCountChanged,
    required this.onThresholdChanged,
    required this.onContinue,
  });

  final int participantCount;
  final int threshold;
  final ValueChanged<int> onParticipantCountChanged;
  final ValueChanged<int> onThresholdChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PolicySelector(
          participantCount: participantCount,
          threshold: threshold,
          onParticipantCountChanged: onParticipantCountChanged,
          onThresholdChanged: onThresholdChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          onPressed: onContinue,
          minWidth: 180,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _SignerAccountStep extends StatelessWidget {
  const _SignerAccountStep({
    required this.labelController,
    required this.participantCount,
    required this.threshold,
    required this.isSubmitting,
    required this.submitError,
    required this.onSubmit,
  });

  final TextEditingController labelController;
  final int participantCount;
  final int threshold;
  final bool isSubmitting;
  final String? submitError;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PolicySummary(
          participantCount: participantCount,
          threshold: threshold,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Signer label',
          controller: labelController,
          hintText: 'Shown to your co-signers',
          leading: const AppIcon(AppIcons.user),
          showClearButton: true,
          onSubmitted: (_) => onSubmit(),
        ),
        if (submitError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorText(message: submitError!),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          onPressed: isSubmitting ? null : onSubmit,
          minWidth: 220,
          leading: isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppIcon(AppIcons.addNew),
          child: Text(isSubmitting ? 'Creating...' : 'Create session'),
        ),
      ],
    );
  }
}

class _PolicySummary extends StatelessWidget {
  const _PolicySummary({
    required this.participantCount,
    required this.threshold,
  });

  final int participantCount;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const AppIcon(AppIcons.users),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Any $threshold of $participantCount signers can approve a send.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySelector extends StatelessWidget {
  const _PolicySelector({
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
            Text(
              'Wallet policy',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Any $threshold of $participantCount signers can approve a send.',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Signers total',
              style: AppTypography.labelSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var value = 2; value <= 5; value++)
                  _PolicyChoice(
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
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var value = 2; value <= participantCount; value++)
                  _PolicyChoice(
                    label: '$value of $participantCount',
                    selected: threshold == value,
                    onSelected: () => onThresholdChanged(value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyChoice extends StatelessWidget {
  const _PolicyChoice({
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
      size: AppButtonSize.small,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      child: Text(label),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTypography.labelMedium.copyWith(
        color: context.colors.text.destructive,
      ),
    );
  }
}
