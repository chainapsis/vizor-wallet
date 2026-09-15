// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/app_bootstrap.dart';
import '../../src/core/security/password_policy.dart';
import '../../src/features/address_scan/widgets/address_qr_scan_modal.dart'
    show AddressQrCameraStatus;
import '../../src/features/keystone/widgets/keystone_signing_modal.dart';
import '../../src/features/onboarding/create/onboarding_split_view.dart'
    show OnboardingStep, OnboardingStepX;
import '../../src/features/onboarding/import/import_split_view.dart'
    show ImportOnboardingStep, ImportOnboardingStepX;
import '../../src/features/onboarding/import/import_wallet_birthday_screen.dart';
import '../../src/features/onboarding/keystone/keystone_onboarding_flow.dart'
    show KeystoneOnboardingStep, KeystoneOnboardingStepX;
import '../../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../../src/features/wallet_link/providers/mobile_wallet_link_provider.dart'
    show MobileWalletLinkScanError;
import '../../src/services/biometric_unlock.dart' show BiometricKind;
import '../keystone_use_cases.dart';
import '../onboarding_use_cases.dart';
import '../screen_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import 'scanner_gallery.dart';

/// The Onboarding gallery: one use case per surface, each knob dispatching to
/// the fixtures in `screen_use_cases.dart` / `keystone_use_cases.dart` so
/// figma_compare and the tests keep every `build*UseCase` they bind to.
///
/// Every surface that exists in both form factors is one use case with a
/// `Layout` knob; the surfaces with no counterpart in the other form factor
/// (the desktop shells, the mobile step screens) carry no knob. The two lanes
/// were built from different Figma frames, so their state axes are registered
/// per lane — the desktop welcome's network-settings panel and the mobile
/// welcome's entry point are each offered only where a fixture exists. Six
/// desktop cards measurably overflow under mobile tokens, so their desktop
/// branch stays `WbLaneOnly`: the two auth-card screens plus the unlock body,
/// the create intro, the seed grid and the password card.
final List<WidgetbookNode> onboardingGalleryNodes = [
  WidgetbookComponent(
    name: 'Welcome',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingWelcomeGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile method selection',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileMethodSelectionUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Intro to Zcash',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingIntroZcashGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Address types',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingAddressTypesGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Things to know',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingThingsToKnowGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Secret passphrase',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingSecretPassphraseGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Set password',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingSetPasswordGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Unlock',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingUnlockGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Lost password',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingLostPasswordGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Storage unavailable',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingStorageUnavailableGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Import secret passphrase',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingImportPassphraseGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Import wallet birthday',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingImportBirthdayGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Import account discovery',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingImportDiscoveryGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Unknown birthday height',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingUnknownBirthdayGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Customise account',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingCustomiseAccountGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile biometrics opt-in',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileBiometricsGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile import paste',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileImportPasteGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile import manual',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileImportManualGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile import review',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileImportReviewGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile wallet link intro',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingMobileWalletLinkIntroUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile wallet link scan',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingWalletLinkScanGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile wallet link selection',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingWalletLinkAccountsGalleryCase,
      ),
    ],
  ),
  // The three desktop shells are one surface with disjoint step axes, so each
  // flow is a use case rather than a flow knob.
  WidgetbookComponent(
    name: 'Onboarding shell',
    useCases: [
      WidgetbookUseCase(
        name: 'Create',
        builder: buildOnboardingCreateShellGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Import',
        builder: buildOnboardingImportShellGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Keystone',
        builder: buildOnboardingKeystoneShellGalleryCase,
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Unlock content',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingUnlockContentGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Onboarding sidebar',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingSidebarGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Onboarding pane chrome',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingPaneChromeGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Auth shell',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingAuthShellGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Mobile step scaffold',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingStepScaffoldGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Seed card',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingSeedCardGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Passcode field',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingPasscodeFieldGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Passcode keypad',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingPasscodeKeypadGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Birthday calendar',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildOnboardingBirthdayCalendarGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Mobile screenshot warning sheet',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMobileSeedScreenshotWarningSheetUseCase,
          ),
        ],
      ),
    ],
  ),
];

/// Keystone lives in its own `Screens > Keystone` folder: pairing and import
/// are onboarding, but the transaction QR and signing screens belong to the
/// send flow, so filing them under Onboarding hid them from both.
final List<WidgetbookNode> keystoneGalleryNodes = [
  WidgetbookComponent(
    name: 'Intro',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneIntroGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Scan',
    useCases: [
      // The desktop half is `KeystoneQrScannerCard`, which owns a live
      // `MobileScannerController`; it previews against the camera fake in
      // `support/wb_fake_scanner_platform.dart`.
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneScanGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Select account',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneSelectAccountGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Birthday height',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneBirthdayGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Transaction QR',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystonePcztQrGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Transaction progress',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneProgressGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Signing',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneSigningGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Scan help',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildOnboardingKeystoneScanHelpGalleryCase,
      ),
    ],
  ),
];

// --- Welcome ---------------------------------------------------------------

/// Which of the desktop welcome screen's two panels is showing; the mobile
/// screen has no network settings, so this axis is desktop-only.
enum OnboardingWelcomePanel { welcome, networkSettings }

/// Tor route of the network-settings panel; only the welcome panel's own
/// fixture pins it to off.
enum OnboardingWelcomeTor { off, connecting, connected }

Widget buildOnboardingWelcomeGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // Two different screens: the desktop one opens the network-settings panel,
  // the mobile one only varies on where it was entered from.
  if (layout == WbLayout.mobile) return _onboardingMobileWelcome(context);
  return _onboardingDesktopWelcome(context);
}

Widget _onboardingDesktopWelcome(BuildContext context) {
  final panel = wbStateKnob<OnboardingWelcomePanel>(
    context,
    label: 'Panel',
    options: OnboardingWelcomePanel.values,
    labelBuilder: onboardingWelcomePanelLabel,
  );
  final tor = wbStateKnob<OnboardingWelcomeTor>(
    context,
    label: 'Tor',
    options: OnboardingWelcomeTor.values,
    labelBuilder: onboardingWelcomeTorLabel,
  );
  // The welcome panel has one fixture only, which pins the route to off, so
  // `Tor` says nothing until the network-settings panel is open.
  if (panel == OnboardingWelcomePanel.welcome) {
    return buildWelcomeLargeUseCase(context);
  }
  return switch (tor) {
    OnboardingWelcomeTor.off => buildWelcomeNetworkSettingsUseCase(context),
    OnboardingWelcomeTor.connecting =>
      buildWelcomeNetworkSettingsTorConnectingUseCase(context),
    OnboardingWelcomeTor.connected =>
      buildWelcomeNetworkSettingsTorConnectedUseCase(context),
  };
}

String onboardingWelcomePanelLabel(OnboardingWelcomePanel panel) {
  return switch (panel) {
    OnboardingWelcomePanel.welcome => 'Welcome',
    OnboardingWelcomePanel.networkSettings => 'Network settings',
  };
}

String onboardingWelcomeTorLabel(OnboardingWelcomeTor tor) {
  return switch (tor) {
    OnboardingWelcomeTor.off => 'Off',
    OnboardingWelcomeTor.connecting => 'Connecting',
    OnboardingWelcomeTor.connected => 'Connected',
  };
}

// --- Create flow: explainers -----------------------------------------------

/// The three explainers are one screen per lane with no state axis, so the
/// `Layout` knob is their only knob. The desktop intro is lane-gated (its pane
/// overflows by 12px under mobile tokens); its two siblings measure clean and
/// stay previewable in either lane.
Widget buildOnboardingIntroZcashGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return buildOnboardingMobileIntroZcashUseCase(context);
  }
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: Builder(builder: buildOnboardingIntroZcashUseCase),
  );
}

Widget buildOnboardingAddressTypesGalleryCase(BuildContext context) {
  return wbLayoutKnob(context) == WbLayout.mobile
      ? buildOnboardingMobileAddressTypesUseCase(context)
      : buildOnboardingAddressTypesUseCase(context);
}

Widget buildOnboardingThingsToKnowGalleryCase(BuildContext context) {
  return wbLayoutKnob(context) == WbLayout.mobile
      ? buildOnboardingMobileThingsToKnowUseCase(context)
      : buildOnboardingThingsToKnowUseCase(context);
}

// --- Create flow: secret passphrase ----------------------------------------

enum OnboardingSecretPassphraseReveal { hidden, revealed }

/// The privacy overlay only covers a revealed grid, so this axis says nothing
/// while the phrase is still hidden.
enum OnboardingSecretPassphrasePrivacy { visible, protected }

/// The lanes vary on different things: desktop crosses reveal with the privacy
/// overlay, while the mobile screen has one fixture per state, so each lane
/// registers its own `State` axis. Desktop is lane-gated — its seed grid
/// overflows by 36px under mobile tokens.
Widget buildOnboardingSecretPassphraseGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return _onboardingMobileSecretPassphrase(context);
  }
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: Builder(builder: _onboardingSecretPassphrase),
  );
}

Widget _onboardingSecretPassphrase(BuildContext context) {
  final reveal = wbStateKnob<OnboardingSecretPassphraseReveal>(
    context,
    label: 'State',
    options: OnboardingSecretPassphraseReveal.values,
    labelBuilder: onboardingSecretPassphraseRevealLabel,
    initial: OnboardingSecretPassphraseReveal.revealed,
  );
  final privacy = wbStateKnob<OnboardingSecretPassphrasePrivacy>(
    context,
    label: 'Privacy',
    options: OnboardingSecretPassphrasePrivacy.values,
    labelBuilder: onboardingSecretPassphrasePrivacyLabel,
  );
  return onboardingSecretPassphraseFixture(
    revealed: reveal == OnboardingSecretPassphraseReveal.revealed,
    privacyProtected: privacy == OnboardingSecretPassphrasePrivacy.protected,
  );
}

String onboardingSecretPassphraseRevealLabel(
  OnboardingSecretPassphraseReveal reveal,
) {
  return switch (reveal) {
    OnboardingSecretPassphraseReveal.hidden => 'Hidden',
    OnboardingSecretPassphraseReveal.revealed => 'Revealed',
  };
}

String onboardingSecretPassphrasePrivacyLabel(
  OnboardingSecretPassphrasePrivacy privacy,
) {
  return switch (privacy) {
    OnboardingSecretPassphrasePrivacy.visible => 'Visible',
    OnboardingSecretPassphrasePrivacy.protected => 'Protected',
  };
}

// --- Set password ----------------------------------------------------------

/// The set-password step of both lanes: desktop types a password, mobile sets
/// a six-digit passcode on the same `/onboarding/set-passcode` step.
///
/// Desktop is lane-gated — its password card overflows by 30px under mobile
/// tokens — and carries the flow knob; the mobile step has one fixture.
Widget buildOnboardingSetPasswordGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return buildMobileCreatePasscodeUseCase(context);
  }
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: Builder(builder: _onboardingSetPassword),
  );
}

/// Knob over the production flow enum: the flow picks the args, the sidebar
/// shell and the submit label all at once.
Widget _onboardingSetPassword(BuildContext context) {
  final flow = wbStateKnob<SetPasswordFlow>(
    context,
    label: 'Flow',
    options: SetPasswordFlow.values,
    labelBuilder: onboardingSetPasswordFlowLabel,
  );
  return onboardingSetPasswordFixture(flow: flow);
}

String onboardingSetPasswordFlowLabel(SetPasswordFlow flow) {
  return switch (flow) {
    SetPasswordFlow.create => 'Create',
    SetPasswordFlow.importWallet => 'Import wallet',
    SetPasswordFlow.importKeystone => 'Import Keystone',
    SetPasswordFlow.importWalletLink => 'Wallet link',
  };
}

// --- Unlock / lost password ------------------------------------------------

/// The desktop screen has no state axis a preview can drive (its password
/// field and message are private `State`), while the mobile passcode screen
/// has three, so the axes are registered per lane.
///
/// The desktop half sits on a fixed-size `OnboardingAuthCard` whose height is
/// a desktop-token constant, so the mobile lane overflows it (measured: 11px)
/// rather than approximating it — show the lane notice instead. The lost
/// password card (76px) is gated the same way.
Widget buildOnboardingUnlockGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return _onboardingMobileUnlock(context);
  }
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: buildUnlockLoginUseCase(context),
  );
}

enum OnboardingUnlockMessage {
  none,
  incorrectPassword,
  couldNotOpen,
  passwordTooShort,
}

enum OnboardingUnlockForgotPassword { shown, spaceReserved, hidden }

/// The two descriptions in production: the unlock route's own line and the
/// Ironwood virtual-unlock host's auto-lock line.
enum OnboardingUnlockDescription { unlock, autoLocked }

Widget buildOnboardingUnlockContentGalleryCase(BuildContext context) {
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _onboardingUnlockContent(context),
  );
}

Widget _onboardingUnlockContent(BuildContext context) {
  final message = wbStateKnob<OnboardingUnlockMessage>(
    context,
    label: 'Message',
    options: OnboardingUnlockMessage.values,
    labelBuilder: onboardingUnlockMessageLabel,
  );
  final forgotPassword = wbStateKnob<OnboardingUnlockForgotPassword>(
    context,
    label: 'Forgot password',
    options: OnboardingUnlockForgotPassword.values,
    labelBuilder: onboardingUnlockForgotPasswordLabel,
  );
  final description = wbStateKnob<OnboardingUnlockDescription>(
    context,
    label: 'Description',
    options: OnboardingUnlockDescription.values,
    labelBuilder: onboardingUnlockDescriptionLabel,
  );
  final canSubmit = wbBoolKnob(context, label: 'Password entered');
  return onboardingUnlockContentFixture(
    messageText: onboardingUnlockMessageText(message),
    showForgotPassword: forgotPassword == OnboardingUnlockForgotPassword.shown,
    reserveForgotPasswordSpace:
        forgotPassword == OnboardingUnlockForgotPassword.spaceReserved,
    descriptionText: onboardingUnlockDescriptionText(description),
    canSubmit: canSubmit,
  );
}

String? onboardingUnlockMessageText(OnboardingUnlockMessage message) {
  return switch (message) {
    OnboardingUnlockMessage.none => null,
    OnboardingUnlockMessage.incorrectPassword =>
      'Incorrect password. Try '
          'again.',
    OnboardingUnlockMessage.couldNotOpen =>
      "Couldn't open your wallet. Please try again.",
    OnboardingUnlockMessage.passwordTooShort => kWalletPasswordMinLengthMessage,
  };
}

String onboardingUnlockDescriptionText(OnboardingUnlockDescription value) {
  return switch (value) {
    OnboardingUnlockDescription.unlock => 'Enter your password to open Vizor.',
    OnboardingUnlockDescription.autoLocked =>
      'We auto-locked Vizor after 10 minutes of inactivity.',
  };
}

String onboardingUnlockMessageLabel(OnboardingUnlockMessage message) {
  return switch (message) {
    OnboardingUnlockMessage.none => 'None',
    OnboardingUnlockMessage.incorrectPassword => 'Incorrect password',
    OnboardingUnlockMessage.couldNotOpen => "Couldn't open your wallet",
    OnboardingUnlockMessage.passwordTooShort => 'Password too short',
  };
}

String onboardingUnlockForgotPasswordLabel(
  OnboardingUnlockForgotPassword value,
) {
  return switch (value) {
    OnboardingUnlockForgotPassword.shown => 'Shown',
    OnboardingUnlockForgotPassword.spaceReserved => 'Space reserved',
    OnboardingUnlockForgotPassword.hidden => 'Hidden',
  };
}

String onboardingUnlockDescriptionLabel(OnboardingUnlockDescription value) {
  return switch (value) {
    OnboardingUnlockDescription.unlock => 'Unlock',
    OnboardingUnlockDescription.autoLocked => 'Auto-locked',
  };
}

enum OnboardingLostPasswordCountdown { counting, ready }

enum OnboardingLostPasswordClaims { none, oneInFlight }

Widget buildOnboardingLostPasswordGalleryCase(BuildContext context) {
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _onboardingLostPassword(context),
  );
}

Widget _onboardingLostPassword(BuildContext context) {
  final countdown = wbStateKnob<OnboardingLostPasswordCountdown>(
    context,
    label: 'Countdown',
    options: OnboardingLostPasswordCountdown.values,
    labelBuilder: onboardingLostPasswordCountdownLabel,
  );
  final claims = wbStateKnob<OnboardingLostPasswordClaims>(
    context,
    label: 'Gift card claims',
    options: OnboardingLostPasswordClaims.values,
    labelBuilder: onboardingLostPasswordClaimsLabel,
  );
  // Both options go through the fixture: the two standalone builders read the
  // real claims store, so only the override keeps the axis hermetic.
  return onboardingLostPasswordFixture(
    countdownSeconds: countdown == OnboardingLostPasswordCountdown.counting
        ? 3
        : 0,
    claimsInFlight: claims == OnboardingLostPasswordClaims.oneInFlight ? 1 : 0,
  );
}

String onboardingLostPasswordClaimsLabel(OnboardingLostPasswordClaims claims) {
  return switch (claims) {
    OnboardingLostPasswordClaims.none => 'None',
    OnboardingLostPasswordClaims.oneInFlight => '1 being received',
  };
}

// --- Storage unavailable ---------------------------------------------------

Widget buildOnboardingStorageUnavailableGalleryCase(BuildContext context) {
  final failure = wbStateKnob<AppBootstrapFailureKind>(
    context,
    label: 'Failure',
    options: AppBootstrapFailureKind.values,
    labelBuilder: onboardingStorageFailureLabel,
  );
  return onboardingStorageUnavailableFixture(
    failureKind: failure,
    // Only the startup-failure body shows this detail line.
    failureMessage: 'Vizor could not load its startup state.',
  );
}

String onboardingStorageFailureLabel(AppBootstrapFailureKind failure) {
  return switch (failure) {
    AppBootstrapFailureKind.secureStorageUnavailable => 'Secure storage locked',
    AppBootstrapFailureKind.startupFailure => 'Startup failure',
    AppBootstrapFailureKind.walletDbMigrationFailed => 'Wallet database update',
  };
}

String onboardingLostPasswordCountdownLabel(
  OnboardingLostPasswordCountdown countdown,
) {
  return switch (countdown) {
    OnboardingLostPasswordCountdown.counting => 'Counting down',
    OnboardingLostPasswordCountdown.ready => 'Reset enabled',
  };
}

// --- Import secret passphrase ----------------------------------------------

/// Fixture-selection axis: the BIP39 modal only exists over the filled phrase,
/// so it is an option here rather than its own knob.
enum OnboardingImportPassphraseState { empty, filled, invalidWord, bip39Modal }

Widget buildOnboardingImportPassphraseGalleryCase(BuildContext context) {
  final state = wbStateKnob<OnboardingImportPassphraseState>(
    context,
    label: 'State',
    options: OnboardingImportPassphraseState.values,
    labelBuilder: onboardingImportPassphraseStateLabel,
  );
  return switch (state) {
    OnboardingImportPassphraseState.empty => buildImportSecretPassphraseUseCase(
      context,
    ),
    OnboardingImportPassphraseState.filled =>
      buildImportSecretPassphrasePopulatedUseCase(context),
    OnboardingImportPassphraseState.invalidWord =>
      buildImportSecretPassphraseInvalidWordUseCase(context),
    OnboardingImportPassphraseState.bip39Modal =>
      buildImportSecretPassphraseModalUseCase(context),
  };
}

String onboardingImportPassphraseStateLabel(
  OnboardingImportPassphraseState state,
) {
  return switch (state) {
    OnboardingImportPassphraseState.empty => 'Empty',
    OnboardingImportPassphraseState.filled => 'Phrase entered',
    OnboardingImportPassphraseState.invalidWord => 'Invalid word',
    OnboardingImportPassphraseState.bip39Modal => 'BIP39 passphrase',
  };
}

// --- Customise account -----------------------------------------------------

/// Which flow the screen is the last step of; only the desktop screen changes
/// with it (the sidebar and the submit label), and the mobile step has one
/// fixture, so the axis is desktop-only.
enum OnboardingCustomiseAccountFlow { create, importWallet }

Widget buildOnboardingCustomiseAccountGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return buildMobileCustomiseAccountUseCase(context);
  }
  final flow = wbStateKnob<OnboardingCustomiseAccountFlow>(
    context,
    label: 'Flow',
    options: OnboardingCustomiseAccountFlow.values,
    labelBuilder: onboardingCustomiseAccountFlowLabel,
  );
  return switch (flow) {
    OnboardingCustomiseAccountFlow.create => buildCustomiseAccountUseCase(
      context,
    ),
    OnboardingCustomiseAccountFlow.importWallet =>
      buildImportCustomiseAccountUseCase(context),
  };
}

String onboardingCustomiseAccountFlowLabel(
  OnboardingCustomiseAccountFlow flow,
) {
  return switch (flow) {
    OnboardingCustomiseAccountFlow.create => 'Create',
    OnboardingCustomiseAccountFlow.importWallet => 'Import wallet',
  };
}

// --- Mobile unlock ---------------------------------------------------------

enum OnboardingMobileUnlockBiometric { none, faceId, touchId, fingerprint }

/// What covers the unlock screen. The sheet fixtures pin the biometric state
/// to Face ID, so `Biometric` only applies with no overlay.
enum OnboardingMobileUnlockOverlay {
  none,
  biometricSignIn,
  forgotPasscode,
  resetWarning,
}

/// What the passcode attempt is doing. Every option past 'Waiting' is reached
/// by entering six digits on the real keypad, so the sheet overlays — which
/// cover the keypad — pin this back to 'Waiting'.
enum OnboardingMobileUnlockAttempt {
  waiting,
  submitting,
  incorrectPasscode,
  openFailed,
}

Widget _onboardingMobileUnlock(BuildContext context) {
  final biometric = wbStateKnob<OnboardingMobileUnlockBiometric>(
    context,
    label: 'Biometric',
    options: OnboardingMobileUnlockBiometric.values,
    labelBuilder: onboardingMobileUnlockBiometricLabel,
  );
  final overlay = wbStateKnob<OnboardingMobileUnlockOverlay>(
    context,
    label: 'Overlay',
    options: OnboardingMobileUnlockOverlay.values,
    labelBuilder: onboardingMobileUnlockOverlayLabel,
  );
  final attempt = wbStateKnob<OnboardingMobileUnlockAttempt>(
    context,
    label: 'Attempt',
    options: OnboardingMobileUnlockAttempt.values,
    labelBuilder: onboardingMobileUnlockAttemptLabel,
  );
  if (overlay == OnboardingMobileUnlockOverlay.none &&
      attempt != OnboardingMobileUnlockAttempt.waiting) {
    return onboardingMobileUnlockSubmitFixture(
      biometric: onboardingMobileUnlockBiometricKind(biometric),
      submit: switch (attempt) {
        OnboardingMobileUnlockAttempt.waiting ||
        OnboardingMobileUnlockAttempt.submitting =>
          OnboardingMobileUnlockSubmit.submitting,
        OnboardingMobileUnlockAttempt.incorrectPasscode =>
          OnboardingMobileUnlockSubmit.incorrectPasscode,
        OnboardingMobileUnlockAttempt.openFailed =>
          OnboardingMobileUnlockSubmit.openFailed,
      },
    );
  }
  if (overlay != OnboardingMobileUnlockOverlay.none) {
    return switch (overlay) {
      OnboardingMobileUnlockOverlay.none => buildMobileUnlockPasscodeUseCase(
        context,
      ),
      OnboardingMobileUnlockOverlay.biometricSignIn =>
        buildMobileUnlockBiometricBackdropUseCase(context),
      OnboardingMobileUnlockOverlay.forgotPasscode =>
        buildMobileForgotPasscodeSheetUseCase(context),
      OnboardingMobileUnlockOverlay.resetWarning =>
        buildMobileForgotPasscodeLastWarningUseCase(context),
    };
  }
  return switch (biometric) {
    OnboardingMobileUnlockBiometric.none => buildMobileUnlockPasscodeUseCase(
      context,
    ),
    OnboardingMobileUnlockBiometric.faceId => buildMobileUnlockFaceIdUseCase(
      context,
    ),
    OnboardingMobileUnlockBiometric.touchId => buildMobileUnlockTouchIdUseCase(
      context,
    ),
    OnboardingMobileUnlockBiometric.fingerprint =>
      buildMobileUnlockFingerprintUseCase(context),
  };
}

String onboardingMobileUnlockBiometricLabel(
  OnboardingMobileUnlockBiometric biometric,
) {
  return switch (biometric) {
    OnboardingMobileUnlockBiometric.none => 'Passcode only',
    OnboardingMobileUnlockBiometric.faceId => 'Face ID',
    OnboardingMobileUnlockBiometric.touchId => 'Touch ID',
    OnboardingMobileUnlockBiometric.fingerprint => 'Fingerprint',
  };
}

String onboardingMobileUnlockAttemptLabel(
  OnboardingMobileUnlockAttempt attempt,
) {
  return switch (attempt) {
    OnboardingMobileUnlockAttempt.waiting => 'Waiting for the passcode',
    OnboardingMobileUnlockAttempt.submitting => 'Opening the wallet',
    OnboardingMobileUnlockAttempt.incorrectPasscode => 'Incorrect passcode',
    OnboardingMobileUnlockAttempt.openFailed => "Couldn't open the wallet",
  };
}

BiometricKind onboardingMobileUnlockBiometricKind(
  OnboardingMobileUnlockBiometric biometric,
) {
  return switch (biometric) {
    OnboardingMobileUnlockBiometric.none => BiometricKind.none,
    OnboardingMobileUnlockBiometric.faceId => BiometricKind.face,
    OnboardingMobileUnlockBiometric.touchId => BiometricKind.touchId,
    OnboardingMobileUnlockBiometric.fingerprint => BiometricKind.fingerprint,
  };
}

String onboardingMobileUnlockOverlayLabel(
  OnboardingMobileUnlockOverlay overlay,
) {
  return switch (overlay) {
    OnboardingMobileUnlockOverlay.none => 'None',
    OnboardingMobileUnlockOverlay.biometricSignIn => 'Biometric sign-in',
    OnboardingMobileUnlockOverlay.forgotPasscode => 'Forgot passcode',
    OnboardingMobileUnlockOverlay.resetWarning => 'Reset warning',
  };
}

// --- Mobile secret passphrase ----------------------------------------------

/// Fixture-selection axis: the screenshot warning is a sheet over this screen,
/// and the privacy overlay replaces the grid, so neither splits into its own
/// orthogonal knob without new fixtures.
enum OnboardingMobilePassphraseState {
  hidden,
  revealed,
  longWords,
  privacyProtected,
  screenshotWarning,
}

Widget _onboardingMobileSecretPassphrase(BuildContext context) {
  final state = wbStateKnob<OnboardingMobilePassphraseState>(
    context,
    label: 'State',
    options: OnboardingMobilePassphraseState.values,
    labelBuilder: onboardingMobilePassphraseStateLabel,
  );
  return switch (state) {
    OnboardingMobilePassphraseState.hidden =>
      buildMobileSecretPassphraseHiddenUseCase(context),
    OnboardingMobilePassphraseState.revealed =>
      buildMobileSecretPassphraseRevealedUseCase(context),
    OnboardingMobilePassphraseState.longWords =>
      buildMobileSecretPassphraseLongWordsUseCase(context),
    OnboardingMobilePassphraseState.privacyProtected =>
      buildMobileSecretPassphraseProtectedUseCase(context),
    OnboardingMobilePassphraseState.screenshotWarning =>
      buildMobileSecretPassphraseScreenshotWarningUseCase(context),
  };
}

String onboardingMobilePassphraseStateLabel(
  OnboardingMobilePassphraseState state,
) {
  return switch (state) {
    OnboardingMobilePassphraseState.hidden => 'Hidden',
    OnboardingMobilePassphraseState.revealed => 'Revealed',
    OnboardingMobilePassphraseState.longWords => 'Long words',
    OnboardingMobilePassphraseState.privacyProtected => 'Privacy protected',
    OnboardingMobilePassphraseState.screenshotWarning => 'Screenshot warning',
  };
}

// --- Mobile biometrics opt-in ----------------------------------------------

enum OnboardingMobileBiometricsMethod { faceId, touchId, fingerprint }

/// Whether the escrow write is in flight. Both buttons disable while it is,
/// which is the only visible difference.
enum OnboardingMobileBiometricsState { offered, enabling }

Widget buildOnboardingMobileBiometricsGalleryCase(BuildContext context) {
  final method = wbStateKnob<OnboardingMobileBiometricsMethod>(
    context,
    label: 'Method',
    options: OnboardingMobileBiometricsMethod.values,
    labelBuilder: onboardingMobileBiometricsMethodLabel,
  );
  final state = wbStateKnob<OnboardingMobileBiometricsState>(
    context,
    label: 'State',
    options: OnboardingMobileBiometricsState.values,
    labelBuilder: onboardingMobileBiometricsStateLabel,
  );
  if (state == OnboardingMobileBiometricsState.enabling) {
    return onboardingMobileBiometricsEnablingFixture(
      biometric: onboardingMobileBiometricsKind(method),
    );
  }
  return switch (method) {
    OnboardingMobileBiometricsMethod.faceId => buildMobileFaceIdOptInUseCase(
      context,
    ),
    OnboardingMobileBiometricsMethod.touchId => buildMobileTouchIdOptInUseCase(
      context,
    ),
    OnboardingMobileBiometricsMethod.fingerprint =>
      buildMobileFingerprintOptInUseCase(context),
  };
}

String onboardingMobileBiometricsMethodLabel(
  OnboardingMobileBiometricsMethod method,
) {
  return switch (method) {
    OnboardingMobileBiometricsMethod.faceId => 'Face ID',
    OnboardingMobileBiometricsMethod.touchId => 'Touch ID',
    OnboardingMobileBiometricsMethod.fingerprint => 'Fingerprint',
  };
}

String onboardingMobileBiometricsStateLabel(
  OnboardingMobileBiometricsState state,
) {
  return switch (state) {
    OnboardingMobileBiometricsState.offered => 'Offered',
    OnboardingMobileBiometricsState.enabling => 'Turning on',
  };
}

BiometricKind onboardingMobileBiometricsKind(
  OnboardingMobileBiometricsMethod method,
) {
  return switch (method) {
    OnboardingMobileBiometricsMethod.faceId => BiometricKind.face,
    OnboardingMobileBiometricsMethod.touchId => BiometricKind.touchId,
    OnboardingMobileBiometricsMethod.fingerprint => BiometricKind.fingerprint,
  };
}

// --- Mobile import ---------------------------------------------------------

enum OnboardingMobileImportPasteState { idle, clipboardError }

Widget buildOnboardingMobileImportPasteGalleryCase(BuildContext context) {
  final state = wbStateKnob<OnboardingMobileImportPasteState>(
    context,
    label: 'State',
    options: OnboardingMobileImportPasteState.values,
    labelBuilder: onboardingMobileImportPasteStateLabel,
  );
  return switch (state) {
    OnboardingMobileImportPasteState.idle => buildMobileImportPasteUseCase(
      context,
    ),
    OnboardingMobileImportPasteState.clipboardError =>
      buildMobileImportPasteErrorUseCase(context),
  };
}

String onboardingMobileImportPasteStateLabel(
  OnboardingMobileImportPasteState state,
) {
  return switch (state) {
    OnboardingMobileImportPasteState.idle => 'Idle',
    OnboardingMobileImportPasteState.clipboardError => "Can't read clipboard",
  };
}

enum OnboardingMobileImportManualEntry {
  empty,
  typing,
  invalidWord,
  wordsAccepted,
}

Widget buildOnboardingMobileImportManualGalleryCase(BuildContext context) {
  final entry = wbStateKnob<OnboardingMobileImportManualEntry>(
    context,
    label: 'Entry',
    options: OnboardingMobileImportManualEntry.values,
    labelBuilder: onboardingMobileImportManualEntryLabel,
  );
  return switch (entry) {
    OnboardingMobileImportManualEntry.empty =>
      buildMobileImportManualEmptyUseCase(context),
    OnboardingMobileImportManualEntry.typing =>
      buildMobileImportManualTypingUseCase(context),
    OnboardingMobileImportManualEntry.invalidWord =>
      buildMobileImportManualErrorUseCase(context),
    OnboardingMobileImportManualEntry.wordsAccepted =>
      buildMobileImportManualDoneUseCase(context),
  };
}

String onboardingMobileImportManualEntryLabel(
  OnboardingMobileImportManualEntry entry,
) {
  return switch (entry) {
    OnboardingMobileImportManualEntry.empty => 'Empty',
    OnboardingMobileImportManualEntry.typing => 'Typing',
    OnboardingMobileImportManualEntry.invalidWord => 'Invalid word',
    OnboardingMobileImportManualEntry.wordsAccepted => 'Words accepted',
  };
}

enum OnboardingMobileImportWords { twelve, fifteen, eighteen, twentyFour }

Widget buildOnboardingMobileImportReviewGalleryCase(BuildContext context) {
  final words = wbStateKnob<OnboardingMobileImportWords>(
    context,
    label: 'Words',
    options: OnboardingMobileImportWords.values,
    labelBuilder: onboardingMobileImportWordsLabel,
  );
  return switch (words) {
    OnboardingMobileImportWords.twelve => buildMobileImportReview12UseCase(
      context,
    ),
    OnboardingMobileImportWords.fifteen => buildMobileImportReview15UseCase(
      context,
    ),
    OnboardingMobileImportWords.eighteen => buildMobileImportReview18UseCase(
      context,
    ),
    OnboardingMobileImportWords.twentyFour => buildMobileImportReview24UseCase(
      context,
    ),
  };
}

String onboardingMobileImportWordsLabel(OnboardingMobileImportWords words) {
  return switch (words) {
    OnboardingMobileImportWords.twelve => '12 words',
    OnboardingMobileImportWords.fifteen => '15 words',
    OnboardingMobileImportWords.eighteen => '18 words',
    OnboardingMobileImportWords.twentyFour => '24 words',
  };
}

// --- Keystone --------------------------------------------------------------

/// Camera states the Keystone scan fixtures cover; `unavailable` has no
/// fixture, so it is deliberately absent.
enum OnboardingKeystoneCamera { requesting, denied, active, loading }

/// The desktop half is the real scanner card, whose `Camera` and `Scan` axes
/// live with the other scanner cases in `scanner_gallery.dart`; the mobile
/// screen has its own forced-camera fixtures.
Widget buildOnboardingKeystoneScanGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.desktop) {
    return buildScannerKeystoneOnboardingGalleryCase(context);
  }
  final camera = wbStateKnob<OnboardingKeystoneCamera>(
    context,
    label: 'Camera',
    options: OnboardingKeystoneCamera.values,
    labelBuilder: onboardingKeystoneCameraLabel,
  );
  return switch (camera) {
    OnboardingKeystoneCamera.requesting =>
      buildMobileKeystoneScanRequestingUseCase(context),
    OnboardingKeystoneCamera.denied => buildMobileKeystoneScanDeniedUseCase(
      context,
    ),
    OnboardingKeystoneCamera.active => buildMobileKeystoneScanActiveUseCase(
      context,
    ),
    OnboardingKeystoneCamera.loading => buildMobileKeystoneScanLoadingUseCase(
      context,
    ),
  };
}

String onboardingKeystoneCameraLabel(OnboardingKeystoneCamera camera) {
  return switch (camera) {
    OnboardingKeystoneCamera.requesting => 'Requesting',
    OnboardingKeystoneCamera.denied => 'Denied',
    OnboardingKeystoneCamera.active => 'Active',
    OnboardingKeystoneCamera.loading => 'Loading',
  };
}

enum OnboardingKeystoneQrRendering { standard, scanOptimized }

Widget buildOnboardingKeystonePcztQrGalleryCase(BuildContext context) {
  final rendering = wbStateKnob<OnboardingKeystoneQrRendering>(
    context,
    label: 'Rendering',
    options: OnboardingKeystoneQrRendering.values,
    labelBuilder: onboardingKeystoneQrRenderingLabel,
  );
  return switch (rendering) {
    OnboardingKeystoneQrRendering.standard =>
      buildMobileKeystonePcztQrDefaultUseCase(context),
    OnboardingKeystoneQrRendering.scanOptimized =>
      buildMobileKeystonePcztQrOptimizedUseCase(context),
  };
}

String onboardingKeystoneQrRenderingLabel(
  OnboardingKeystoneQrRendering rendering,
) {
  return switch (rendering) {
    OnboardingKeystoneQrRendering.standard => 'Standard',
    OnboardingKeystoneQrRendering.scanOptimized => 'Scan optimised',
  };
}

enum OnboardingKeystoneSigningPhase { loading, qrReady, scanner }

/// The Keystone signing surface of both lanes: desktop signs in the modal,
/// mobile in the full-screen flow (the payment-link overlay picks between the
/// two on `kAppFormFactor`). The modal varies on its action slots and
/// instruction line, the mobile flow only on its phase, so each lane registers
/// its own axes.
Widget buildOnboardingKeystoneSigningGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.desktop) {
    return _onboardingKeystoneSigningModal(context);
  }
  final phase = wbStateKnob<OnboardingKeystoneSigningPhase>(
    context,
    label: 'Phase',
    options: OnboardingKeystoneSigningPhase.values,
    labelBuilder: onboardingKeystoneSigningPhaseLabel,
  );
  return switch (phase) {
    OnboardingKeystoneSigningPhase.loading =>
      buildMobileKeystoneSigningLoadingUseCase(context),
    OnboardingKeystoneSigningPhase.qrReady =>
      buildMobileKeystoneSigningReadyUseCase(context),
    OnboardingKeystoneSigningPhase.scanner =>
      buildMobileKeystoneSigningScannerUseCase(context),
  };
}

String onboardingKeystoneSigningPhaseLabel(
  OnboardingKeystoneSigningPhase phase,
) {
  return switch (phase) {
    OnboardingKeystoneSigningPhase.loading => 'Preparing',
    OnboardingKeystoneSigningPhase.qrReady => 'QR ready',
    OnboardingKeystoneSigningPhase.scanner => 'Scanning signature',
  };
}

// --- Import: wallet birthday -----------------------------------------------

/// Whether the endpoint answered the birthday metadata load. The estimate and
/// submit states below it are private `State`, so they are not options here.
enum OnboardingImportBirthdayMetadata { loaded, failed }

Widget buildOnboardingImportBirthdayGalleryCase(BuildContext context) {
  final tab = wbStateKnob<ImportBirthdayTab>(
    context,
    label: 'Tab',
    options: ImportBirthdayTab.values,
    labelBuilder: onboardingImportBirthdayTabLabel,
  );
  final metadata = wbStateKnob<OnboardingImportBirthdayMetadata>(
    context,
    label: 'Metadata',
    options: OnboardingImportBirthdayMetadata.values,
    labelBuilder: onboardingImportBirthdayMetadataLabel,
  );
  return importWalletBirthdayFixture(
    tab: tab,
    metadataLoaded: metadata == OnboardingImportBirthdayMetadata.loaded,
  );
}

String onboardingImportBirthdayTabLabel(ImportBirthdayTab tab) {
  return switch (tab) {
    ImportBirthdayTab.date => 'Date',
    ImportBirthdayTab.blockHeight => 'Block height',
  };
}

String onboardingImportBirthdayMetadataLabel(
  OnboardingImportBirthdayMetadata metadata,
) {
  return switch (metadata) {
    OnboardingImportBirthdayMetadata.loaded => 'Loaded',
    OnboardingImportBirthdayMetadata.failed => "Couldn't load",
  };
}

// --- Import: account discovery ---------------------------------------------

/// Row counts worth previewing: one, a short list, and past the three rows
/// that turn the scrollbar gutter on.
enum OnboardingImportDiscoveryAccounts { one, three, eight }

Widget buildOnboardingImportDiscoveryGalleryCase(BuildContext context) {
  final accounts = wbStateKnob<OnboardingImportDiscoveryAccounts>(
    context,
    label: 'Accounts',
    options: OnboardingImportDiscoveryAccounts.values,
    labelBuilder: onboardingImportDiscoveryAccountsLabel,
    initial: OnboardingImportDiscoveryAccounts.three,
  );
  final balance = wbStateKnob<OnboardingImportDiscoveryBalance>(
    context,
    label: 'Balance',
    options: OnboardingImportDiscoveryBalance.values,
    labelBuilder: onboardingImportDiscoveryBalanceLabel,
    initial: OnboardingImportDiscoveryBalance.loaded,
  );
  // Every row starts selected, so this only shows once the user switches them
  // all off: it decides whether Import stays enabled with nothing selected.
  final allowEmptySelection = wbBoolKnob(
    context,
    label: 'Allow empty selection',
    initial: true,
  );
  return importAccountDiscoveryFixture(
    accountCount: onboardingImportDiscoveryAccountCount(accounts),
    balance: balance,
    allowEmptySelection: allowEmptySelection,
    layout: wbLayoutKnob(context),
  );
}

int onboardingImportDiscoveryAccountCount(
  OnboardingImportDiscoveryAccounts accounts,
) {
  return switch (accounts) {
    OnboardingImportDiscoveryAccounts.one => 1,
    OnboardingImportDiscoveryAccounts.three => 3,
    OnboardingImportDiscoveryAccounts.eight => 8,
  };
}

String onboardingImportDiscoveryAccountsLabel(
  OnboardingImportDiscoveryAccounts accounts,
) {
  return switch (accounts) {
    OnboardingImportDiscoveryAccounts.one => '1 account',
    OnboardingImportDiscoveryAccounts.three => '3 accounts',
    OnboardingImportDiscoveryAccounts.eight => '8 accounts',
  };
}

String onboardingImportDiscoveryBalanceLabel(
  OnboardingImportDiscoveryBalance balance,
) {
  return switch (balance) {
    OnboardingImportDiscoveryBalance.loading => 'Loading',
    OnboardingImportDiscoveryBalance.loaded => 'Loaded',
    OnboardingImportDiscoveryBalance.failed => "Couldn't load",
  };
}

// --- Import: birthday calendar ---------------------------------------------

/// The desktop pane overlay, or the bare panel the mobile birthday sheet
/// reuses.
enum OnboardingBirthdayCalendarPresentation { overlay, panel }

Widget buildOnboardingBirthdayCalendarGalleryCase(BuildContext context) {
  final presentation = wbStateKnob<OnboardingBirthdayCalendarPresentation>(
    context,
    label: 'Presentation',
    options: OnboardingBirthdayCalendarPresentation.values,
    labelBuilder: onboardingBirthdayCalendarPresentationLabel,
  );
  final range = wbStateKnob<OnboardingBirthdayCalendarRange>(
    context,
    label: 'Range',
    options: OnboardingBirthdayCalendarRange.values,
    labelBuilder: onboardingBirthdayCalendarRangeLabel,
  );
  return importBirthdayCalendarFixture(
    asOverlay: presentation == OnboardingBirthdayCalendarPresentation.overlay,
    range: range,
  );
}

String onboardingBirthdayCalendarPresentationLabel(
  OnboardingBirthdayCalendarPresentation presentation,
) {
  return switch (presentation) {
    OnboardingBirthdayCalendarPresentation.overlay => 'Overlay',
    OnboardingBirthdayCalendarPresentation.panel => 'Panel',
  };
}

String onboardingBirthdayCalendarRangeLabel(
  OnboardingBirthdayCalendarRange range,
) {
  return switch (range) {
    OnboardingBirthdayCalendarRange.midRange => 'Mid range',
    OnboardingBirthdayCalendarRange.earliest => 'At earliest date',
    OnboardingBirthdayCalendarRange.latest => 'At latest date',
  };
}

// --- Import: unknown birthday height ---------------------------------------

Widget buildOnboardingUnknownBirthdayGalleryCase(BuildContext context) {
  return importBirthdayUnknownHeightFixture(layout: wbLayoutKnob(context));
}

// --- Keystone: pairing steps -----------------------------------------------

Widget buildOnboardingKeystoneIntroGalleryCase(BuildContext context) {
  return wbLayoutKnob(context) == WbLayout.mobile
      ? buildMobileKeystoneConnectUseCase(context)
      : keystoneHowToConnectFixture();
}

/// How many accounts the device sent. Only the desktop picker can be driven
/// to a count: the mobile step has a single four-account fixture.
enum OnboardingKeystoneAccounts { none, one, four }

/// Which discovered account is selected; nothing selected is the state the
/// screen opens in when the device sent an account it cannot preselect.
enum OnboardingKeystoneSelection { none, first, last }

Widget buildOnboardingKeystoneSelectAccountGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return buildMobileKeystoneSelectAccountUseCase(context);
  }
  final accounts = wbStateKnob<OnboardingKeystoneAccounts>(
    context,
    label: 'Accounts',
    options: OnboardingKeystoneAccounts.values,
    labelBuilder: onboardingKeystoneAccountsLabel,
    initial: OnboardingKeystoneAccounts.four,
  );
  final selection = wbStateKnob<OnboardingKeystoneSelection>(
    context,
    label: 'Selection',
    options: OnboardingKeystoneSelection.values,
    labelBuilder: onboardingKeystoneSelectionLabel,
    initial: OnboardingKeystoneSelection.first,
  );
  final count = onboardingKeystoneAccountCount(accounts);
  return keystoneSelectAccountFixture(
    accountCount: count,
    // An empty account list has no index to select, whichever option the
    // independent Selection dropdown is on.
    selectedIndex: count == 0
        ? null
        : switch (selection) {
            OnboardingKeystoneSelection.none => null,
            OnboardingKeystoneSelection.first => 0,
            OnboardingKeystoneSelection.last => count - 1,
          },
  );
}

int onboardingKeystoneAccountCount(OnboardingKeystoneAccounts accounts) {
  return switch (accounts) {
    OnboardingKeystoneAccounts.none => 0,
    OnboardingKeystoneAccounts.one => 1,
    OnboardingKeystoneAccounts.four => 4,
  };
}

String onboardingKeystoneAccountsLabel(OnboardingKeystoneAccounts accounts) {
  return switch (accounts) {
    OnboardingKeystoneAccounts.none => 'None found',
    OnboardingKeystoneAccounts.one => '1 account',
    OnboardingKeystoneAccounts.four => '4 accounts',
  };
}

String onboardingKeystoneSelectionLabel(OnboardingKeystoneSelection selection) {
  return switch (selection) {
    OnboardingKeystoneSelection.none => 'None',
    OnboardingKeystoneSelection.first => 'First',
    OnboardingKeystoneSelection.last => 'Last',
  };
}

/// Whether the endpoint answered the Keystone birthday metadata load. A
/// pending load has no option of its own: the step shows no spinner and no
/// disabled control while it waits, so it renders exactly like 'Loaded'.
enum OnboardingKeystoneBirthdayMetadata { loaded, failed }

/// Metadata is the one axis a preview can drive, and only on desktop: the tab
/// and the date estimate are private `State` the screen only changes on a tap,
/// the estimate still calls `ImportBirthdayEstimator.estimateBirthdayHeight`
/// with no seam, and the mobile step's fixture pins the load off.
Widget buildOnboardingKeystoneBirthdayGalleryCase(BuildContext context) {
  if (wbLayoutKnob(context) == WbLayout.mobile) {
    return buildMobileKeystoneBirthdayUseCase(context);
  }
  final metadata = wbStateKnob<OnboardingKeystoneBirthdayMetadata>(
    context,
    label: 'Metadata',
    options: OnboardingKeystoneBirthdayMetadata.values,
    labelBuilder: onboardingKeystoneBirthdayMetadataLabel,
  );
  return keystoneWalletBirthdayFixture(
    metadataLoaded: metadata == OnboardingKeystoneBirthdayMetadata.loaded,
  );
}

String onboardingKeystoneBirthdayMetadataLabel(
  OnboardingKeystoneBirthdayMetadata metadata,
) {
  return switch (metadata) {
    OnboardingKeystoneBirthdayMetadata.loaded => 'Loaded',
    OnboardingKeystoneBirthdayMetadata.failed => "Couldn't load",
  };
}

// --- Keystone: transaction progress ----------------------------------------

/// Fixture-selection axis: the standalone panel the send/swap status screens
/// show, or the blurred overlay the scanner draws over its viewport.
enum OnboardingKeystoneProgressPresentation { panel, overlay }

/// The two labels production passes into these widgets.
enum OnboardingKeystoneProgressLabel { submitting, readingQr }

Widget buildOnboardingKeystoneProgressGalleryCase(BuildContext context) {
  final presentation = wbStateKnob<OnboardingKeystoneProgressPresentation>(
    context,
    label: 'Presentation',
    options: OnboardingKeystoneProgressPresentation.values,
    labelBuilder: onboardingKeystoneProgressPresentationLabel,
  );
  final label = wbStateKnob<OnboardingKeystoneProgressLabel>(
    context,
    label: 'Label',
    options: OnboardingKeystoneProgressLabel.values,
    labelBuilder: onboardingKeystoneProgressLabelLabel,
  );
  // Panel only: the overlay has no camera row.
  final cameraRow = wbBoolKnob(context, label: 'Camera row');
  return keystoneTransactionProgressFixture(
    asOverlay: presentation == OnboardingKeystoneProgressPresentation.overlay,
    label: onboardingKeystoneProgressLabelText(label),
    showCameraRow: cameraRow,
  );
}

String onboardingKeystoneProgressPresentationLabel(
  OnboardingKeystoneProgressPresentation presentation,
) {
  return switch (presentation) {
    OnboardingKeystoneProgressPresentation.panel => 'Panel',
    OnboardingKeystoneProgressPresentation.overlay => 'Scanner overlay',
  };
}

String onboardingKeystoneProgressLabelText(
  OnboardingKeystoneProgressLabel label,
) {
  return switch (label) {
    OnboardingKeystoneProgressLabel.submitting => 'Submitting the transaction',
    OnboardingKeystoneProgressLabel.readingQr => 'Reading QR...',
  };
}

String onboardingKeystoneProgressLabelLabel(
  OnboardingKeystoneProgressLabel label,
) {
  return switch (label) {
    OnboardingKeystoneProgressLabel.submitting => 'Submitting',
    OnboardingKeystoneProgressLabel.readingQr => 'Reading QR',
  };
}

// --- Keystone: signing modal -----------------------------------------------

/// Which of the modal's two action slots are filled; production fills both on
/// send, and one or none on the flows that cannot cancel mid-round.
enum OnboardingKeystoneSigningActions { both, primaryOnly, secondaryOnly, none }

Widget _onboardingKeystoneSigningModal(BuildContext context) {
  final phase = wbStateKnob<KeystoneSigningModalPhase>(
    context,
    label: 'Phase',
    options: KeystoneSigningModalPhase.values,
    labelBuilder: onboardingKeystoneSigningModalPhaseLabel,
    initial: KeystoneSigningModalPhase.ready,
  );
  final actions = wbStateKnob<OnboardingKeystoneSigningActions>(
    context,
    label: 'Actions',
    options: OnboardingKeystoneSigningActions.values,
    labelBuilder: onboardingKeystoneSigningActionsLabel,
  );
  final instruction = wbBoolKnob(context, label: 'Instruction', initial: true);
  return keystoneSigningModalFixture(
    phase: phase,
    showPrimary:
        actions == OnboardingKeystoneSigningActions.both ||
        actions == OnboardingKeystoneSigningActions.primaryOnly,
    showSecondary:
        actions == OnboardingKeystoneSigningActions.both ||
        actions == OnboardingKeystoneSigningActions.secondaryOnly,
    showInstruction: instruction,
  );
}

String onboardingKeystoneSigningModalPhaseLabel(
  KeystoneSigningModalPhase phase,
) {
  return switch (phase) {
    KeystoneSigningModalPhase.preparing => 'Preparing',
    KeystoneSigningModalPhase.ready => 'QR ready',
    KeystoneSigningModalPhase.failed => 'Failed',
  };
}

String onboardingKeystoneSigningActionsLabel(
  OnboardingKeystoneSigningActions actions,
) {
  return switch (actions) {
    OnboardingKeystoneSigningActions.both => 'Both',
    OnboardingKeystoneSigningActions.primaryOnly => 'Primary only',
    OnboardingKeystoneSigningActions.secondaryOnly => 'Secondary only',
    OnboardingKeystoneSigningActions.none => 'None',
  };
}

// --- Mobile welcome / method selection -------------------------------------

/// Where the mobile welcome screen was opened from: the first run has no back
/// affordance, `/add-account` returns to the wallet that already exists.
enum OnboardingMobileWelcomeEntry { firstRun, addAccount }

Widget _onboardingMobileWelcome(BuildContext context) {
  final entry = wbStateKnob<OnboardingMobileWelcomeEntry>(
    context,
    label: 'Entry',
    options: OnboardingMobileWelcomeEntry.values,
    labelBuilder: onboardingMobileWelcomeEntryLabel,
  );
  return onboardingMobileWelcomeFixture(
    showBackButton: entry == OnboardingMobileWelcomeEntry.addAccount,
  );
}

String onboardingMobileWelcomeEntryLabel(OnboardingMobileWelcomeEntry entry) {
  return switch (entry) {
    OnboardingMobileWelcomeEntry.firstRun => 'First run',
    OnboardingMobileWelcomeEntry.addAccount => 'Add account',
  };
}

// --- Mobile wallet link ----------------------------------------------------

/// Camera access the scan card is showing. The screen's preview seam forces
/// the state, so no option reaches a real camera.
enum OnboardingWalletLinkCamera { requesting, denied, unavailable, active }

/// Which failure card replaces the scanner. Anything but `none` hides the
/// camera entirely, so it outranks the other two axes.
enum OnboardingWalletLinkScanErrorCase { none, invalid, expired, failed }

Widget buildOnboardingWalletLinkScanGalleryCase(BuildContext context) {
  final camera = wbStateKnob<OnboardingWalletLinkCamera>(
    context,
    label: 'Camera',
    options: OnboardingWalletLinkCamera.values,
    labelBuilder: onboardingWalletLinkCameraLabel,
    initial: OnboardingWalletLinkCamera.active,
  );
  final error = wbStateKnob<OnboardingWalletLinkScanErrorCase>(
    context,
    label: 'Error',
    options: OnboardingWalletLinkScanErrorCase.values,
    labelBuilder: onboardingWalletLinkScanErrorLabel,
  );
  // 'Reading link' is the caption the live camera swaps in while the scanned
  // package is fetched, so it only says something on the active card.
  final loading = wbBoolKnob(context, label: 'Reading link');
  return onboardingMobileWalletLinkScanFixture(
    camera: switch (camera) {
      OnboardingWalletLinkCamera.requesting => AddressQrCameraStatus.requesting,
      OnboardingWalletLinkCamera.denied => AddressQrCameraStatus.denied,
      OnboardingWalletLinkCamera.unavailable =>
        AddressQrCameraStatus.unavailable,
      OnboardingWalletLinkCamera.active => AddressQrCameraStatus.active,
    },
    error: switch (error) {
      OnboardingWalletLinkScanErrorCase.none => null,
      OnboardingWalletLinkScanErrorCase.invalid =>
        MobileWalletLinkScanError.invalid,
      OnboardingWalletLinkScanErrorCase.expired =>
        MobileWalletLinkScanError.expired,
      OnboardingWalletLinkScanErrorCase.failed =>
        MobileWalletLinkScanError.failed,
    },
    loading: loading,
  );
}

String onboardingWalletLinkCameraLabel(OnboardingWalletLinkCamera camera) {
  return switch (camera) {
    OnboardingWalletLinkCamera.requesting => 'Requesting',
    OnboardingWalletLinkCamera.denied => 'Denied',
    OnboardingWalletLinkCamera.unavailable => 'Unavailable',
    OnboardingWalletLinkCamera.active => 'Active',
  };
}

String onboardingWalletLinkScanErrorLabel(
  OnboardingWalletLinkScanErrorCase error,
) {
  return switch (error) {
    OnboardingWalletLinkScanErrorCase.none => 'None',
    OnboardingWalletLinkScanErrorCase.invalid => 'Invalid QR code',
    OnboardingWalletLinkScanErrorCase.expired => 'Link expired',
    OnboardingWalletLinkScanErrorCase.failed => "Couldn't open this link",
  };
}

/// What the scanned desktop package holds. 'Nothing to import' is the payload
/// with neither an account nor a contact left, which is its own card.
enum OnboardingWalletLinkAccounts {
  nothingToImport,
  pendingOnly,
  alreadyImportedOnly,
  mixed,
}

/// How many of the pending rows are ticked, which decides the button label
/// and whether the section action reads 'Select all' or 'Deselect all'.
enum OnboardingWalletLinkSelection { none, partial, all }

/// Which of the two steps is showing. Both are the same
/// `_WalletLinkSelectionScaffold` over a different row list, so the payload
/// and selection axes apply to whichever list is on screen.
enum OnboardingWalletLinkList { accounts, contacts }

Widget buildOnboardingWalletLinkAccountsGalleryCase(BuildContext context) {
  final list = wbStateKnob<OnboardingWalletLinkList>(
    context,
    label: 'List',
    options: OnboardingWalletLinkList.values,
    labelBuilder: onboardingWalletLinkListLabel,
  );
  final accounts = wbStateKnob<OnboardingWalletLinkAccounts>(
    context,
    label: 'Payload',
    options: OnboardingWalletLinkAccounts.values,
    labelBuilder: onboardingWalletLinkAccountsLabel,
    initial: OnboardingWalletLinkAccounts.mixed,
  );
  final selection = wbStateKnob<OnboardingWalletLinkSelection>(
    context,
    label: 'Selection',
    options: OnboardingWalletLinkSelection.values,
    labelBuilder: onboardingWalletLinkSelectionLabel,
    initial: OnboardingWalletLinkSelection.all,
  );
  final submitting = wbBoolKnob(context, label: 'Submitting');

  final rowCount = list == OnboardingWalletLinkList.accounts
      ? onboardingMobileWalletLinkAccountCount
      : onboardingMobileWalletLinkContactCount;
  final alreadyImportedCount = switch (accounts) {
    OnboardingWalletLinkAccounts.nothingToImport => 0,
    OnboardingWalletLinkAccounts.pendingOnly => 0,
    OnboardingWalletLinkAccounts.alreadyImportedOnly => rowCount,
    OnboardingWalletLinkAccounts.mixed => 1,
  };
  final hasRows = accounts != OnboardingWalletLinkAccounts.nothingToImport;
  final selectedCount = switch (selection) {
    OnboardingWalletLinkSelection.none => 0,
    OnboardingWalletLinkSelection.partial => 1,
    OnboardingWalletLinkSelection.all => rowCount - alreadyImportedCount,
  };

  if (list == OnboardingWalletLinkList.contacts) {
    return onboardingMobileWalletLinkContactsFixture(
      hasContacts: hasRows,
      alreadyImportedCount: alreadyImportedCount,
      selectedCount: selectedCount,
      submitting: submitting,
    );
  }
  return onboardingMobileWalletLinkAccountsFixture(
    hasAccounts: hasRows,
    alreadyImportedCount: alreadyImportedCount,
    selectedCount: selectedCount,
    submitting: submitting,
  );
}

String onboardingWalletLinkListLabel(OnboardingWalletLinkList list) {
  return switch (list) {
    OnboardingWalletLinkList.accounts => 'Accounts',
    OnboardingWalletLinkList.contacts => 'Contacts',
  };
}

String onboardingWalletLinkAccountsLabel(OnboardingWalletLinkAccounts value) {
  return switch (value) {
    OnboardingWalletLinkAccounts.nothingToImport => 'Nothing to import',
    OnboardingWalletLinkAccounts.pendingOnly => 'Ready to import',
    OnboardingWalletLinkAccounts.alreadyImportedOnly => 'Already imported',
    OnboardingWalletLinkAccounts.mixed => 'Mixed',
  };
}

String onboardingWalletLinkSelectionLabel(OnboardingWalletLinkSelection value) {
  return switch (value) {
    OnboardingWalletLinkSelection.none => 'None selected',
    OnboardingWalletLinkSelection.partial => 'Some selected',
    OnboardingWalletLinkSelection.all => 'All selected',
  };
}

// --- Onboarding shell / sidebar / pane chrome / auth shell -----------------

Widget buildOnboardingCreateShellGalleryCase(BuildContext context) {
  final step = wbStateKnob<OnboardingStep>(
    context,
    label: 'Step',
    options: OnboardingStep.values,
    labelBuilder: (step) => step.label,
    initial: OnboardingStep.secretPassphrase,
  );
  final showPasswordStep = wbBoolKnob(
    context,
    label: 'Show password step',
    initial: true,
  );
  final passphraseRevealed = wbBoolKnob(context, label: 'Passphrase revealed');
  return onboardingCreateShellFixture(
    step: step,
    showPasswordStep: showPasswordStep,
    passphraseRevealed: passphraseRevealed,
  );
}

Widget buildOnboardingImportShellGalleryCase(BuildContext context) {
  final step = wbStateKnob<ImportOnboardingStep>(
    context,
    label: 'Step',
    options: ImportOnboardingStep.values,
    labelBuilder: (step) => step.label,
  );
  final showPasswordStep = wbBoolKnob(
    context,
    label: 'Show password step',
    initial: true,
  );
  return onboardingImportShellFixture(
    step: step,
    showPasswordStep: showPasswordStep,
  );
}

Widget buildOnboardingKeystoneShellGalleryCase(BuildContext context) {
  final step = wbStateKnob<KeystoneOnboardingStep>(
    context,
    label: 'Step',
    options: KeystoneOnboardingStep.values,
    labelBuilder: (step) => step.label,
  );
  final showPasswordStep = wbBoolKnob(
    context,
    label: 'Show password step',
    initial: true,
  );
  return onboardingKeystoneShellFixture(
    step: step,
    showPasswordStep: showPasswordStep,
  );
}

Widget buildOnboardingSidebarGalleryCase(BuildContext context) {
  final flow = wbStateKnob<OnboardingSidebarFlow>(
    context,
    label: 'Flow',
    options: OnboardingSidebarFlow.values,
    labelBuilder: onboardingSidebarFlowLabel,
  );
  final active = wbStateKnob<OnboardingSidebarActive>(
    context,
    label: 'Active step',
    options: OnboardingSidebarActive.values,
    labelBuilder: onboardingSidebarActiveLabel,
  );
  // The real flows never pass `onTap`; the slot exists, so the click cursor it
  // adds is worth seeing.
  final tappable = wbBoolKnob(context, label: 'Tappable steps');
  return onboardingSidebarFixture(
    flow: flow,
    active: active,
    tappable: tappable,
  );
}

String onboardingSidebarFlowLabel(OnboardingSidebarFlow flow) {
  return switch (flow) {
    OnboardingSidebarFlow.create => 'Create wallet',
    OnboardingSidebarFlow.importWallet => 'Import wallet',
    OnboardingSidebarFlow.keystone => 'Keystone',
  };
}

String onboardingSidebarActiveLabel(OnboardingSidebarActive active) {
  return switch (active) {
    OnboardingSidebarActive.first => 'First step',
    OnboardingSidebarActive.middle => 'Middle step',
    OnboardingSidebarActive.last => 'Last step',
  };
}

Widget buildOnboardingPaneChromeGalleryCase(BuildContext context) {
  final back = wbStateKnob<OnboardingPaneBack>(
    context,
    label: 'Back link',
    options: OnboardingPaneBack.values,
    labelBuilder: onboardingPaneBackLabel,
  );
  final withOverlay = wbBoolKnob(context, label: 'Overlay');
  return onboardingPaneChromeFixture(back: back, withOverlay: withOverlay);
}

String onboardingPaneBackLabel(OnboardingPaneBack back) {
  return switch (back) {
    OnboardingPaneBack.route => 'Goes to a route',
    OnboardingPaneBack.callback => 'Runs a callback',
    OnboardingPaneBack.none => 'No back link',
  };
}

/// Not lane-gated: the shell only lays a fixed-size card out, and the preview
/// card holds a placeholder, so no token set can overflow it.
Widget buildOnboardingAuthShellGalleryCase(BuildContext context) {
  final box = wbStateKnob<OnboardingAuthCardBox>(
    context,
    label: 'Card',
    options: OnboardingAuthCardBox.values,
    labelBuilder: onboardingAuthCardBoxLabel,
  );
  final compactPadding = wbBoolKnob(context, label: 'Compact padding');
  return onboardingAuthShellFixture(box: box, compactPadding: compactPadding);
}

String onboardingAuthCardBoxLabel(OnboardingAuthCardBox box) {
  return switch (box) {
    OnboardingAuthCardBox.unlock => 'Unlock',
    OnboardingAuthCardBox.lostPassword => 'Lost password',
    OnboardingAuthCardBox.custom => 'Custom',
  };
}

// --- Keystone: scan help ---------------------------------------------------

Widget buildOnboardingKeystoneScanHelpGalleryCase(BuildContext context) {
  final visible = wbBoolKnob(context, label: 'Visible', initial: true);
  return keystoneScanHelpFixture(visible: visible);
}

// --- Onboarding components -------------------------------------------------

Widget buildOnboardingSeedCardGalleryCase(BuildContext context) {
  final words = wbStateKnob<OnboardingSeedCardWords>(
    context,
    label: 'Words',
    options: OnboardingSeedCardWords.values,
    labelBuilder: onboardingSeedCardWordsLabel,
    initial: OnboardingSeedCardWords.twentyFour,
  );
  final obscured = wbBoolKnob(context, label: 'Obscured');
  final copy = wbStateKnob<OnboardingSeedCardCopy>(
    context,
    label: 'Copy action',
    options: OnboardingSeedCardCopy.values,
    labelBuilder: onboardingSeedCardCopyLabel,
    initial: OnboardingSeedCardCopy.copy,
  );
  final onboardingRowGap = wbBoolKnob(
    context,
    label: 'Onboarding row gap',
    initial: true,
  );
  return onboardingSeedCardFixture(
    words: words,
    obscured: obscured,
    copy: copy,
    onboardingRowGap: onboardingRowGap,
  );
}

String onboardingSeedCardWordsLabel(OnboardingSeedCardWords words) {
  return switch (words) {
    OnboardingSeedCardWords.twelve => '12 words',
    OnboardingSeedCardWords.fifteen => '15 words',
    OnboardingSeedCardWords.eighteen => '18 words',
    OnboardingSeedCardWords.twentyOne => '21 words',
    OnboardingSeedCardWords.twentyFour => '24 words',
  };
}

String onboardingSeedCardCopyLabel(OnboardingSeedCardCopy copy) {
  return switch (copy) {
    OnboardingSeedCardCopy.none => 'Hidden',
    OnboardingSeedCardCopy.copy => 'Copy',
    OnboardingSeedCardCopy.copied => 'Copied',
  };
}

/// How many of the six digits are in. 'Three' is the only partial worth a
/// slot: the dots fill left to right.
enum OnboardingPasscodeFilled { none, three, all }

/// The message under the dots. Both strings are the unlock screen's own.
enum OnboardingPasscodeError { none, incorrectPasscode, openFailed }

Widget buildOnboardingPasscodeFieldGalleryCase(BuildContext context) {
  final filled = wbStateKnob<OnboardingPasscodeFilled>(
    context,
    label: 'Filled',
    options: OnboardingPasscodeFilled.values,
    labelBuilder: onboardingPasscodeFilledLabel,
    initial: OnboardingPasscodeFilled.three,
  );
  final error = wbStateKnob<OnboardingPasscodeError>(
    context,
    label: 'Message',
    options: OnboardingPasscodeError.values,
    labelBuilder: onboardingPasscodeErrorLabel,
  );
  return onboardingPasscodeFieldFixture(
    filled: switch (filled) {
      OnboardingPasscodeFilled.none => 0,
      OnboardingPasscodeFilled.three => 3,
      OnboardingPasscodeFilled.all => 6,
    },
    error: switch (error) {
      OnboardingPasscodeError.none => null,
      OnboardingPasscodeError.incorrectPasscode => 'Incorrect Passcode',
      OnboardingPasscodeError.openFailed =>
        "Couldn't open your wallet. Please try again.",
    },
  );
}

String onboardingPasscodeFilledLabel(OnboardingPasscodeFilled filled) {
  return switch (filled) {
    OnboardingPasscodeFilled.none => 'Empty',
    OnboardingPasscodeFilled.three => '3 of 6',
    OnboardingPasscodeFilled.all => 'All 6',
  };
}

String onboardingPasscodeErrorLabel(OnboardingPasscodeError error) {
  return switch (error) {
    OnboardingPasscodeError.none => 'None',
    OnboardingPasscodeError.incorrectPasscode => 'Incorrect passcode',
    OnboardingPasscodeError.openFailed => "Couldn't open the wallet",
  };
}

Widget buildOnboardingPasscodeKeypadGalleryCase(BuildContext context) {
  final canDelete = wbBoolKnob(context, label: 'Can delete', initial: true);
  final showHelp = wbBoolKnob(context, label: 'Show help', initial: true);
  final enabled = wbBoolKnob(context, label: 'Enabled', initial: true);
  final biometric = wbStateKnob<OnboardingPasscodeBiometric>(
    context,
    label: 'Biometric',
    options: OnboardingPasscodeBiometric.values,
    labelBuilder: onboardingPasscodeBiometricLabel,
    initial: OnboardingPasscodeBiometric.faceId,
  );
  return onboardingPasscodeKeypadFixture(
    canDelete: canDelete,
    showHelp: showHelp,
    enabled: enabled,
    biometric: biometric,
  );
}

String onboardingPasscodeBiometricLabel(OnboardingPasscodeBiometric biometric) {
  return switch (biometric) {
    OnboardingPasscodeBiometric.none => 'No biometric action',
    OnboardingPasscodeBiometric.faceId => 'Face ID',
    OnboardingPasscodeBiometric.touchId => 'Touch ID',
    OnboardingPasscodeBiometric.fingerprint => 'Fingerprint',
  };
}

Widget buildOnboardingStepScaffoldGalleryCase(BuildContext context) {
  final progress = wbStateKnob<OnboardingStepScaffoldProgress>(
    context,
    label: 'Progress',
    options: OnboardingStepScaffoldProgress.values,
    labelBuilder: onboardingStepScaffoldProgressLabel,
  );
  final slots = wbStateKnob<OnboardingStepScaffoldSlots>(
    context,
    label: 'Slots',
    options: OnboardingStepScaffoldSlots.values,
    labelBuilder: onboardingStepScaffoldSlotsLabel,
  );
  final showBackButton = wbBoolKnob(
    context,
    label: 'Show back button',
    initial: true,
  );
  final scrollable = wbBoolKnob(context, label: 'Scrollable', initial: true);
  return onboardingStepScaffoldFixture(
    progress: progress,
    slots: slots,
    showBackButton: showBackButton,
    scrollable: scrollable,
  );
}

String onboardingStepScaffoldProgressLabel(
  OnboardingStepScaffoldProgress progress,
) {
  return switch (progress) {
    OnboardingStepScaffoldProgress.create => 'Create step 3',
    OnboardingStepScaffoldProgress.importWallet => 'Import step 1',
    OnboardingStepScaffoldProgress.walletLink => 'Wallet link intro',
  };
}

String onboardingStepScaffoldSlotsLabel(OnboardingStepScaffoldSlots slots) {
  return switch (slots) {
    OnboardingStepScaffoldSlots.titleOnly => 'Title only',
    OnboardingStepScaffoldSlots.subtitle => 'Title and subtitle',
    OnboardingStepScaffoldSlots.aboveTitleHero => 'Hero above the title',
    OnboardingStepScaffoldSlots.bottomAction => 'Pinned bottom action',
  };
}
