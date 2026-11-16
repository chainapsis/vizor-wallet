import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/shared/account_persona_draft.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/onboarding/shared/set_password_screen.dart';

/// The real first-account credential screen without wallet or storage access.
Widget buildDeferredCreationPasswordCapture(BuildContext context) =>
    const _DeferredCreationPasswordCapture();

class _DeferredCreationPasswordCapture extends StatefulWidget {
  const _DeferredCreationPasswordCapture();

  @override
  State<_DeferredCreationPasswordCapture> createState() =>
      _DeferredCreationPasswordCaptureState();
}

class _DeferredCreationPasswordCaptureState
    extends State<_DeferredCreationPasswordCapture> {
  late final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => OnboardingSplitViewShell(
          activeStep: OnboardingStep.setPassword,
          showPasswordStep: true,
          showEducationSteps: false,
          child: SetPasswordScreen(
            args: const SetPasswordScreenArgs.createDeferred().withPersona(
              const AccountPersona(
                name: 'Capture account',
                profilePictureId: 'pfp-03',
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: Router.withConfig(config: _router),
  );
}
