import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../providers/app_security_provider.dart';
import '../mobile/mobile_onboarding_progress_scope.dart';
import 'account_persona_draft.dart';
import 'account_setup_submission.dart';
import 'customise_account_mutation.dart';
import 'onboarding_flow_args.dart';

/// Welcome owns deferred additional-account submission and recovery. First
/// wallets carry a stable persona to the final credential screen. Legacy phrase
/// entry points can still supply a mnemonic.
class CreateAccountSubmission {
  CreateAccountSubmission({AccountPersona? persona})
    : persona = persona ?? AccountPersona.generate();

  final AccountPersona persona;
  final _submission = AccountSetupSubmission();
  bool get requiresRecovery => _submission.requiresRecovery;

  Future<void> continueSetup(WidgetRef ref, [String? mnemonic]) async {
    if (requiresRecovery) {
      await _submission.recover(ref);
      return;
    }
    final args =
        (mnemonic == null
                ? const SetPasswordScreenArgs.createDeferred()
                : SetPasswordScreenArgs.create(mnemonic: mnemonic))
            .withPersona(persona);
    if (!ref.read(appSecurityProvider).isPasswordConfigured) {
      clearCustomisedAccountDraft(ref, args.flow);
      if (kAppFormFactor == AppFormFactor.mobile) {
        // Replace the entry stack so its redirects cannot dismiss a durable
        // setup failure when the first account appears. Back uses typed args.
        ref.context.goOnboarding('/onboarding/set-passcode', extra: args);
      } else {
        GoRouter.of(ref.context).go(args.desktopPasswordRoutePath, extra: args);
      }
      return;
    }
    final router = GoRouter.of(ref.context);
    await _submission.run(ref, () async {
      await ref
          .read(linuxKeyringCoordinatorProvider)
          .runMutation(
            () => runCustomisedAccountMutation(
              ref,
              setupArgs: args,
              accountName: persona.name,
              profilePictureId: persona.profilePictureId,
            ),
          );
      if (!ref.context.mounted) return;
      clearCustomisedAccountDraft(ref, args.flow);
      router.go('/home');
    });
  }
}
