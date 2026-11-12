import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../src/features/onboarding/providers/welcome_network_settings_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../widgetbook/mobile_welcome_preview_scope.dart';
import '../widgetbook/screen_use_cases.dart';

Widget buildMobileLanguageSettingsCapture(BuildContext context) =>
    _mobileNavigator(
      (context) => buildMobileSettingsMainUseCase(context, interactive: true),
    );

Widget buildMobileLanguageWelcomeCapture(BuildContext context) =>
    _mobileNavigator(
      (_) => mobileWelcomePreviewScope(
        state: const NetworkPrivacyState.off(),
        child: ProviderScope(
          overrides: [
            welcomeNetworkSettingsPresentedProvider.overrideWith(
              WelcomeNetworkSettingsNotifier.new,
            ),
          ],
          child: const MobileWelcomeScreen(animateBackground: false),
        ),
      ),
    );

// Keep root-navigator sheets inside the screenshot's repaint boundary.
Widget _mobileNavigator(WidgetBuilder builder) => Navigator(
  onGenerateRoute: (_) => MaterialPageRoute<void>(
    builder: (context) => Scaffold(body: builder(context)),
  ),
);
