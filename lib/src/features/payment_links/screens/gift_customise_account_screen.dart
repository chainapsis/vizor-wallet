import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/input/app_password_input_source.dart';
import '../../onboarding/mobile/mobile_customise_account_screen.dart';
import '../../onboarding/mobile/mobile_onboarding_progress.dart';
import '../services/gift_claim_setup_coordinator.dart';
import '../services/payment_link_service.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../onboarding/shared/account_persona_draft.dart';

class GiftCustomiseAccountArgs {
  const GiftCustomiseAccountArgs({
    required this.passcode,
    required this.inspection,
    this.passwordInputSource,
  });
  final String? passcode;
  final PaymentLinkClaimInspection inspection;
  final PasswordInputSourceCandidate? passwordInputSource;
}

/// Uses the same name and profile UI as normal wallet creation.
class GiftCustomiseAccountScreen extends ConsumerStatefulWidget {
  const GiftCustomiseAccountScreen({
    required this.args,
    this.random,
    super.key,
  });
  final GiftCustomiseAccountArgs args;
  final Random? random;

  @override
  ConsumerState<GiftCustomiseAccountScreen> createState() =>
      _GiftCustomiseAccountScreenState();
}

class _GiftCustomiseAccountScreenState
    extends ConsumerState<GiftCustomiseAccountScreen> {
  bool _continuingToSecurity = false;
  bool _requiresRestart = false;
  String? _createdAccountUuid;
  late final GiftClaimFlowNotifier _flow;

  @override
  void initState() {
    super.initState();
    _flow = ref.read(giftClaimFlowProvider.notifier);
  }

  @override
  void dispose() {
    final inspection = widget.args.inspection;
    if (!_continuingToSecurity) {
      scheduleMicrotask(() => _flow.finishWalletSetup(inspection));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileCustomiseAccountScreen(
    random: widget.random,
    onBack: () {
      _continuingToSecurity = true;
      _flow.cancelWalletSetup(widget.args.inspection);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/gift');
      }
    },
    onPopped: () => scheduleMicrotask(
      () => _flow.cancelWalletSetup(widget.args.inspection),
    ),
    initialPersona: ref.read(giftClaimFlowProvider)?.setupPersona,
    actionsEnabled: !_requiresRestart,
    setupCommitted: _createdAccountUuid != null,
    position: OnboardingProgressPlan.forFlow(
      OnboardingFlow.gift,
      setupMode: ref.read(appSecurityProvider).isPasswordConfigured
          ? OnboardingSetupMode.reusePasscode
          : OnboardingSetupMode.createPasscode,
    ).at(OnboardingStage.customiseAccount),
    onFinish: (name, profilePictureId) async {
      if (!ref.read(appSecurityProvider).isPasswordConfigured &&
          widget.args.passcode == null) {
        ref
            .read(giftClaimFlowProvider.notifier)
            .beginWalletSetup(
              widget.args.inspection,
              persona: AccountPersona(
                name: name,
                profilePictureId: profilePictureId,
              ),
            );
        _continuingToSecurity = true;
        context.go('/gift/passcode');
        return;
      }
      try {
        await completeGiftClaimWalletSetup(
          ref,
          password: widget.args.passcode,
          accountName: name,
          profilePictureId: profilePictureId,
          inspection: widget.args.inspection,
          createdAccountUuid: _createdAccountUuid,
          // Match normal account creation: security is committed before
          // asking for biometric unlock, then continue to Home.
          onComplete: () {
            if (context.mounted) {
              context.go(
                widget.args.passcode == null
                    ? '/home'
                    : '/onboarding/biometrics',
              );
            }
          },
        );
      } on GiftClaimAccountCreatedException catch (error) {
        if (mounted) setState(() => _createdAccountUuid = error.accountUuid);
        log('Gift wallet storage recovery failed: ${error.cause.runtimeType}');
        throw Exception('Couldn’t finish saving your wallet. Try again.');
      } on WalletAccountStateUncertainException {
        if (mounted) setState(() => _requiresRestart = true);
        rethrow;
      }
    },
  );
}
