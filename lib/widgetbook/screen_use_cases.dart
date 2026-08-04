// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/privacy/sensitive_privacy_overlay.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/accounts/screens/accounts_screen.dart';
import '../src/features/about/screens/about_screen.dart';
import '../src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../src/features/activity/swap_activity_row_items_provider.dart';
import '../src/features/home/screens/home_screen.dart';
import '../src/features/home/screens/mobile/mobile_home_screen.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/migration/screens/ironwood_migration_flow_screen.dart';
import '../src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import '../src/features/migration/widgets/ironwood_migration_privacy_lock_host.dart';
import '../src/features/migration/widgets/mobile/mobile_ironwood_keystone_signing_view.dart';
import '../src/features/migration/widgets/mobile/mobile_ironwood_migration_announcement_sheet.dart';
import '../src/features/onboarding/lost_password_screen.dart';
import '../src/features/onboarding/import/import_secret_passphrase_screen.dart';
import '../src/features/onboarding/import/import_split_view.dart';
import '../src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import '../src/features/onboarding/mobile/mobile_biometrics_screen.dart';
import '../src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import '../src/features/onboarding/mobile/mobile_import_manual_screen.dart';
import '../src/features/onboarding/mobile/mobile_import_review_screen.dart';
import '../src/features/onboarding/mobile/mobile_import_screens.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart';
import '../src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import '../src/features/onboarding/mobile/mobile_unlock_screen.dart';
import '../src/features/onboarding/create/customise_account_screen.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/settings/screens/settings_change_password_screen.dart';
import '../src/features/settings/screens/settings_endpoint_screen.dart';
import '../src/features/settings/screens/settings_screen.dart';
import '../src/features/settings/screens/settings_seed_phrase_screen.dart';
import '../src/features/settings/screens/settings_uninstall_screen.dart';
import '../src/features/wallet_link/models/wallet_link_models.dart';
import '../src/features/wallet_link/screens/wallet_link_desktop_screen.dart';
import '../src/features/onboarding/unlock_screen.dart';
import '../src/features/onboarding/welcome.dart';
import '../src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/services/biometric_unlock.dart';

const _previewMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse '
    'access accident account accuse achieve acid acoustic acquire across act '
    'action actor actress actual';

const _previewLongWordMnemonic =
    'business question physical security language purchase abstract accident '
    'distance elephant hospital umbrella';
final _previewImportWordList = _previewMnemonic.split(' ');

bool _previewMnemonicValidator(String mnemonic) => mnemonic.isNotEmpty;

const _previewImportReviewMnemonic =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine puzzle sudden modify active effort merit fossil carbon drift '
    'narrow across raise';
const _previewImportReviewMnemonic15 =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine puzzle sudden modify';
const _previewImportReviewMnemonic12 =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine';
const _previewImportReviewMnemonic18 =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine puzzle sudden modify active effort merit';
const _previewErrorToastDuration = Duration(hours: 1);

const _previewManualAcceptedWords = [
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'absent',
  'absorb',
  'abstract',
  'absurd',
  'abuse',
  'access',
];

const _previewManualWordList = [..._previewManualAcceptedWords, 'age', 'agent'];

/// Welcome screen in its large-layout form. Wrapped in a `ProviderScope`
/// with `appLayoutProvider` overridden to a no-op so the dev window does
/// not get reshaped by the screen's on-mount `setMode(large)` call, and
/// in a minimal `GoRouter` so the in-screen `context.go(...)` calls
/// resolve instead of throwing if a reviewer taps a button during the
/// preview.
Widget buildWelcomeLargeUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new),
      networkPrivacyProvider.overrideWith(
        () => _PreviewNetworkPrivacyNotifier(const NetworkPrivacyState.off()),
      ),
    ],
    child: _WelcomeHarness(),
  );
}

Widget buildWelcomeNetworkSettingsUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new),
      networkPrivacyProvider.overrideWith(
        () => _PreviewNetworkPrivacyNotifier(const NetworkPrivacyState.off()),
      ),
    ],
    child: const _WelcomeHarness(showNetworkSettingsInitially: true),
  );
}

Widget buildCustomiseAccountUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(const AccountState()),
      ),
    ],
    child: const _CustomiseAccountHarness(),
  );
}

Widget buildUnlockLoginUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: _UnlockHarness(),
  );
}

Widget buildIronwoodMigrationPrivacyLockUseCase(BuildContext context) {
  return const ProviderScope(child: IronwoodMigrationVirtualUnlockScreen());
}

Widget buildLostPasswordCountdownUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: IgnorePointer(
      child: LostPasswordScreen(
        initialCountdownSeconds: 3,
        countdownEnabled: false,
        onBack: () {},
        onReset: () async {},
      ),
    ),
  );
}

Widget buildLostPasswordEnabledUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: IgnorePointer(
      child: LostPasswordScreen(
        initialCountdownSeconds: 0,
        countdownEnabled: false,
        onBack: () {},
        onReset: () async {},
      ),
    ),
  );
}

Widget buildMobileUnlockPasscodeUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(BiometricUnlockState.initial);
}

Widget buildMobileUnlockFaceIdUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      ),
      enabled: true,
    ),
  );
}

Widget buildMobileUnlockBiometricBackdropUseCase(BuildContext context) {
  return const _MobilePreviewFrame(child: MobileBiometricSignInView());
}

Widget buildMobileUnlockFingerprintUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.fingerprint,
      ),
      enabled: true,
    ),
  );
}

Widget buildMobileCreatePasscodeUseCase(BuildContext context) {
  return _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobilePasscodeScreen(
        args: SetPasswordScreenArgs.create(mnemonic: _previewMnemonic),
      ),
    ),
  );
}

Widget buildMobileCustomiseAccountUseCase(BuildContext context) {
  return _MobilePreviewFrame(
    child: MobileCustomiseAccountScreen(
      args: const CustomiseAccountArgs(
        mnemonic: _previewMnemonic,
        pendingPassword: '123456',
      ),
      random: Random(1234),
      onFinish: (_, _) async {},
    ),
  );
}

Widget buildImportSecretPassphraseUseCase(BuildContext context) {
  return ColoredBox(
    color: context.colors.background.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ],
      child: ImportOnboardingShell(
        activeStep: ImportOnboardingStep.secretPassphrase,
        showPasswordStep: false,
        child: ImportSecretPassphraseScreen(
          wordListOverride: _previewImportWordList,
          mnemonicValidatorOverride: _previewMnemonicValidator,
          useEnvironmentPrivacySignals: false,
        ),
      ),
    ),
  );
}

Widget buildImportSecretPassphrasePopulatedUseCase(BuildContext context) {
  return ColoredBox(
    color: context.colors.background.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ],
      child: ImportOnboardingShell(
        activeStep: ImportOnboardingStep.secretPassphrase,
        showPasswordStep: false,
        child: ImportSecretPassphraseScreen(
          args: const ImportSecretPassphraseArgs(
            mnemonic: _previewMnemonic,
            bip39Passphrase: 'My BIP39 passphrase',
          ),
          wordListOverride: _previewImportWordList,
          mnemonicValidatorOverride: _previewMnemonicValidator,
          useEnvironmentPrivacySignals: false,
        ),
      ),
    ),
  );
}

Widget buildImportSecretPassphraseModalUseCase(BuildContext context) {
  return ColoredBox(
    color: context.colors.background.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ],
      child: ImportOnboardingShell(
        activeStep: ImportOnboardingStep.secretPassphrase,
        showPasswordStep: false,
        child: ImportSecretPassphraseScreen(
          args: const ImportSecretPassphraseArgs(
            mnemonic: _previewMnemonic,
            bip39Passphrase: 'My BIP39 passphrase',
          ),
          wordListOverride: _previewImportWordList,
          mnemonicValidatorOverride: _previewMnemonicValidator,
          initialBip39PassphraseModalOpen: true,
          useEnvironmentPrivacySignals: false,
        ),
      ),
    ),
  );
}

Widget buildMobileImportPasteUseCase(BuildContext context) {
  return const _MobilePreviewFrame(child: _MobileImportHarness());
}

Widget buildMobileImportPasteErrorUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: _MobileImportHarness(initialPasteError: "Can't read the clipboard"),
  );
}

Widget buildMobileImportManualEmptyUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileImportManualScreen(wordListOverride: _previewManualWordList),
    ),
  );
}

Widget buildMobileImportManualTypingUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileImportManualScreen(
        wordListOverride: _previewManualWordList,
        initialTypedWord: 'Ag',
      ),
    ),
  );
}

Widget buildMobileImportManualErrorUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileImportManualScreen(
        wordListOverride: _previewManualWordList,
        initialTypedWord: 'Secr\$',
        initialError: 'Invalid secret passphrase word.',
      ),
    ),
  );
}

Widget buildMobileImportManualDoneUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileImportManualScreen(
        wordListOverride: _previewManualWordList,
        initialAcceptedWords: _previewManualAcceptedWords,
        initialTypedWord: 'Age',
      ),
    ),
  );
}

Widget buildMobileImportReviewUseCase(BuildContext context) {
  return buildMobileImportReview15UseCase(context);
}

Widget buildMobileImportReview12UseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: _MobileImportHarness(
      initialLocation: '/import/review',
      initialReviewMnemonic: _previewImportReviewMnemonic12,
    ),
  );
}

Widget buildMobileImportReview15UseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: _MobileImportHarness(
      initialLocation: '/import/review',
      initialReviewMnemonic: _previewImportReviewMnemonic15,
    ),
  );
}

Widget buildMobileImportReview18UseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: _MobileImportHarness(
      initialLocation: '/import/review',
      initialReviewMnemonic: _previewImportReviewMnemonic18,
    ),
  );
}

Widget buildMobileImportReview24UseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: _MobileImportHarness(
      initialLocation: '/import/review',
      initialReviewMnemonic: _previewImportReviewMnemonic,
    ),
  );
}

Widget buildMobileSecretPassphraseRevealedUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileSecretPassphraseScreen(
        args: CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
        screenshotStream: Stream.empty(),
      ),
    ),
  );
}

Widget buildMobileSecretPassphraseLongWordsUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileSecretPassphraseScreen(
        args: CreateSecretPassphraseArgs(mnemonic: _previewLongWordMnemonic),
        screenshotStream: Stream.empty(),
      ),
    ),
  );
}

Widget buildMobileSecretPassphraseProtectedUseCase(BuildContext context) {
  return const _MobileSecretPassphraseProtectedPreview();
}

Widget buildMobileSecretPassphraseScreenshotWarningUseCase(
  BuildContext context,
) {
  return _MobilePreviewFrame(
    child: Stack(
      children: [
        const IgnorePointer(
          child: MobileSecretPassphraseScreen(
            args: CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
            screenshotStream: Stream.empty(),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: AppTheme.of(context).colors.background.neutralScrim,
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: MobileModalCard(child: MobileSeedScreenshotWarningSheet()),
          ),
        ),
      ],
    ),
  );
}

Widget buildMobileFaceIdOptInUseCase(BuildContext context) {
  return _buildMobileBiometricOptInUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      ),
      enabled: false,
    ),
  );
}

Widget buildMobileFingerprintOptInUseCase(BuildContext context) {
  return _buildMobileBiometricOptInUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.fingerprint,
      ),
      enabled: false,
    ),
  );
}

Widget buildMobileForgotPasscodeSheetUseCase(BuildContext context) {
  return _buildMobileUnlockModalUseCase(context, const ForgotPasscodeSheet());
}

Widget buildMobileForgotPasscodeLastWarningUseCase(BuildContext context) {
  return _buildMobileUnlockModalUseCase(
    context,
    const ForgotPasscodeLastWarningSheet(),
  );
}

Widget buildMobileSeedScreenshotWarningSheetUseCase(BuildContext context) {
  return _buildMobileModalSnapshotUseCase(
    context,
    const MobileSeedScreenshotWarningSheet(),
  );
}

Widget buildAccountsManyUseCase(BuildContext context) {
  return _buildAccountsUseCase(_accountsManyState);
}

Widget buildAccountsOtherMenuUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-3',
  );
}

Widget buildAccountsCurrentMenuUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-1',
  );
}

Widget buildAccountsEditAccountUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.editAccount,
  );
}

Widget buildAccountsProfilePictureUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.profilePicture,
  );
}

Widget buildAccountsRemoveUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.removeAccount,
  );
}

Widget buildSettingsMainUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(const NetworkPrivacyState.off());
}

Widget buildSettingsTorConnectingUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(
    const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
    ),
  );
}

Widget buildSettingsTorConnectedUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(
    const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
    ),
  );
}

Widget buildSettingsTorSwitchingToDirectUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(
    const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
      targetTorEnabled: false,
    ),
  );
}

Widget buildSettingsTorUpdatesUnavailableUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(
    const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
      softwareUpdatesAvailable: false,
    ),
  );
}

Widget buildSettingsTorFailedUseCase(BuildContext context) {
  return _buildSettingsMainUseCase(
    const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      error: 'Preview Tor bootstrap failure',
    ),
  );
}

Widget _buildSettingsMainUseCase(NetworkPrivacyState networkPrivacyState) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsBootstrap(_accountsDesignState, initialLocation: '/settings'),
      ),
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(_accountsDesignState),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(_accountsDesignState.activeAccountUuid),
      ),
      networkPrivacyProvider.overrideWith(
        () => _PreviewNetworkPrivacyNotifier(networkPrivacyState),
      ),
    ],
    child: _SettingsHarness(),
  );
}

Widget buildSettingsEndpointUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/endpoint',
    const SettingsEndpointScreen(),
  );
}

Widget buildSettingsSecretPassphraseGateUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/secret-passphrase',
    const SettingsSeedPhraseScreen(),
  );
}

Widget buildSettingsSecretPassphraseRevealUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/secret-passphrase',
    const SettingsSeedPhraseRevealPreview(
      mnemonic: _previewImportReviewMnemonic,
      bip39Passphrase: '123CAsd#41 recovery phrase 123CAsd#41',
    ),
  );
}

Widget buildSettingsSecretPassphraseRevealWithoutBip39UseCase(
  BuildContext context,
) {
  return _buildSettingsSubScreenUseCase(
    '/settings/secret-passphrase',
    const SettingsSeedPhraseRevealPreview(
      mnemonic: _previewImportReviewMnemonic,
    ),
  );
}

Widget buildSettingsChangePasswordGateUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/change-password',
    const SettingsChangePasswordScreen(),
  );
}

Widget buildSettingsUninstallConfirmUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/uninstall',
    const SettingsUninstallScreen(),
  );
}

/// Done stage demo: plays the badge motion (1000ms hold, then the helmet
/// fades out over 500ms) on entry. Re-select the use case to replay.
Widget buildSettingsUninstallDoneUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/uninstall',
    const SettingsUninstallScreen(initialStage: SettingsUninstallStage.done),
  );
}

Widget buildSettingsWalletLinkConfirmAccessUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/link-mobile',
    const WalletLinkDesktopScreen(),
  );
}

Widget buildSettingsWalletLinkInitialUseCase(BuildContext context) {
  return _buildSettingsWalletLinkUseCase(const WalletLinkState.initial());
}

Widget buildSettingsWalletLinkQrUseCase(BuildContext context) {
  return _buildSettingsWalletLinkUseCase(
    const WalletLinkState(
      phase: WalletLinkPhase.ready,
      qrPayload:
          'vizor://wallet-link/v1?id=7f28d351-2b4c-4cb8-ae15-93824cb4f8db&key=previewTransferKey123&endpoint=http%3A%2F%2Flocalhost%3A3000',
      remaining: Duration(seconds: 59),
      accountCount: 6,
      contactCount: 20,
    ),
  );
}

Widget buildSettingsWalletLinkSuccessUseCase(BuildContext context) {
  return _buildSettingsWalletLinkUseCase(
    const WalletLinkState(
      phase: WalletLinkPhase.linked,
      accountCount: 6,
      contactCount: 20,
      actualImportCounts: true,
    ),
  );
}

Widget buildSettingsWalletLinkExpiredUseCase(BuildContext context) {
  return _buildSettingsWalletLinkUseCase(
    const WalletLinkState(
      phase: WalletLinkPhase.expired,
      accountCount: 6,
      contactCount: 20,
    ),
  );
}

Widget _buildSettingsWalletLinkUseCase(WalletLinkState state) {
  return _buildSettingsSubScreenUseCase(
    '/settings/link-mobile',
    WalletLinkDesktopScreen(previewState: state),
  );
}

Widget _buildSettingsSubScreenUseCase(String path, Widget screen) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsBootstrap(_accountsDesignState, initialLocation: path),
      ),
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(_accountsDesignState),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(_accountsDesignState.activeAccountUuid),
      ),
    ],
    child: _SettingsSubScreenHarness(path: path, screen: screen),
  );
}

Widget buildAboutUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/about', _accountsDesignState);
}

Widget buildTermsUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/terms', const AccountState());
}

Widget buildPrivacyUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/privacy', const AccountState());
}

Widget buildMobileAccountsUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(_accountsDesignState);
}

Widget buildMobileAccountsSoftwareMenuUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-3',
  );
}

Widget buildMobileAccountsKeystoneMenuUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-2',
  );
}

Widget buildMobileAccountsEditAccountUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialSheetAccountUuid: 'preview-account-2',
    initialSheet: MobileAccountsInitialSheet.editAccount,
  );
}

Widget buildMobileAccountsRemoveAccountUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialSheetAccountUuid: 'preview-account-2',
    initialSheet: MobileAccountsInitialSheet.removeAccount,
  );
}

Widget buildMobileAccountsActiveMigrationRemoveAccountUseCase(
  BuildContext context,
) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialSheetAccountUuid: 'preview-account-2',
    initialSheet: MobileAccountsInitialSheet.removeAccount,
    migrationStatus: _previewMobileMigrationStatus(),
  );
}

Widget buildMobileAccountsManyUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(_accountsManyState);
}

Widget buildMobileHomeDefaultUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14312000000),
      recentTransactions: [_homeTx(1), _homeTx(2)],
    ),
  );
}

Widget buildMobileHomeIronwoodMigrationRequiredUseCase(BuildContext context) {
  final accountUuid = _ironwoodMobileHomeAccountState.activeAccountUuid!;
  return _buildMobileHomeUseCase(
    accountState: _ironwoodMobileHomeAccountState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14_292_000_000),
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3), _homeTx(4)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.start(
      network: 'main',
      accountUuid: accountUuid,
      status: _previewMigrationStatus(kIronwoodMigrationReadyPhase),
    ),
    marketData: const ZecMarketData(usdPrice: 8.397, change24hPct: 13.12),
    swapEnabled: false,
  );
}

Widget buildMobileHomeIronwoodAnnouncementUseCase(BuildContext context) {
  final accountUuid = _ironwoodMobileHomeAccountState.activeAccountUuid!;
  final status = _previewMigrationStatus(kIronwoodMigrationReadyPhase);
  return _buildMobileHomeUseCase(
    accountState: _ironwoodMobileHomeAccountState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14_292_000_000),
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3), _homeTx(4)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.start(
      network: 'main',
      accountUuid: accountUuid,
      status: status,
    ),
    marketData: const ZecMarketData(usdPrice: 8.397, change24hPct: 13.12),
    swapEnabled: false,
    showStaticIronwoodAnnouncement: true,
  );
}

Widget buildMobileHomeIronwoodMigrationInProgressUseCase(BuildContext context) {
  final accountUuid = _ironwoodMobileHomeAccountState.activeAccountUuid!;
  return _buildMobileHomeUseCase(
    accountState: _ironwoodMobileHomeAccountState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(10_000_000_000),
      ironwoodBalance: BigInt.from(4_001_000_000),
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3), _homeTx(4)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: accountUuid,
      status: _previewMobileHomeMigrationStatus(),
    ),
    marketData: const ZecMarketData(usdPrice: 29.9955, change24hPct: 13.12),
    swapEnabled: false,
  );
}

Widget buildMobileHomeNoActivityUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(orchardBalance: BigInt.from(14312000000)),
  );
}

Widget buildMobileHomeNoBalanceUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(),
  );
}

Widget buildMobileHomeNoBalanceKeystoneUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _homeKeystoneState,
    syncState: _homeSyncedState(accountUuid: _homeKeystoneAccountUuid),
  );
}

Widget buildMobileHomeImportingUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: SyncState(
      accountUuid: _accountsDesignState.activeAccountUuid,
      isSyncing: true,
      percentage: 0.34,
      displayPercentage: 0.34,
    ),
  );
}

Widget buildMobileHomeAccountsModalUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(orchardBalance: BigInt.from(14312000000)),
    openAccountsSheet: true,
  );
}

Widget buildDesktopHomeIronwoodMigrationRequiredUseCase(BuildContext context) {
  return _buildDesktopHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14_323_000_000),
      transparentBalance: BigInt.from(1_412_000_000),
      canShieldTransparentBalance: true,
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.start(
      network: 'main',
      accountUuid: _accountsDesignState.activeAccountUuid!,
      status: _previewMigrationStatus(kIronwoodMigrationReadyPhase),
    ),
    zecUsdPrice: 1200.12 / 143.23,
  );
}

Widget buildDesktopHomeIronwoodMigrationInProgressUseCase(
  BuildContext context,
) {
  final status = _previewMigrationStatus(
    kIronwoodMigrationBroadcastScheduledPhase,
    activeRunId: 'preview-run',
    parts: [
      rust_sync.MigrationPartStatus(
        partIndex: 0,
        valueZatoshi: BigInt.from(10_000_000_000),
        state: rust_sync.MigrationPartState.scheduled,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
    ],
  );
  return _buildDesktopHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(10_221_000_000),
      ironwoodBalance: BigInt.from(4_011_000_000),
      transparentBalance: BigInt.from(1_412_000_000),
      canShieldTransparentBalance: true,
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: _accountsDesignState.activeAccountUuid!,
      status: status,
    ),
    zecUsdPrice: 1200.12 / 40.11,
  );
}

Widget buildDesktopHomeSidebarCompactBalancesUseCase(BuildContext context) {
  final status = _previewMigrationStatus(
    kIronwoodMigrationBroadcastScheduledPhase,
    activeRunId: 'preview-sidebar-compact-balances',
  );
  return _buildDesktopHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(1_234_567_890_000),
      ironwoodBalance: BigInt.from(5_240_000_000),
    ),
    migrationCta: IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: _accountsDesignState.activeAccountUuid!,
      status: status,
    ),
  );
}

Widget buildDesktopHomeIronwoodMigrationAnnouncementUseCase(
  BuildContext context,
) {
  final accountUuid = _accountsDesignState.activeAccountUuid!;
  return _buildDesktopHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14_223_000_000),
      recentTransactions: [_homeTx(1), _homeTx(2), _homeTx(3), _homeTx(4)],
    ),
    migrationCta: IronwoodHomeMigrationCtaState.start(
      network: 'main',
      accountUuid: accountUuid,
      status: _previewMigrationStatus(kIronwoodMigrationReadyPhase),
    ),
    announcement: IronwoodMigrationAnnouncementState.visible(
      network: 'main',
      accountUuid: accountUuid,
      status: _previewMigrationStatus(kIronwoodMigrationReadyPhase),
    ),
  );
}

Widget buildIronwoodMigrationIntroUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/intro',
    step: IronwoodMigrationFlowStep.intro,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_223_000_000)),
  );
}

Widget buildIronwoodMigrationHowItWorksUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/how-it-works',
    step: IronwoodMigrationFlowStep.howItWorks,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_232_000_000)),
  );
}

Widget buildIronwoodMigrationWhatToExpectUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/what-to-expect',
    step: IronwoodMigrationFlowStep.whatToExpect,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_232_000_000)),
  );
}

Widget buildIronwoodMigrationOptionsUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/options',
    step: IronwoodMigrationFlowStep.options,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
  );
}

Widget buildIronwoodMigrationPrivateReviewUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/review',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
  );
}

Widget buildIronwoodMigrationImmediateReviewUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/immediate/review',
    step: IronwoodMigrationFlowStep.immediateReview,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    previewImmediatePlan: _previewMobileImmediateMigrationPlan(),
  );
}

Widget buildIronwoodMigrationImmediateKeystoneRequestUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/immediate/keystone/sign',
    step: IronwoodMigrationFlowStep.immediateReview,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    previewImmediatePlan: _previewMobileImmediateMigrationPlan(),
  );
}

Widget buildIronwoodMigrationImmediateKeystoneScannerUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/immediate/keystone/sign',
    step: IronwoodMigrationFlowStep.immediateReview,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    previewImmediatePlan: _previewMobileImmediateMigrationPlan(),
    previewImmediateKeystoneScanner: true,
  );
}

Widget buildIronwoodMigrationPrivateKeystoneRequestUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/keystone/sign',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    isHardware: true,
  );
}

Widget buildIronwoodMigrationAnalyzingUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/review',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    reviewPreviewStage: IronwoodMigrationReviewPreviewStage.analyzing,
  );
}

Widget buildIronwoodMigrationShuffleReviewUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/review',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    reviewPreviewStage: IronwoodMigrationReviewPreviewStage.review,
  );
}

Widget buildIronwoodMigrationPrivateStatusWaitingUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_224_000_000)),
    previewStatus: _previewPrivateMigrationStatus(),
  );
}

Widget buildIronwoodMigrationPrivateStatusMigratingUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_223_000_000)),
    previewStatus: _previewPrivateMigrationTransferStatus(),
  );
}

Widget buildIronwoodMigrationPrivateStatusNeedsInputUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(14_223_000_000)),
    previewStatus: _previewPrivateMigrationNeedsInputStatus(),
    isHardware: true,
  );
}

Widget buildIronwoodMigrationPostPrepareWaitingUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPostPrepareWaitingStatus(),
  );
}

Widget buildIronwoodMigrationScheduleUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/schedule',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewMigrationScheduleStatus(),
  );
}

Widget buildIronwoodMigrationPreparationScheduleUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/preparation-schedule',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPrivateMigrationStatus(),
  );
}

Widget buildIronwoodMigrationPreparationScheduleLargeTextUseCase(
  BuildContext context,
) {
  return MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.5)),
    child: buildIronwoodMigrationPreparationScheduleUseCase(context),
  );
}

Widget buildIronwoodMigrationManageScheduleUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/schedule',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewMigrationScheduleStatus(),
    schedulePreviewOverlay: IronwoodMigrationSchedulePreviewOverlay.manage,
    schedulePreviewCanStop: true,
  );
}

Widget buildIronwoodMigrationImmediateConfirmationUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/schedule',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewMigrationScheduleStatus(),
    schedulePreviewOverlay:
        IronwoodMigrationSchedulePreviewOverlay.immediateConfirmation,
    schedulePreviewImmediatePlan: _previewMobileImmediateMigrationPlan(),
    schedulePreviewCanStop: true,
  );
}

Widget buildIronwoodMigrationStopConfirmationUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/schedule',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewMigrationScheduleStatus(),
    schedulePreviewOverlay:
        IronwoodMigrationSchedulePreviewOverlay.stopConfirmation,
    schedulePreviewCanStop: true,
  );
}

Widget buildIronwoodMigrationCompleteUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPostPrepareStatus(
      phase: kIronwoodMigrationCompletePhase,
      parts: _previewPostPrepareParts(completedNoteCount: 3),
    ),
  );
}

Widget buildIronwoodMigrationPostPrepareSigningUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPostPrepareSigningStatus(),
    isHardware: true,
  );
}

Widget buildIronwoodMigrationPostPrepareProgressedUseCase(
  BuildContext context,
) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPostPrepareProgressedStatus(),
  );
}

Widget buildIronwoodMigrationPostPrepareActiveUseCase(BuildContext context) {
  return _buildIronwoodMigrationUseCase(
    initialLocation: '/migration/private/status',
    step: IronwoodMigrationFlowStep.review,
    data: _ironwoodMigrationFlowData(zatoshi: BigInt.from(10_000_000_000)),
    previewStatus: _previewPostPrepareActiveStatus(),
  );
}

Widget buildMobileIronwoodMigrationIntroUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.intro,
  );
}

Widget buildMobileIronwoodMigrationHowItWorksUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.howItWorks,
  );
}

Widget buildMobileIronwoodMigrationOptionsUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.options,
  );
}

Widget buildMobileIronwoodMigrationAndroidOptionsUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.options,
    privateMigrationSupported: false,
  );
}

Widget buildMobileIronwoodMigrationFastReviewUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.fastReview,
    previewImmediatePlan: _previewMobileImmediateMigrationPlan(),
  );
}

Widget buildMobileIronwoodMigrationNotificationsPromptUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.notificationsPrompt,
  );
}

Widget buildMobileIronwoodMigrationNotificationsConfirmationUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.notificationsConfirmation,
  );
}

Widget buildMobileIronwoodMigrationStartLoadingUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationStartLoading,
  );
}

Widget buildMobileIronwoodMigrationStartKeystoneReadyUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationStartKeystoneReady,
  );
}

Widget buildMobileIronwoodMigrationPreparationActiveUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.preparationActive,
  );
}

Widget buildMobileIronwoodMigrationPreparationPausedUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.preparationPaused,
  );
}

Widget buildMobileIronwoodMigrationPreparationPausedKeystoneUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.preparationPausedKeystone,
  );
}

Widget buildMobileIronwoodMigrationPreparationSyncingUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.preparationSyncing,
  );
}

Widget buildMobileIronwoodMigrationSyncingUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.syncing,
  );
}

Widget buildMobileIronwoodMigrationPreparationCompleteUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.preparationCompleteModal,
  );
}

Widget buildMobileIronwoodMigrationPreparationCompleteCaptureUseCase(
  BuildContext context,
) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
      MobileIronwoodMigrationPreviewSurface.preparationCompleteModal,
    ),
  );
}

Widget buildMobileIronwoodMigrationWaitingNotificationsOnUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationWaitingNotificationsOn,
  );
}

Widget buildMobileIronwoodMigrationWaitingNotificationsOffUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationWaitingNotificationsOff,
  );
}

Widget buildMobileIronwoodMigrationNeedsInputUseCase(BuildContext context) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: false),
    child: _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
      MobileIronwoodMigrationPreviewSurface.migrationNeedsInput,
    ),
  );
}

Widget buildMobileIronwoodMigrationKeystoneSignAllUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationKeystoneSignAll,
  );
}

Widget buildMobileIronwoodMigrationBroadcastingUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationBroadcasting,
  );
}

Widget buildMobileIronwoodMigrationScheduleUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationScheduleUseCase(preparation: false);
}

Widget buildMobileIronwoodMigrationSchedulePendingUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationScheduleUseCase(
    preparation: false,
    status: _previewMigrationSchedulePendingStatus(),
  );
}

Widget buildMobileIronwoodMigrationPreparationScheduleUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationScheduleUseCase(preparation: true);
}

Widget _buildMobileIronwoodMigrationScheduleUseCase({
  required bool preparation,
  rust_sync.MigrationStatus? status,
}) {
  final accountState = _ironwoodMigrationAccountState();
  final resolvedStatus =
      status ??
      (preparation
          ? _previewPrivateMigrationStatus()
          : _previewMigrationScheduleStatus());
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_homeBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(
          accountState.activeAccountUuid,
          initialState: SyncState(
            accountUuid: accountState.activeAccountUuid,
            hasAccountScopedData: true,
            scannedHeight: 3_000_000,
            chainTipHeight: 3_000_000,
          ),
        ),
      ),
    ],
    child: _MobilePreviewFrame(
      child: _MobileMigrationScheduleHarness(
        preparation: preparation,
        status: resolvedStatus,
      ),
    ),
  );
}

Widget buildMobileIronwoodMigrationCompleteUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.migrationComplete,
  );
}

Widget buildMobileIronwoodMigrationHomeAttentionUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.homeAttention,
  );
}

Widget buildMobileIronwoodMigrationHomeAttentionModalUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.homeAttentionModal,
  );
}

Widget buildMobileIronwoodMigrationKeystoneHelpUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
    MobileIronwoodMigrationPreviewSurface.keystoneScanHelp,
  );
}

Widget buildMobileIronwoodMigrationKeystoneLoadingUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationKeystoneSigningUseCase(
    MobileIronwoodKeystoneSigningViewState.loading,
  );
}

Widget buildMobileIronwoodMigrationKeystoneReadyUseCase(BuildContext context) {
  return _buildMobileIronwoodMigrationKeystoneSigningUseCase(
    MobileIronwoodKeystoneSigningViewState.ready,
  );
}

/// A request that fits one Keystone round: no round badge, only the
/// transaction count.
Widget buildMobileIronwoodMigrationKeystoneReadySingleRoundUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationKeystoneSigningUseCase(
    MobileIronwoodKeystoneSigningViewState.ready,
    multiRound: false,
  );
}

Widget buildMobileIronwoodMigrationKeystoneScannerUseCase(
  BuildContext context,
) {
  return _buildMobileIronwoodMigrationKeystoneSigningUseCase(
    MobileIronwoodKeystoneSigningViewState.scanner,
  );
}

Widget _buildMobileIronwoodMigrationKeystoneSigningUseCase(
  MobileIronwoodKeystoneSigningViewState state, {
  bool multiRound = true,
}) {
  // Production only knows the round split and message count once the request
  // is encoded, so the loading state carries neither.
  final loading = state == MobileIronwoodKeystoneSigningViewState.loading;
  return SizedBox(
    width: 393,
    height: 852,
    child: MediaQuery(
      data: const MediaQueryData(
        size: Size(393, 852),
        viewPadding: EdgeInsets.only(top: 55),
      ),
      child: MobileIronwoodKeystoneSigningView(
        state: state,
        round: MobileIronwoodKeystoneSigningRound.denominationSplit,
        // A multi-round request: the badge and the per-round transaction count
        // are the states that need previewing.
        signingRoundLabel: loading || !multiRound ? null : 'Round 1 of 2',
        signingMessageCountLabel: loading
            ? null
            : multiRound
            ? 'Signs 26 of 51 transactions'
            : 'Signs 51 transactions',
        // Mid-scan so the viewfinder-width progress bar and its numeric
        // readout are visible in the scanner preview.
        scanProgress: state == MobileIronwoodKeystoneSigningViewState.scanner
            ? 0.42
            : null,
        qrCode: const _KeystoneMigrationQrPreview(),
        camera: const _KeystoneMigrationCameraPreview(),
        onNext: () {},
        onCancel: () {},
        onToggleFlashlight: () {},
        onShowRequestQr: () {},
        onShowScanHelp: () {},
      ),
    ),
  );
}

class _KeystoneMigrationQrPreview extends StatelessWidget {
  const _KeystoneMigrationQrPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFFFFFFF),
      child: Center(child: AppIcon(AppIcons.qr, size: 128)),
    );
  }
}

class _KeystoneMigrationCameraPreview extends StatelessWidget {
  const _KeystoneMigrationCameraPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF111111));
  }
}

Widget _buildMobileIronwoodMigrationUseCase({
  required MobileIronwoodMigrationStep step,
  rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan,
  MobileIronwoodMigrationPreviewSurface? previewSurface,
  bool? privateMigrationSupported,
}) {
  final zatoshi = switch (step) {
    MobileIronwoodMigrationStep.intro => BigInt.from(14_223_000_000),
    MobileIronwoodMigrationStep.howItWorks ||
    MobileIronwoodMigrationStep.options => BigInt.from(14_223_000_000),
    MobileIronwoodMigrationStep.fastReview => BigInt.from(14_224_000_000),
    MobileIronwoodMigrationStep.notifications ||
    MobileIronwoodMigrationStep.preparing ||
    MobileIronwoodMigrationStep.migrating => BigInt.from(14_220_000_000),
  };
  final accountName = switch (step) {
    MobileIronwoodMigrationStep.preparing ||
    MobileIronwoodMigrationStep.migrating => 'Account1',
    _ => 'Username',
  };
  return ProviderScope(
    child: _MobilePreviewFrame(
      child: MobileIronwoodMigrationFlowScreen(
        step: step,
        previewData: _ironwoodMigrationFlowData(
          zatoshi: zatoshi,
          accountName: accountName,
        ),
        previewPrivatePlan: _previewMobilePrivateMigrationPlan(),
        previewImmediatePlan: previewImmediatePlan,
        previewSurface: previewSurface,
        privateMigrationSupported: privateMigrationSupported,
      ),
    ),
  );
}

Widget _buildMobileIronwoodMigrationPreviewSurfaceUseCase(
  MobileIronwoodMigrationPreviewSurface surface,
) {
  return _buildMobileIronwoodMigrationUseCase(
    step: MobileIronwoodMigrationStep.migrating,
    previewSurface: surface,
  );
}

Widget _buildAccountsUseCase(
  AccountState accountState, {
  String? initialOpenMenuAccountUuid,
  String? initialModalAccountUuid,
  AccountsScreenInitialModal? initialModal,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_accountsBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
    ],
    child: _AccountsHarness(
      initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
      initialModalAccountUuid: initialModalAccountUuid,
      initialModal: initialModal,
    ),
  );
}

Widget _buildUtilityUseCase(String initialLocation, AccountState accountState) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _utilityBootstrap(initialLocation, accountState),
      ),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
    ],
    child: _UtilityHarness(initialLocation: initialLocation),
  );
}

Widget _buildMobileHomeUseCase({
  required AccountState accountState,
  required SyncState syncState,
  bool openAccountsSheet = false,
  IronwoodHomeMigrationCtaState migrationCta =
      const IronwoodHomeMigrationCtaState.hidden(),
  IronwoodMigrationAnnouncementState announcement =
      const IronwoodMigrationAnnouncementState.hidden(),
  ZecMarketData marketData = const ZecMarketData(
    usdPrice: 70,
    change24hPct: 13.12,
  ),
  bool swapEnabled = true,
  bool showStaticIronwoodAnnouncement = false,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_homeBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      receiveAddressServiceProvider.overrideWithValue(
        const _PreviewReceiveAddressService(),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(
          accountState.activeAccountUuid,
          initialState: syncState,
        ),
      ),
      privacyModeProvider.overrideWith(_PreviewPrivacyModeNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        _PreviewZecMarketDataSource(marketData),
      ),
      zecHomeUsdUnitPriceProvider.overrideWithValue(marketData.usdPrice),
      zecPriceChange24hPctProvider.overrideWithValue(marketData.change24hPct),
      swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
      swapActivityRowItemsProvider.overrideWith((ref, accountUuid) async {
        return const [];
      }),
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
        return migrationCta;
      }),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migrationCta),
      ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
        return announcement;
      }),
    ],
    child: _MobilePreviewFrame(
      child: _MobileHomeHarness(
        openAccountsSheet: openAccountsSheet,
        showStaticIronwoodAnnouncement: showStaticIronwoodAnnouncement,
      ),
    ),
  );
}

Widget _buildDesktopHomeUseCase({
  required AccountState accountState,
  required SyncState syncState,
  required IronwoodHomeMigrationCtaState migrationCta,
  IronwoodMigrationAnnouncementState announcement =
      const IronwoodMigrationAnnouncementState.hidden(),
  double zecUsdPrice = 1.20012,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_homeBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(
          accountState.activeAccountUuid,
          initialState: syncState,
        ),
      ),
      privacyModeProvider.overrideWith(_PreviewPrivacyModeNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        _PreviewZecMarketDataSource(
          ZecMarketData(usdPrice: zecUsdPrice, change24hPct: 13.12),
        ),
      ),
      zecHomeUsdUnitPriceProvider.overrideWithValue(zecUsdPrice),
      zecPriceChange24hPctProvider.overrideWithValue(13.12),
      swapFeatureEnabledProvider.overrideWithValue(false),
      swapActivityRowItemsProvider.overrideWith((ref, accountUuid) async {
        return const [];
      }),
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
        return migrationCta;
      }),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migrationCta),
      ironwoodHomeBalancePresentationProvider.overrideWithValue(
        migrationCta.mode == IronwoodHomeMigrationCtaMode.resume
            ? IronwoodHomeBalancePresentationMode.ironwoodOnly
            : IronwoodHomeBalancePresentationMode.allShielded,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _PreviewMigrationCoordinator(
          accountUuid: accountState.activeAccountUuid,
          status: migrationCta.status?.activeRunId == null
              ? null
              : migrationCta.status,
        ),
      ),
      ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
        return announcement;
      }),
    ],
    child: const _DesktopHomeHarness(),
  );
}

Widget _buildIronwoodMigrationUseCase({
  required String initialLocation,
  required IronwoodMigrationFlowStep step,
  required IronwoodMigrationFlowData data,
  rust_sync.MigrationStatus? previewStatus,
  IronwoodMigrationReviewPreviewStage reviewPreviewStage =
      IronwoodMigrationReviewPreviewStage.review,
  bool isHardware = false,
  rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan,
  bool previewImmediateKeystoneScanner = false,
  IronwoodMigrationSchedulePreviewOverlay? schedulePreviewOverlay,
  rust_sync.OrchardMigrationImmediatePlan? schedulePreviewImmediatePlan,
  bool schedulePreviewCanStop = false,
}) {
  final accountState = _ironwoodMigrationAccountState(isHardware: isHardware);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_homeBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(
          accountState.activeAccountUuid,
          initialState: SyncState(
            accountUuid: accountState.activeAccountUuid,
            hasAccountScopedData: true,
            isSyncing: true,
            percentage: 0.34,
            displayPercentage: 0.34,
            displayTargetPercentage: 0.34,
            scannedHeight: 3_000_000,
            chainTipHeight: 3_000_000,
            orchardBalance: data.amountZatoshi,
            spendableBalance: data.amountZatoshi,
            totalBalance: data.amountZatoshi,
          ),
        ),
      ),
      privacyModeProvider.overrideWith(_PreviewPrivacyModeNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodMigrationAnalyzingMinimumDurationProvider.overrideWithValue(
        Duration.zero,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _PreviewMigrationCoordinator(
          accountUuid: accountState.activeAccountUuid,
          status: previewStatus,
        ),
      ),
    ],
    child: _IronwoodMigrationHarness(
      initialLocation: initialLocation,
      initialStep: step,
      data: data,
      previewStatus: previewStatus,
      reviewPreviewStage: reviewPreviewStage,
      previewImmediatePlan: previewImmediatePlan,
      previewImmediateKeystoneScanner: previewImmediateKeystoneScanner,
      schedulePreviewOverlay: schedulePreviewOverlay,
      schedulePreviewImmediatePlan: schedulePreviewImmediatePlan,
      schedulePreviewCanStop: schedulePreviewCanStop,
    ),
  );
}

Widget _buildMobileAccountsUseCase(
  AccountState accountState, {
  String? initialSheetAccountUuid,
  MobileAccountsInitialSheet? initialSheet,
  String? initialOpenMenuAccountUuid,
  rust_sync.MigrationStatus? migrationStatus,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_accountsBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      receiveAddressServiceProvider.overrideWithValue(
        const _PreviewReceiveAddressService(),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _PreviewMigrationCoordinator(
          accountUuid: initialSheetAccountUuid,
          status: migrationStatus,
        ),
      ),
    ],
    child: Center(
      child: SizedBox(
        width: 393,
        height: 852,
        child: _MobileAccountsHarness(
          initialSheetAccountUuid: initialSheetAccountUuid,
          initialSheet: initialSheet,
          initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
        ),
      ),
    ),
  );
}

class _MobileImportHarness extends StatefulWidget {
  const _MobileImportHarness({
    this.initialLocation = '/import',
    this.initialPasteError,
    this.initialReviewMnemonic = _previewImportReviewMnemonic,
  });

  final String initialLocation;
  final String? initialPasteError;
  final String initialReviewMnemonic;

  @override
  State<_MobileImportHarness> createState() => _MobileImportHarnessState();
}

class _MobileImportHarnessState extends State<_MobileImportHarness> {
  late final GoRouter _router;
  late final SensitivePrivacyOverlayController _reviewPrivacyController =
      SensitivePrivacyOverlayController();

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(
          path: '/import',
          builder: (_, _) => MobileImportScreen(
            initialPreviewError: widget.initialPasteError,
            initialPreviewErrorDuration: _previewErrorToastDuration,
          ),
        ),
        GoRoute(
          path: '/import/manual',
          builder: (_, _) => const MobileImportManualScreen(
            wordListOverride: _previewManualWordList,
          ),
        ),
        GoRoute(
          path: '/import/review',
          builder: (_, state) {
            final extra = state.extra;
            final args = extra is ImportSecretPassphraseArgs
                ? extra
                : ImportSecretPassphraseArgs(
                    mnemonic: widget.initialReviewMnemonic,
                  );
            return MobileImportReviewScreen(
              args: args,
              screenshotStream: const Stream.empty(),
              privacyOverlayController: _reviewPrivacyController,
            );
          },
        ),
        GoRoute(
          path: '/import/birthday',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/import/birthday'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _reviewPrivacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _NoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: `AppLayoutNotifier.setMode` would reshape the
    // native window via `window_manager`, which is disruptive in a
    // Widgetbook preview where the window belongs to the dev tool.
  }
}

class _AccountsHarness extends StatefulWidget {
  const _AccountsHarness({
    this.initialOpenMenuAccountUuid,
    this.initialModalAccountUuid,
    this.initialModal,
  });

  final String? initialOpenMenuAccountUuid;
  final String? initialModalAccountUuid;
  final AccountsScreenInitialModal? initialModal;

  @override
  State<_AccountsHarness> createState() => _AccountsHarnessState();
}

class _AccountsHarnessState extends State<_AccountsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => AccountsScreen(
            initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
            initialModalAccountUuid: widget.initialModalAccountUuid,
            initialModal: widget.initialModal,
          ),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/settings/secret-passphrase',
          builder: (_, state) => _PreviewRoutePlaceholder(
            label:
                '/settings/secret-passphrase '
                '(${state.extra as String? ?? 'active account'})',
          ),
        ),
        GoRoute(
          path: '/about',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/about'),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/welcome'),
        ),
        GoRoute(
          path: '/unlock',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/unlock'),
        ),
        GoRoute(
          path: '/migration/intro',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/migration/intro'),
        ),
        GoRoute(
          path: '/migration/private/status',
          builder: (_, _) => const _PreviewRoutePlaceholder(
            label: '/migration/private/status',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _SettingsSubScreenHarness extends StatefulWidget {
  const _SettingsSubScreenHarness({required this.path, required this.screen});

  final String path;
  final Widget screen;

  @override
  State<_SettingsSubScreenHarness> createState() =>
      _SettingsSubScreenHarnessState();
}

class _SettingsSubScreenHarnessState extends State<_SettingsSubScreenHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.path,
      routes: [
        GoRoute(path: widget.path, builder: (_, _) => widget.screen),
        for (final path in [
          '/settings',
          '/home',
          '/welcome',
          '/unlock',
          '/swap',
          '/activity',
          '/accounts',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _PreviewRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _SettingsHarness extends StatefulWidget {
  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/settings/link-mobile',
          builder: (_, _) => const WalletLinkDesktopScreen(
            previewState: WalletLinkState.initial(),
          ),
        ),
        for (final path in const [
          '/settings/secret-passphrase',
          '/settings/change-password',
          '/settings/endpoint',
          '/settings/uninstall',
          '/address-book',
          '/about',
          '/privacy',
          '/terms',
          '/home',
          '/send',
          '/receive',
          '/activity',
          '/accounts',
          '/welcome',
          '/unlock',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _PreviewRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _UtilityHarness extends StatefulWidget {
  const _UtilityHarness({required this.initialLocation});

  final String initialLocation;

  @override
  State<_UtilityHarness> createState() => _UtilityHarnessState();
}

class _UtilityHarnessState extends State<_UtilityHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
        GoRoute(
          path: '/privacy',
          builder: (_, _) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/welcome'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _MobileAccountsHarness extends StatefulWidget {
  const _MobileAccountsHarness({
    this.initialSheetAccountUuid,
    this.initialSheet,
    this.initialOpenMenuAccountUuid,
  });

  final String? initialSheetAccountUuid;
  final MobileAccountsInitialSheet? initialSheet;
  final String? initialOpenMenuAccountUuid;

  @override
  State<_MobileAccountsHarness> createState() => _MobileAccountsHarnessState();
}

class _MobileAccountsHarnessState extends State<_MobileAccountsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => MobileAccountsScreen(
            initialSheetAccountUuid: widget.initialSheetAccountUuid,
            initialSheet: widget.initialSheet,
            initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
          ),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/settings/seed-phrase',
          builder: (_, state) => _PreviewRoutePlaceholder(
            label:
                '/settings/seed-phrase '
                '(${state.extra as String? ?? 'active account'})',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _MobileHomeHarness extends StatefulWidget {
  const _MobileHomeHarness({
    required this.openAccountsSheet,
    required this.showStaticIronwoodAnnouncement,
  });

  final bool openAccountsSheet;
  final bool showStaticIronwoodAnnouncement;

  @override
  State<_MobileHomeHarness> createState() => _MobileHomeHarnessState();
}

class _MobileHomeHarnessState extends State<_MobileHomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => AppMobileShell(
            body: _MobileHomeBody(openAccountsSheet: widget.openAccountsSheet),
            tabBar: AppMobileTabBar(
              items: _mobileHomeTabItems,
              currentIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/swap',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/swap'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) => _PreviewRoutePlaceholder(
            label: '/activity/tx/${state.pathParameters['txid']}',
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/accounts',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/accounts'),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = Router.withConfig(config: _router);
    if (!widget.showStaticIronwoodAnnouncement) {
      return router;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        router,
        ColoredBox(
          color: context.colors.background.neutralScrim,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MobileModalCard(
              child: MobileIronwoodMigrationAnnouncementSheet(
                onStartMigration: () {},
                onOpenReleaseNotes: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopHomeHarness extends StatefulWidget {
  const _DesktopHomeHarness();

  @override
  State<_DesktopHomeHarness> createState() => _DesktopHomeHarnessState();
}

class _DesktopHomeHarnessState extends State<_DesktopHomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/pay',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/pay'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) => _PreviewRoutePlaceholder(
            label: '/activity/tx/${state.pathParameters['txid']}',
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/settings/endpoint',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/settings/endpoint'),
        ),
        GoRoute(
          path: '/migration',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/migration'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _MobileHomeBody extends StatefulWidget {
  const _MobileHomeBody({required this.openAccountsSheet});

  final bool openAccountsSheet;

  @override
  State<_MobileHomeBody> createState() => _MobileHomeBodyState();
}

class _MobileHomeBodyState extends State<_MobileHomeBody> {
  var _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened || !widget.openAccountsSheet) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMobileAccountsSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MobileHomeScreen();
  }
}

class _IronwoodMigrationHarness extends StatefulWidget {
  const _IronwoodMigrationHarness({
    required this.initialLocation,
    required this.initialStep,
    required this.data,
    this.previewStatus,
    this.reviewPreviewStage = IronwoodMigrationReviewPreviewStage.review,
    this.previewImmediatePlan,
    this.previewImmediateKeystoneScanner = false,
    this.schedulePreviewOverlay,
    this.schedulePreviewImmediatePlan,
    this.schedulePreviewCanStop = false,
  });

  final String initialLocation;
  final IronwoodMigrationFlowStep initialStep;
  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus? previewStatus;
  final IronwoodMigrationReviewPreviewStage reviewPreviewStage;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final bool previewImmediateKeystoneScanner;
  final IronwoodMigrationSchedulePreviewOverlay? schedulePreviewOverlay;
  final rust_sync.OrchardMigrationImmediatePlan? schedulePreviewImmediatePlan;
  final bool schedulePreviewCanStop;

  @override
  State<_IronwoodMigrationHarness> createState() =>
      _IronwoodMigrationHarnessState();
}

class _IronwoodMigrationHarnessState extends State<_IronwoodMigrationHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(path: '/migration', redirect: (_, _) => '/migration/intro'),
        GoRoute(
          path: '/migration/intro',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.intro,
            previewData: widget.initialStep == IronwoodMigrationFlowStep.intro
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_223_000_000),
                  ),
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/how-it-works',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.howItWorks,
            previewData:
                widget.initialStep == IronwoodMigrationFlowStep.howItWorks
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_232_000_000),
                  ),
            previewPrivatePlan: _previewPrivateMigrationPlan(),
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/what-to-expect',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.whatToExpect,
            previewData:
                widget.initialStep == IronwoodMigrationFlowStep.whatToExpect
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_232_000_000),
                  ),
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/options',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.options,
            previewData: widget.initialStep == IronwoodMigrationFlowStep.options
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_224_000_000),
                  ),
            previewPrivatePlan: _previewPrivateMigrationPlan(),
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/review',
          redirect: (_, _) => '/migration/private/review',
        ),
        GoRoute(
          path: '/migration/private/review',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.review,
            previewData: widget.initialStep == IronwoodMigrationFlowStep.review
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_224_000_000),
                  ),
            previewPrivatePlan: _previewPrivateMigrationPlan(),
            previewReviewStage: widget.reviewPreviewStage,
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/private/status',
          builder: (_, _) => IronwoodMigrationPrivateStatusScreen(
            previewStatus:
                widget.previewStatus ?? _previewPrivateMigrationStatus(),
          ),
        ),
        GoRoute(
          path: '/migration/private/schedule',
          builder: (_, _) => IronwoodMigrationScheduleScreen(
            previewStatus:
                widget.previewStatus ?? _previewPrivateMigrationStatus(),
            previewOverlay: widget.schedulePreviewOverlay,
            previewImmediatePlan: widget.schedulePreviewImmediatePlan,
            previewCanStop: widget.schedulePreviewCanStop,
          ),
        ),
        GoRoute(
          path: '/migration/private/preparation-schedule',
          builder: (_, _) => IronwoodMigrationPreparationScheduleScreen(
            previewStatus:
                widget.previewStatus ?? _previewPrivateMigrationStatus(),
            previewOverlay: widget.schedulePreviewOverlay,
            previewImmediatePlan: widget.schedulePreviewImmediatePlan,
            previewCanStop: widget.schedulePreviewCanStop,
          ),
        ),
        GoRoute(
          path: '/migration/immediate/review',
          builder: (_, _) => IronwoodMigrationFlowScreen(
            step: IronwoodMigrationFlowStep.immediateReview,
            previewData:
                widget.initialStep == IronwoodMigrationFlowStep.immediateReview
                ? widget.data
                : _ironwoodMigrationFlowData(
                    zatoshi: BigInt.from(14_224_000_000),
                  ),
            previewImmediatePlan:
                widget.previewImmediatePlan ??
                _previewMobileImmediateMigrationPlan(),
            onOpenReleaseNotesOverride: () {},
          ),
        ),
        GoRoute(
          path: '/migration/immediate/keystone/sign',
          builder: (_, _) {
            final plan =
                widget.previewImmediatePlan ??
                _previewMobileImmediateMigrationPlan();
            return IronwoodMigrationKeystoneImmediateSignScreen(
              approvedPlan: plan,
              previewRequest: rust_sync.KeystoneMigrationSigningRequest(
                requestId: 'preview-immediate',
                messages: [
                  rust_sync.KeystoneMigrationMessage(
                    id: 'preview-immediate-transaction',
                    redactedPczt: Uint8List.fromList(const [1, 2, 3]),
                    expectedSignatureCount: 0,
                  ),
                ],
                signingBatchLimit: 1,
              ),
              previewUrParts: const [
                'ur:zcash-sign-request/preview-immediate-transaction',
              ],
              previewStartScanning: widget.previewImmediateKeystoneScanner,
            );
          },
        ),
        GoRoute(
          path: '/migration/private/keystone/sign',
          builder: (_, _) => IronwoodMigrationKeystoneCombinedSignScreen(
            approvedSchedule: const [],
            previewRequest: rust_sync.KeystoneMigrationSigningRequest(
              requestId: 'preview-private',
              messages: [
                rust_sync.KeystoneMigrationMessage(
                  id: 'preview-private-split-1',
                  redactedPczt: Uint8List.fromList(const [1, 2, 3]),
                  expectedSignatureCount: 0,
                ),
                rust_sync.KeystoneMigrationMessage(
                  id: 'preview-private-split-2',
                  redactedPczt: Uint8List.fromList(const [4, 5, 6]),
                  expectedSignatureCount: 0,
                ),
              ],
              signingBatchLimit: 1,
            ),
            previewUrParts: const [
              'ur:zcash-sign-request/preview-private-split-1',
            ],
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _WelcomeHarness extends StatefulWidget {
  const _WelcomeHarness({this.showNetworkSettingsInitially = false});

  final bool showNetworkSettingsInitially;

  @override
  State<_WelcomeHarness> createState() => _WelcomeHarnessState();
}

class _WelcomeHarnessState extends State<_WelcomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (_, _) => WelcomeScreen(
            showNetworkSettingsInitially: widget.showNetworkSettingsInitially,
          ),
        ),
        // Stub destinations so buttons in the preview don't throw when
        // tapped. They render nothing meaningful — the point is just to
        // satisfy the router.
        GoRoute(
          path: '/onboarding/intro',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/onboarding/intro'),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/import'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _CustomiseAccountHarness extends StatefulWidget {
  const _CustomiseAccountHarness();

  @override
  State<_CustomiseAccountHarness> createState() =>
      _CustomiseAccountHarnessState();
}

class _CustomiseAccountHarnessState extends State<_CustomiseAccountHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: OnboardingStep.customiseAccount.routePath,
      routes: [
        GoRoute(
          path: OnboardingStep.customiseAccount.routePath,
          builder: (_, _) => OnboardingSplitViewShell(
            activeStep: OnboardingStep.customiseAccount,
            showPasswordStep: true,
            child: CustomiseAccountScreen(
              args: CustomiseAccountArgs(
                mnemonic: _previewMnemonic,
                pendingPassword: 'PreviewPassword1!',
              ),
              random: Random(1234),
              onFinish: (_, _) async {},
            ),
          ),
        ),
        GoRoute(
          path: OnboardingStep.setPassword.routePath,
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/onboarding/set-password'),
        ),
        GoRoute(
          path: OnboardingStep.secretPassphrase.routePath,
          builder: (_, _) => const _PreviewRoutePlaceholder(
            label: '/onboarding/secret-passphrase',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _UnlockHarness extends StatefulWidget {
  @override
  State<_UnlockHarness> createState() => _UnlockHarnessState();
}

class _UnlockHarnessState extends State<_UnlockHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/unlock',
      routes: [
        GoRoute(
          path: '/unlock',
          // Preview-only: keep navigation inert inside Widgetbook.
          builder: (_, _) => const IgnorePointer(child: UnlockScreen()),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/lost-password',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/lost-password'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

Widget _buildMobileUnlockUseCase(BiometricUnlockState biometricState) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(biometricState),
      ),
    ],
    child: _MobilePreviewFrame(
      child: IgnorePointer(
        child: MobileUnlockScreen(autoPromptBiometric: false),
      ),
    ),
  );
}

Widget _buildMobileBiometricOptInUseCase(BiometricUnlockState biometricState) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(biometricState),
      ),
    ],
    child: const _MobilePreviewFrame(
      child: IgnorePointer(child: MobileBiometricsScreen()),
    ),
  );
}

Widget _buildMobileUnlockModalUseCase(BuildContext context, Widget sheet) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(
          const BiometricUnlockState(
            availability: BiometricAvailability(
              supported: true,
              enrolled: true,
              kind: BiometricKind.face,
            ),
            enabled: true,
          ),
        ),
      ),
    ],
    child: _MobilePreviewFrame(
      child: Stack(
        children: [
          const IgnorePointer(
            child: MobileUnlockScreen(autoPromptBiometric: false),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: AppTheme.of(context).colors.background.neutralScrim,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                ),
                child: MobileModalCard(child: sheet),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildMobileModalSnapshotUseCase(BuildContext context, Widget sheet) {
  return Center(
    child: SizedBox.fromSize(
      size: const Size(393, 435),
      child: ClipRect(
        child: ColoredBox(
          color: AppTheme.of(context).colors.background.neutralScrim,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(393, 435),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
              ),
              child: MobileModalCard(child: sheet),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MobileSecretPassphraseProtectedPreview extends StatefulWidget {
  const _MobileSecretPassphraseProtectedPreview();

  @override
  State<_MobileSecretPassphraseProtectedPreview> createState() =>
      _MobileSecretPassphraseProtectedPreviewState();
}

class _MobileSecretPassphraseProtectedPreviewState
    extends State<_MobileSecretPassphraseProtectedPreview> {
  late final SensitivePrivacyOverlayController _privacyController =
      SensitivePrivacyOverlayController(initiallySafe: false);

  @override
  void dispose() {
    _privacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MobilePreviewFrame(
      child: IgnorePointer(
        child: MobileSecretPassphraseScreen(
          args: const CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
          screenshotStream: const Stream.empty(),
          privacyOverlayController: _privacyController,
        ),
      ),
    );
  }
}

class _MobilePreviewFrame extends StatelessWidget {
  const _MobilePreviewFrame({required this.child});

  final Widget child;

  static const size = Size(393, 852);
  static const safeAreaPadding = EdgeInsets.only(top: 55, bottom: 24);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: ClipRect(
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: size,
              padding: safeAreaPadding,
              viewPadding: safeAreaPadding,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PreviewBiometricUnlockNotifier extends BiometricUnlockNotifier {
  _PreviewBiometricUnlockNotifier(this.initialState);

  final BiometricUnlockState initialState;

  @override
  Future<BiometricUnlockState> build() async => initialState;

  @override
  Future<String?> readPasscode({required String reason}) async => null;
}

/// The schedule screens reach for `GoRouter` to resolve their back
/// destination, so they need a router even in a static preview. Without one the
/// whole screen renders as an error box instead of the schedule.
class _MobileMigrationScheduleHarness extends StatefulWidget {
  const _MobileMigrationScheduleHarness({
    required this.preparation,
    required this.status,
  });

  final bool preparation;
  final rust_sync.MigrationStatus status;

  @override
  State<_MobileMigrationScheduleHarness> createState() =>
      _MobileMigrationScheduleHarnessState();
}

class _MobileMigrationScheduleHarnessState
    extends State<_MobileMigrationScheduleHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.preparation
          ? '/migration/private/preparation-schedule'
          : '/migration/private/schedule',
      routes: [
        GoRoute(
          path: '/migration/private/schedule',
          builder: (_, _) => MobileIronwoodMigrationScheduleScreen(
            previewStatus: widget.status,
          ),
        ),
        GoRoute(
          path: '/migration/private/preparation-schedule',
          builder: (_, _) => MobileIronwoodMigrationPreparationScheduleScreen(
            previewStatus: widget.status,
          ),
        ),
        // Stub destination so back / Return in the preview resolve instead of
        // throwing if a reviewer taps them.
        GoRoute(
          path: '/migration/private/status',
          builder: (_, _) => const _PreviewRoutePlaceholder(
            label: '/migration/private/status',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

class _PreviewRoutePlaceholder extends StatelessWidget {
  const _PreviewRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

final _accountsDesignState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: 'preview-account-1',
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'preview-account-2',
      name: 'Account Name',
      order: 1,
      isHardware: true,
      profilePictureId: 'pfp-01',
    ),
    AccountInfo(
      uuid: 'preview-account-3',
      name: 'Account Name',
      order: 2,
      profilePictureId: 'pfp-02',
    ),
    AccountInfo(
      uuid: 'preview-account-4',
      name: 'Account Name',
      order: 3,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: 'preview-account-1',
  activeAddress: 'u1widgetbookaccountsaddress',
);

final _ironwoodMobileHomeAccountState = _accountsDesignState.copyWith(
  accounts: [
    for (final account in _accountsDesignState.accounts)
      account.uuid == _accountsDesignState.activeAccountUuid
          ? account.copyWith(name: 'Wallet 1')
          : account,
  ],
);

final _accountsManyState = AccountState(
  accounts: [
    const AccountInfo(
      uuid: 'preview-account-1',
      name: 'Primary Vault',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    for (var index = 2; index <= 20; index += 1)
      AccountInfo(
        uuid: 'preview-account-$index',
        name: index == 2 ? 'Keystone Vault' : 'Account $index',
        order: index - 1,
        isHardware: index == 2,
        profilePictureId: index.isEven ? 'pfp-02' : 'pfp-01',
      ),
  ],
  activeAccountUuid: 'preview-account-1',
  activeAddress: 'u1widgetbookaccountsaddress',
);

AccountState _ironwoodMigrationAccountState({bool isHardware = false}) {
  return AccountState(
    accounts: [
      for (final account in _accountsDesignState.accounts)
        account.uuid == _accountsDesignState.activeAccountUuid
            ? AccountInfo(
                uuid: account.uuid,
                name: 'Username',
                order: account.order,
                isHardware: isHardware,
                isSeedAnchor: account.isSeedAnchor,
                profilePictureId: account.profilePictureId,
              )
            : account,
    ],
    activeAccountUuid: _accountsDesignState.activeAccountUuid,
    activeAddress: _accountsDesignState.activeAddress,
  );
}

const _homeKeystoneAccountUuid = 'preview-keystone-account';

final _homeKeystoneState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _homeKeystoneAccountUuid,
      name: 'Keystone Vault',
      order: 0,
      isHardware: true,
      profilePictureId: 'pfp-02',
    ),
  ],
  activeAccountUuid: _homeKeystoneAccountUuid,
  activeAddress: 'u1widgetbookkeystoneaddress',
);

const _mobileHomeTabItems = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

AppBootstrapState _accountsBootstrap(
  AccountState accountState, {
  String initialLocation = '/accounts',
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

AppBootstrapState _utilityBootstrap(
  String initialLocation,
  AccountState accountState,
) {
  final hasWallet = accountState.accounts.isNotEmpty;
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: hasWallet,
    isUnlocked: hasWallet,
    passwordRotationRecoveryFailed: false,
  );
}

AppBootstrapState _homeBootstrap(AccountState accountState) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _homeSyncedState({
  String? accountUuid,
  BigInt? orchardBalance,
  BigInt? ironwoodBalance,
  BigInt? transparentBalance,
  bool canShieldTransparentBalance = false,
  List<rust_sync.TransactionInfo> recentTransactions = const [],
}) {
  final resolvedOrchardBalance = orchardBalance ?? BigInt.zero;
  final resolvedIronwoodBalance = ironwoodBalance ?? BigInt.zero;
  final resolvedTransparentBalance = transparentBalance ?? BigInt.zero;
  return SyncState(
    accountUuid: accountUuid ?? _accountsDesignState.activeAccountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    displayPercentage: 1,
    scannedHeight: 3_428_143,
    chainTipHeight: 3_428_143,
    orchardBalance: resolvedOrchardBalance,
    ironwoodBalance: resolvedIronwoodBalance,
    transparentBalance: resolvedTransparentBalance,
    canShieldTransparentBalance: canShieldTransparentBalance,
    spendableBalance: resolvedOrchardBalance + resolvedIronwoodBalance,
    totalBalance:
        resolvedOrchardBalance +
        resolvedIronwoodBalance +
        resolvedTransparentBalance,
    recentTransactions: recentTransactions,
  );
}

rust_sync.TransactionInfo _homeTx(int index) {
  final seconds = BigInt.from(1800000000 + index);
  return rust_sync.TransactionInfo(
    txidHex: 'preview-home-tx-$index',
    minedHeight: BigInt.from(1000 + index),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: seconds,
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(index) * BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: seconds,
  );
}

rust_sync.MigrationStatus _previewMigrationStatus(
  String phase, {
  String? activeRunId,
  List<rust_sync.MigrationPartStatus> parts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 0,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: parts,
  );
}

IronwoodMigrationFlowData _ironwoodMigrationFlowData({
  required BigInt zatoshi,
  String accountName = 'Username',
}) {
  return IronwoodMigrationFlowData(
    amountZatoshi: zatoshi,
    accountName: accountName,
    profilePictureId: kDefaultProfilePictureId,
  );
}

rust_sync.OrchardMigrationPrivatePlan _previewPrivateMigrationPlan() {
  return rust_sync.OrchardMigrationPrivatePlan(
    targetValuesZatoshi: frb.Uint64List.fromList([
      8_000_000_000,
      4_000_000_000,
      1_000_000_000,
      500_000_000,
      500_000_000,
      220_000_000,
    ]),
    totalInputZatoshi: BigInt.from(14_224_000_000),
    totalMigratableZatoshi: BigInt.from(14_220_000_000),
    orchardChangeZatoshi: BigInt.from(100_000),
    denominationSplitFeeZatoshi: BigInt.from(600_000),
    migrationFeeZatoshi: BigInt.from(600_000),
    estimatedTotalFeeZatoshi: BigInt.from(1_200_000),
    plannedBatchCount: 6,
    denominationSplitStageCount: 2,
    denominationSplitLayerCount: 2,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    proofReadinessDelayBlocks: 146,
    scheduledTransfers: [
      rust_sync.MigrationScheduledTransfer(
        partIndex: 1,
        valueZatoshi: BigInt.from(4_000_000_000),
        blockOffset: 144,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 3,
        valueZatoshi: BigInt.from(500_000_000),
        blockOffset: 288,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 0,
        valueZatoshi: BigInt.from(8_000_000_000),
        blockOffset: 432,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 5,
        valueZatoshi: BigInt.from(220_000_000),
        blockOffset: 576,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 4,
        valueZatoshi: BigInt.from(500_000_000),
        blockOffset: 720,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 2,
        valueZatoshi: BigInt.from(1_000_000_000),
        blockOffset: 864,
      ),
    ],
  );
}

rust_sync.OrchardMigrationImmediatePlan _previewMobileImmediateMigrationPlan() {
  return rust_sync.OrchardMigrationImmediatePlan(
    totalInputZatoshi: BigInt.from(14_223_060_000),
    feeZatoshi: BigInt.from(60_000),
    migratedZatoshi: BigInt.from(14_223_000_000),
    inputNoteCount: 12,
  );
}

rust_sync.OrchardMigrationPrivatePlan _previewMobilePrivateMigrationPlan() {
  return rust_sync.OrchardMigrationPrivatePlan(
    targetValuesZatoshi: frb.Uint64List.fromList([
      4_000_000_000,
      500_000_000,
      8_000_000_000,
      100_000_000,
      500_000_000,
      1_000_000_000,
    ]),
    totalInputZatoshi: BigInt.from(14_223_000_000),
    totalMigratableZatoshi: BigInt.from(14_220_000_000),
    orchardChangeZatoshi: BigInt.zero,
    denominationSplitFeeZatoshi: BigInt.from(150_000),
    migrationFeeZatoshi: BigInt.from(150_000),
    estimatedTotalFeeZatoshi: BigInt.from(300_000),
    plannedBatchCount: 6,
    denominationSplitStageCount: 1,
    denominationSplitLayerCount: 1,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 960,
    proofReadinessDelayBlocks: 146,
    scheduledTransfers: [
      rust_sync.MigrationScheduledTransfer(
        partIndex: 0,
        valueZatoshi: BigInt.from(4_000_000_000),
        blockOffset: 12,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 1,
        valueZatoshi: BigInt.from(500_000_000),
        blockOffset: 960,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 2,
        valueZatoshi: BigInt.from(8_000_000_000),
        blockOffset: 960,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 3,
        valueZatoshi: BigInt.from(100_000_000),
        blockOffset: 960,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 4,
        valueZatoshi: BigInt.from(500_000_000),
        blockOffset: 960,
      ),
      rust_sync.MigrationScheduledTransfer(
        partIndex: 5,
        valueZatoshi: BigInt.from(1_000_000_000),
        blockOffset: 960,
      ),
    ],
  );
}

rust_sync.MigrationStatus _previewMobileMigrationStatus() {
  final completion = DateTime(2026, 7, 20, 10);
  const values = [
    4_000_000_000,
    500_000_000,
    8_000_000_000,
    100_000_000,
    500_000_000,
    1_000_000_000,
  ];
  const statuses = [
    'confirmed',
    'needs_input',
    'broadcasted',
    'scheduled',
    'scheduled',
    'scheduled',
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'preview-mobile-run',
    targetValuesZatoshi: frb.Uint64List.fromList(values),
    preparedNoteCount: 6,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 4,
    broadcastedTxCount: 2,
    confirmedTxCount: 1,
    totalCount: 6,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: [
      for (var i = 0; i < values.length; i++)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'preview-mobile-tx-$i',
          valueZatoshi: BigInt.from(values[i]),
          scheduledAtMs: completion.millisecondsSinceEpoch,
          scheduledHeight: 3_000_000 + 960,
          status: statuses[i],
        ),
    ],
    parts: const [],
  );
}

rust_sync.MigrationStatus _previewMobileHomeMigrationStatus() {
  final scheduledAt = DateTime(2026, 7, 20, 10).millisecondsSinceEpoch;
  const values = [
    4_001_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'preview-mobile-home-run',
    targetValuesZatoshi: frb.Uint64List.fromList(values),
    preparedNoteCount: values.length,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 5,
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: values.length,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 960,
    scheduledBroadcasts: [
      for (var i = 0; i < values.length; i++)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'preview-mobile-home-tx-$i',
          valueZatoshi: BigInt.from(values[i]),
          scheduledAtMs: scheduledAt,
          scheduledHeight: 3_000_960,
          status: i == 0 ? 'confirmed' : 'scheduled',
        ),
    ],
    parts: const [],
  );
}

rust_sync.MigrationPreparationOutputStatus _previewPreparationOutput(
  int valueZatoshi,
  rust_sync.MigrationPreparationOutputKind kind, {
  int? nextRound,
}) => rust_sync.MigrationPreparationOutputStatus(
  valueZatoshi: BigInt.from(valueZatoshi),
  kind: kind,
  nextRound: nextRound,
);

rust_sync.MigrationPreparationTransactionStatus _previewPreparationTransaction({
  required int stageIndex,
  required int valueZatoshi,
  required int round,
  required int plannedHeight,
  required int projectedHeight,
  required rust_sync.MigrationPreparationTransactionState state,
  required List<rust_sync.MigrationPreparationOutputStatus> outputs,
  int? scheduledHeight,
  int? minedHeight,
  int confirmationCount = 0,
}) => rust_sync.MigrationPreparationTransactionStatus(
  stageIndex: stageIndex,
  approximateValueZatoshi: BigInt.from(valueZatoshi),
  round: round,
  feeZatoshi: BigInt.from(10_000),
  plannedHeight: plannedHeight,
  projectedHeight: projectedHeight,
  projectedCompletionHeight: (minedHeight ?? projectedHeight) + 3,
  outputs: outputs,
  state: state,
  scheduledHeight: scheduledHeight,
  minedHeight: minedHeight,
  confirmationCount: confirmationCount,
  confirmationTarget: 3,
);

rust_sync.MigrationStatus _previewPrivateMigrationStatus() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    activeRunId: 'preview-run',
    targetValuesZatoshi: frb.Uint64List.fromList([
      8_000_000_000,
      4_000_000_000,
      1_000_000_000,
      500_000_000,
      500_000_000,
      220_000_000,
    ]),
    preparedNoteCount: 6,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 1,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 6,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    preparationMeanDelayBlocks: 24,
    scheduledBroadcasts: const [],
    preparationTransactions: [
      _previewPreparationTransaction(
        stageIndex: 0,
        valueZatoshi: 14_220_000_000,
        round: 1,
        plannedHeight: 2_999_712,
        projectedHeight: 2_999_716,
        state: rust_sync.MigrationPreparationTransactionState.completed,
        scheduledHeight: 2_999_712,
        minedHeight: 2_999_716,
        confirmationCount: 3,
        outputs: [
          _previewPreparationOutput(
            10_000_000_000,
            rust_sync.MigrationPreparationOutputKind.continuation,
            nextRound: 2,
          ),
          _previewPreparationOutput(
            4_219_990_000,
            rust_sync.MigrationPreparationOutputKind.migration,
          ),
        ],
      ),
      _previewPreparationTransaction(
        stageIndex: 1,
        valueZatoshi: 8_000_000_000,
        round: 1,
        plannedHeight: 2_999_856,
        projectedHeight: 2_999_998,
        state: rust_sync.MigrationPreparationTransactionState.confirming,
        scheduledHeight: 2_999_856,
        minedHeight: 2_999_998,
        confirmationCount: 2,
        outputs: [
          _previewPreparationOutput(
            5_000_000_000,
            rust_sync.MigrationPreparationOutputKind.migration,
          ),
          _previewPreparationOutput(
            2_999_990_000,
            rust_sync.MigrationPreparationOutputKind.change,
          ),
        ],
      ),
      _previewPreparationTransaction(
        stageIndex: 2,
        valueZatoshi: 4_000_000_000,
        round: 1,
        plannedHeight: 3_000_000,
        projectedHeight: 3_000_000,
        state: rust_sync.MigrationPreparationTransactionState.broadcasted,
        scheduledHeight: 3_000_000,
        outputs: [
          _previewPreparationOutput(
            3_999_990_000,
            rust_sync.MigrationPreparationOutputKind.migration,
          ),
        ],
      ),
      _previewPreparationTransaction(
        stageIndex: 3,
        valueZatoshi: 2_000_000_000,
        round: 1,
        plannedHeight: 3_000_144,
        projectedHeight: 3_000_144,
        state: rust_sync.MigrationPreparationTransactionState.scheduled,
        scheduledHeight: 3_000_144,
        outputs: [
          _previewPreparationOutput(
            1_999_990_000,
            rust_sync.MigrationPreparationOutputKind.migration,
          ),
        ],
      ),
      _previewPreparationTransaction(
        stageIndex: 4,
        valueZatoshi: 10_000_000_000,
        round: 2,
        plannedHeight: 3_000_171,
        projectedHeight: 3_000_171,
        state: rust_sync.MigrationPreparationTransactionState.awaitingInputs,
        outputs: [
          _previewPreparationOutput(
            9_999_990_000,
            rust_sync.MigrationPreparationOutputKind.migration,
          ),
        ],
      ),
      _previewPreparationTransaction(
        stageIndex: 5,
        valueZatoshi: 500_000_000,
        round: 2,
        plannedHeight: 3_000_195,
        projectedHeight: 3_000_195,
        state: rust_sync.MigrationPreparationTransactionState.awaitingInputs,
        outputs: [
          _previewPreparationOutput(
            499_990_000,
            rust_sync.MigrationPreparationOutputKind.change,
          ),
        ],
      ),
    ],
    parts: const [],
  );
}

rust_sync.MigrationStatus _previewPrivateMigrationTransferStatus() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'preview-run',
    targetValuesZatoshi: frb.Uint64List.fromList([
      8_000_000_000,
      4_000_000_000,
      1_000_000_000,
      500_000_000,
      500_000_000,
      220_000_000,
    ]),
    preparedNoteCount: 6,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 3,
    broadcastedTxCount: 3,
    confirmedTxCount: 2,
    totalCount: 6,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    estimatedCompletionHeight: 3_000_216,
    scheduledBroadcasts: [
      rust_sync.MigrationScheduledBroadcast(
        txidHex: 'preview-txid',
        valueZatoshi: BigInt.from(1_000_000_000),
        scheduledAtMs: DateTime(2026, 7, 18, 12).millisecondsSinceEpoch,
        scheduledHeight: 3_000_144,
        status: 'scheduled',
      ),
    ],
    parts: [
      _previewMigrationPart(
        1,
        4_000_000_000,
        rust_sync.MigrationPartState.completed,
        scheduleOrder: 3,
        scheduledHeight: 3_000_100,
      ),
      _previewMigrationPart(
        4,
        500_000_000,
        rust_sync.MigrationPartState.migrating,
        scheduleOrder: 0,
        scheduledHeight: 3_000_200,
      ),
      _previewMigrationPart(
        0,
        8_000_000_000,
        rust_sync.MigrationPartState.scheduled,
        scheduleOrder: 1,
        scheduledHeight: 3_000_300,
      ),
      _previewMigrationPart(
        5,
        220_000_000,
        rust_sync.MigrationPartState.scheduled,
        scheduleOrder: 2,
        scheduledHeight: 3_000_400,
      ),
      _previewMigrationPart(
        3,
        500_000_000,
        rust_sync.MigrationPartState.scheduled,
        scheduleOrder: 4,
        scheduledHeight: 3_000_500,
      ),
      _previewMigrationPart(
        2,
        1_000_000_000,
        rust_sync.MigrationPartState.scheduled,
        scheduleOrder: 5,
        scheduledHeight: 3_000_600,
      ),
    ],
  );
}

rust_sync.MigrationStatus _previewPrivateMigrationNeedsInputStatus() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationReadyToMigratePhase,
    activeRunId: 'preview-run',
    targetValuesZatoshi: frb.Uint64List.fromList([
      8_000_000_000,
      4_000_000_000,
      1_000_000_000,
      500_000_000,
      500_000_000,
      220_000_000,
    ]),
    preparedNoteCount: 6,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 4,
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: 6,
    signedChildPcztCount: 2,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: [
      _previewMigrationPart(
        0,
        4_000_000_000,
        rust_sync.MigrationPartState.completed,
      ),
      _previewMigrationPart(
        1,
        500_000_000,
        rust_sync.MigrationPartState.needsInput,
      ),
      _previewMigrationPart(
        2,
        8_000_000_000,
        rust_sync.MigrationPartState.migrating,
      ),
      _previewMigrationPart(
        3,
        220_000_000,
        rust_sync.MigrationPartState.scheduled,
      ),
      _previewMigrationPart(
        4,
        500_000_000,
        rust_sync.MigrationPartState.scheduled,
      ),
      _previewMigrationPart(
        5,
        1_000_000_000,
        rust_sync.MigrationPartState.scheduled,
      ),
    ],
  );
}

rust_sync.MigrationStatus _previewPostPrepareWaitingStatus() =>
    _previewPostPrepareStatus(
      phase: kIronwoodMigrationReadyToMigratePhase,
      parts: _previewPostPrepareParts(),
      proofReady: false,
    );

rust_sync.MigrationStatus _previewPostPrepareSigningStatus() =>
    _previewPostPrepareStatus(
      phase: kIronwoodMigrationReadyToMigratePhase,
      parts: _previewPostPrepareParts(
        firstState: rust_sync.MigrationPartState.needsInput,
      ),
      proofReady: true,
      currentSigningPartIndices: const [0, 1, 2],
    );

rust_sync.MigrationStatus _previewPostPrepareProgressedStatus() =>
    _previewPostPrepareStatus(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      parts: _previewPostPrepareParts(completedNoteCount: 1),
    );

rust_sync.MigrationStatus _previewPostPrepareActiveStatus() =>
    _previewPostPrepareStatus(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      parts: _previewPostPrepareParts(
        completedNoteCount: 1,
        activeNoteIndex: 1,
      ),
    );

const _migrationSchedulePreviewValues = <int>[
  4_000_000_000,
  1_000_000_000,
  215_000_000,
  3_500_000_000,
  400_000_000,
  100_000_000,
  100_000_000,
  100_000_000,
  585_000_000,
];

rust_sync.MigrationStatus _previewMigrationScheduleStatus() {
  final parts = [
    for (var index = 0; index < _migrationSchedulePreviewValues.length; index++)
      _previewMigrationPart(
        index,
        _migrationSchedulePreviewValues[index],
        index < 4
            ? rust_sync.MigrationPartState.completed
            : index == 4
            ? rust_sync.MigrationPartState.confirming
            : rust_sync.MigrationPartState.preparing,
        scheduleOrder: index,
        scheduledHeight: 3_000_030 + index * 18,
        confirmationCount: index == 4 ? 1 : null,
      ),
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationBroadcastScheduledPhase,
    activeRunId: 'migration-schedule-preview-run',
    targetValuesZatoshi: frb.Uint64List.fromList(
      _migrationSchedulePreviewValues,
    ),
    preparedNoteCount: parts.length,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 5,
    broadcastedTxCount: 5,
    confirmedTxCount: 4,
    totalCount: parts.length,
    signedChildPcztCount: 4,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    scheduleMeanDelayBlocks: 108,
    scheduleMaxDelayBlocks: 432,
    nextProofWindowHeight: 3_000_144,
    nextProofWindowPartIndices: frb.Uint32List.fromList(const [5, 6, 7, 8]),
    proofReady: false,
    estimatedCompletionHeight: 3_000_216,
    scheduledBroadcasts: const [],
    parts: parts,
  );
}

/// A run early enough that Rust has only committed a height to the parts it has
/// already signed and promoted. The rest arrive as `preparing` with no height,
/// which is what the schedule surface has to project a cadence for.
rust_sync.MigrationStatus _previewMigrationSchedulePendingStatus() {
  const assignedHeights = <int?>[
    2_999_930,
    2_999_948,
    2_999_966,
    3_000_120,
    null,
    null,
    null,
    null,
    null,
  ];
  final parts = [
    for (var index = 0; index < _migrationSchedulePreviewValues.length; index++)
      _previewMigrationPart(
        index,
        _migrationSchedulePreviewValues[index],
        index < 2
            ? rust_sync.MigrationPartState.completed
            : index == 2
            ? rust_sync.MigrationPartState.confirming
            : index == 3
            ? rust_sync.MigrationPartState.scheduled
            : rust_sync.MigrationPartState.preparing,
        scheduleOrder: index,
        scheduledHeight: assignedHeights[index],
        confirmationCount: index == 2 ? 1 : null,
      ),
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'migration-schedule-pending-preview-run',
    targetValuesZatoshi: frb.Uint64List.fromList(
      _migrationSchedulePreviewValues,
    ),
    preparedNoteCount: parts.length,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 4,
    broadcastedTxCount: 3,
    confirmedTxCount: 2,
    totalCount: parts.length,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    scheduleMeanDelayBlocks: 108,
    scheduleMaxDelayBlocks: 432,
    scheduledBroadcasts: const [],
    parts: parts,
  );
}

const _postPrepareNoteValues = <int>[
  4_000_000_000,
  3_500_000_000,
  2_500_000_000,
];

List<rust_sync.MigrationPartStatus> _previewPostPrepareParts({
  rust_sync.MigrationPartState firstState =
      rust_sync.MigrationPartState.scheduled,
  int completedNoteCount = 0,
  int? activeNoteIndex,
}) => [
  for (var index = 0; index < _postPrepareNoteValues.length; index++)
    _previewMigrationPart(
      index,
      _postPrepareNoteValues[index],
      index < completedNoteCount
          ? rust_sync.MigrationPartState.completed
          : index == activeNoteIndex
          ? rust_sync.MigrationPartState.confirming
          : index == 0
          ? firstState
          : rust_sync.MigrationPartState.scheduled,
    ),
];

rust_sync.MigrationStatus _previewPostPrepareStatus({
  required String phase,
  required List<rust_sync.MigrationPartStatus> parts,
  bool? proofReady,
  List<int> currentSigningPartIndices = const [],
}) => rust_sync.MigrationStatus(
  phase: phase,
  activeRunId: 'post-prepare-preview-run',
  targetValuesZatoshi: frb.Uint64List.fromList(_postPrepareNoteValues),
  preparedNoteCount: _postPrepareNoteValues.length,
  denominationConfirmationCount: 3,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 1,
  denominationSplitTotalCount: 1,
  pendingTxCount: _postPrepareNoteValues.length,
  broadcastedTxCount: 1,
  confirmedTxCount: parts
      .where((part) => part.state == rust_sync.MigrationPartState.completed)
      .length,
  totalCount: _postPrepareNoteValues.length,
  signedChildPcztCount: 0,
  pendingSplitStageCount: 0,
  canAbandon: false,
  signingBatchLimit: 8,
  scheduleMeanDelayBlocks: 108,
  scheduleMaxDelayBlocks: 432,
  proofReady: proofReady,
  currentSigningPartIndices: currentSigningPartIndices.isEmpty
      ? null
      : frb.Uint32List.fromList(currentSigningPartIndices),
  scheduledBroadcasts: const [],
  parts: parts,
);

rust_sync.MigrationPartStatus _previewMigrationPart(
  int partIndex,
  int valueZatoshi,
  rust_sync.MigrationPartState state, {
  int? scheduleOrder,
  int? scheduledHeight,
  int? confirmationCount,
}) {
  return rust_sync.MigrationPartStatus(
    partIndex: partIndex,
    scheduleOrder: scheduleOrder,
    valueZatoshi: BigInt.from(valueZatoshi),
    state: state,
    scheduledHeight: scheduledHeight,
    confirmationCount:
        confirmationCount ??
        (state == rust_sync.MigrationPartState.completed ? 3 : 0),
    confirmationTarget: 3,
  );
}

class _PreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _PreviewNetworkPrivacyNotifier(this.initialState);

  final NetworkPrivacyState initialState;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

class _PreviewAccountNotifier extends AccountNotifier {
  _PreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }

  @override
  Future<void> renameAccount(String uuid, String newName) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(name: newName)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(profilePictureId: profilePictureId)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> removeAccount(String uuid) async {
    final prev = state.value ?? initialState;
    final updated = [
      for (final account in prev.accounts)
        if (account.uuid != uuid) account,
    ];
    state = AsyncData(prev.copyWith(accounts: updated));
  }

  @override
  Future<void> resetWallet() async {
    state = const AsyncData(AccountState());
  }
}

class _PreviewMigrationCoordinator extends IronwoodMigrationCoordinator {
  _PreviewMigrationCoordinator({required this.accountUuid, this.status});

  final String? accountUuid;
  final rust_sync.MigrationStatus? status;

  @override
  IronwoodMigrationCoordinatorState build() {
    final uuid = accountUuid;
    final previewStatus = status;
    return IronwoodMigrationCoordinatorState(
      statuses: uuid == null || previewStatus == null
          ? const {}
          : {uuid: previewStatus},
    );
  }

  @override
  Future<void> recover(String accountUuid) async {
    state = state.copyWith(
      errors: Map<String, String>.from(state.errors)..remove(accountUuid),
    );
  }
}

class _PreviewSyncNotifier extends SyncNotifier {
  _PreviewSyncNotifier(this.activeAccountUuid, {this.initialState});

  final String? activeAccountUuid;
  final SyncState? initialState;

  @override
  Future<SyncState> build() async =>
      initialState ??
      SyncState(
        accountUuid: activeAccountUuid,
        hasAccountScopedData: activeAccountUuid != null,
        isSyncing: true,
        percentage: 0.34,
        displayPercentage: 0.34,
        totalBalance: BigInt.from(14223000000),
      );

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> refreshAfterAccountSwitch() async {}

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {}

  @override
  Future<void> clearSensitiveStateForLock() async {}
}

class _PreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _PreviewZecMarketDataSource implements ZecMarketDataSource {
  const _PreviewZecMarketDataSource(this.data);

  final ZecMarketData? data;

  @override
  Future<ZecMarketData?> fetchMarketData() async => data;
}

class _PreviewReceiveAddressService implements ReceiveAddressService {
  const _PreviewReceiveAddressService();

  @override
  String? getCachedTransparentAddress(String accountUuid) =>
      't1WidgetbookTransparentAddress';

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return currentShieldedAddress?.isNotEmpty == true
        ? currentShieldedAddress!
        : 'u1widgetbookaccountsaddress';
  }

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    return 't1WidgetbookTransparentAddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1widgetbookaccountsrenewedaddress';
  }
}
