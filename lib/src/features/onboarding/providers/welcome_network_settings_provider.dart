import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/network_privacy_provider.dart';

/// Only Welcome uses this hold. Incoming Gift links keep their existing intake
/// while the network editor is on top, even when its transport is ready.
class WelcomeNetworkSettingsNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPresented(bool value) => state = value;
}

final welcomeNetworkSettingsPresentedProvider =
    NotifierProvider<WelcomeNetworkSettingsNotifier, bool>(
      WelcomeNetworkSettingsNotifier.new,
    );

bool welcomeNetworkReady(NetworkPrivacyState state) =>
    !state.isBusy &&
    !(state.status == NetworkPrivacyConnectionStatus.failed &&
        state.torEnabled);
