import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../widgets/multisig_onboarding_flow.dart';
import '../widgets/multisig_setup_security_gate.dart';

class MultisigCreateSessionScreen extends ConsumerStatefulWidget {
  const MultisigCreateSessionScreen({super.key});

  @override
  ConsumerState<MultisigCreateSessionScreen> createState() =>
      _MultisigCreateSessionScreenState();
}

class _MultisigCreateSessionScreenState
    extends ConsumerState<MultisigCreateSessionScreen> {
  late final TextEditingController _coordinatorController;
  late final TextEditingController _labelController;
  final _securityGateController = MultisigSetupSecurityGateController();
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
    _labelController = TextEditingController();
  }

  @override
  void dispose() {
    _coordinatorController.dispose();
    _labelController.dispose();
    _securityGateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final coordinatorUrl = _coordinatorController.text.trim();
    final security = ref.read(appSecurityProvider);
    if (coordinatorUrl.isEmpty || !_securityGateController.isValid(security)) {
      setState(() {
        _showValidation = true;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final pending = await _securityGateController.runWithOpenSession(
        ref: ref,
        security: security,
        action: () => ref
            .read(multisigPendingSessionsProvider.notifier)
            .createSession(
              coordinatorUrl: coordinatorUrl,
              participantCount: _participantCount,
              threshold: _threshold,
              label: _labelController.text,
            ),
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
              const MultisigOnboardingTitle(
                title: 'Create multisig setup',
                subtitle:
                    'Choose the signer policy before sharing the invite code.',
                iconName: AppIcons.users,
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: 'Coordinator',
                            controller: _coordinatorController,
                            hintText: kDefaultMultisigCoordinatorUrl,
                            leading: const AppIcon(AppIcons.endpoint),
                            showClearButton: true,
                            tone:
                                _showValidation &&
                                    _coordinatorController.text.trim().isEmpty
                                ? AppTextFieldTone.destructive
                                : AppTextFieldTone.neutral,
                            messageText:
                                _showValidation &&
                                    _coordinatorController.text.trim().isEmpty
                                ? 'Enter a coordinator URL.'
                                : null,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppTextField(
                            label: 'Your label',
                            controller: _labelController,
                            hintText: 'Optional',
                            leading: const AppIcon(AppIcons.user),
                            showClearButton: true,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _PolicySelector(
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
                          ),
                          if (_securityGateController.requiresInput(
                            security,
                          )) ...[
                            const SizedBox(height: AppSpacing.sm),
                            MultisigSetupSecurityGate(
                              controller: _securityGateController,
                              security: security,
                              showValidation: _showValidation,
                              enabled: !_isSubmitting,
                              onChanged: () {
                                setState(() {
                                  _submitError = null;
                                });
                              },
                              onSubmitted: _submit,
                            ),
                          ],
                          if (_submitError != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ErrorText(message: _submitError!),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            onPressed: _isSubmitting ? null : _submit,
                            minWidth: 220,
                            leading: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const AppIcon(AppIcons.addNew),
                            child: Text(
                              _isSubmitting ? 'Creating...' : 'Create session',
                            ),
                          ),
                        ],
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
              'Any $threshold of $participantCount participants can approve a send.',
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
