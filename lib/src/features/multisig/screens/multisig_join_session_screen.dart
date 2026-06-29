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

class MultisigJoinSessionScreen extends ConsumerStatefulWidget {
  const MultisigJoinSessionScreen({super.key});

  @override
  ConsumerState<MultisigJoinSessionScreen> createState() =>
      _MultisigJoinSessionScreenState();
}

class _MultisigJoinSessionScreenState
    extends ConsumerState<MultisigJoinSessionScreen> {
  late final TextEditingController _sessionController;
  late final TextEditingController _coordinatorController;
  late final TextEditingController _labelController;
  final _securityGateController = MultisigSetupSecurityGateController();
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
    _labelController = TextEditingController();
  }

  @override
  void dispose() {
    _sessionController.dispose();
    _coordinatorController.dispose();
    _labelController.dispose();
    _securityGateController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_isSubmitting) return;
    final sessionId = _sessionController.text.trim();
    final coordinatorUrl = _coordinatorController.text.trim();
    final security = ref.read(appSecurityProvider);
    if (sessionId.isEmpty ||
        coordinatorUrl.isEmpty ||
        !_securityGateController.isValid(security)) {
      setState(() {
        _showError = true;
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
            .joinSession(
              coordinatorUrl: coordinatorUrl,
              sessionId: sessionId,
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
                title: 'Join multisig setup',
                subtitle: 'Enter the session ID shared by the creator.',
                iconName: AppIcons.link,
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
                            label: 'Session ID',
                            controller: _sessionController,
                            hintText: 'Session ID',
                            leading: const AppIcon(AppIcons.link),
                            showClearButton: true,
                            tone:
                                _showError &&
                                    _sessionController.text.trim().isEmpty
                                ? AppTextFieldTone.destructive
                                : AppTextFieldTone.neutral,
                            messageText:
                                _showError &&
                                    _sessionController.text.trim().isEmpty
                                ? 'Enter a session ID.'
                                : null,
                            onSubmitted: (_) => _join(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppTextField(
                            label: 'Coordinator',
                            controller: _coordinatorController,
                            hintText: kDefaultMultisigCoordinatorUrl,
                            leading: const AppIcon(AppIcons.endpoint),
                            showClearButton: true,
                            tone:
                                _showError &&
                                    _coordinatorController.text.trim().isEmpty
                                ? AppTextFieldTone.destructive
                                : AppTextFieldTone.neutral,
                            messageText:
                                _showError &&
                                    _coordinatorController.text.trim().isEmpty
                                ? 'Enter a coordinator URL.'
                                : null,
                            onSubmitted: (_) => _join(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppTextField(
                            label: 'Your label',
                            controller: _labelController,
                            hintText: 'Optional',
                            leading: const AppIcon(AppIcons.user),
                            showClearButton: true,
                            onSubmitted: (_) => _join(),
                          ),
                          if (_securityGateController.requiresInput(
                            security,
                          )) ...[
                            const SizedBox(height: AppSpacing.sm),
                            MultisigSetupSecurityGate(
                              controller: _securityGateController,
                              security: security,
                              showValidation: _showError,
                              enabled: !_isSubmitting,
                              onChanged: () {
                                setState(() {
                                  _submitError = null;
                                });
                              },
                              onSubmitted: _join,
                            ),
                          ],
                          if (_submitError != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ErrorText(message: _submitError!),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            onPressed: _isSubmitting ? null : _join,
                            minWidth: 180,
                            leading: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const AppIcon(AppIcons.link),
                            child: Text(
                              _isSubmitting ? 'Joining...' : 'Join session',
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
