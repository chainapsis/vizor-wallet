// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/privacy/sensitive_privacy_overlay.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/biometric_icon.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart'
    show AddressQrCameraStatus;
import '../src/features/keystone/widgets/keystone_scan_help_overlay.dart';
import '../src/features/keystone/widgets/keystone_transaction_progress_panel.dart';
import '../src/features/onboarding/create/address_types_screen.dart';
import '../src/features/onboarding/create/intro_zcash_screen.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/create/secret_passphrase_screen.dart';
import '../src/features/onboarding/create/things_to_know_screen.dart';
import '../src/features/onboarding/import/import_account_discovery_modal.dart';
import '../src/features/onboarding/import/import_birthday_calendar_overlay.dart';
import '../src/features/onboarding/import/import_birthday_estimator.dart';
import '../src/features/onboarding/import/import_birthday_unknown_height_modal.dart';
import '../src/features/onboarding/import/import_split_view.dart';
import '../src/features/onboarding/import/import_wallet_birthday_screen.dart';
import '../src/features/onboarding/keystone/keystone_how_to_connect_screen.dart';
import '../src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import '../src/features/onboarding/keystone/keystone_select_account_screen.dart';
import '../src/features/onboarding/keystone/keystone_wallet_birthday_screen.dart';
import '../src/features/onboarding/lost_password_screen.dart';
import '../src/features/onboarding/mobile/mobile_biometrics_screen.dart';
import '../src/features/onboarding/mobile/mobile_create_steps.dart';
import '../src/features/onboarding/mobile/mobile_import_account_discovery_sheet.dart';
import '../src/features/onboarding/mobile/mobile_import_birthday_unknown_height_sheet.dart';
import '../src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_scaffold.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../src/features/onboarding/mobile/mobile_unlock_screen.dart';
import '../src/features/onboarding/mobile/seed_card.dart';
import '../src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../src/features/onboarding/mobile/passcode_widgets.dart';
import '../src/features/onboarding/shared/onboarding_auth_shell.dart';
import '../src/features/onboarding/shared/onboarding_chrome.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/onboarding/shared/set_password_screen.dart';
import '../src/features/onboarding/storage_unavailable_screen.dart';
import '../src/features/onboarding/unlock_screen.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import '../src/features/wallet_link/models/wallet_link_models.dart';
import '../src/features/wallet_link/providers/mobile_wallet_link_provider.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/providers/rpc_endpoint_failover_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/rust/api/wallet.dart' as rust_wallet;
import '../src/services/biometric_unlock.dart';
import '../src/rust/wallet/keystone.dart' show KeystoneAccountInfo;
import 'support/wb_layout.dart';

/// Desktop onboarding fixtures for `gallery/onboarding_gallery.dart`.
///
/// Everything here is a deterministic dev-only mock: no Rust, no storage, no
/// network. The create-flow screens navigate with `context.go`, so each one
/// runs inside a throwaway `GoRouter` whose destinations are placeholders.
const _previewMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse '
    'access accident account accuse achieve acid acoustic acquire across act '
    'action actor actress actual';

const _previewKeystoneUfvk = 'uview1previewkeystoneaccount';

// --- Create flow: intro / address types / things to know -------------------

Widget buildOnboardingIntroZcashUseCase(BuildContext context) {
  return _onboardingCreateStep(
    step: OnboardingStep.intro,
    // The intro's back target is the welcome screen, not a previous step.
    stubPaths: const [
      '/welcome',
      '/onboarding/address-types',
      '/onboarding/secret-passphrase',
    ],
    child: const IntroZcashScreen(),
  );
}

Widget buildOnboardingAddressTypesUseCase(BuildContext context) {
  return _onboardingCreateStep(
    step: OnboardingStep.addressTypes,
    stubPaths: const ['/onboarding/intro', '/onboarding/things-to-know'],
    child: const AddressTypesScreen(),
  );
}

Widget buildOnboardingThingsToKnowUseCase(BuildContext context) {
  return _onboardingCreateStep(
    step: OnboardingStep.thingsToKnow,
    stubPaths: const [
      '/onboarding/address-types',
      '/onboarding/secret-passphrase',
    ],
    child: const ThingsToKnowScreen(),
  );
}

// --- Create flow: secret passphrase ----------------------------------------

/// Seed-reveal step. `args` stays null and the two create-flow providers carry
/// the phrase instead, so the screen never reaches `generateMnemonic()`.
Widget onboardingSecretPassphraseFixture({
  required bool revealed,
  required bool privacyProtected,
}) {
  return ProviderScope(
    overrides: [
      createOnboardingMnemonicProvider.overrideWith(
        () => _PreviewCreateMnemonicNotifier(_previewMnemonic),
      ),
      onboardingSecretPassphraseRevealedProvider.overrideWith(
        () => _PreviewSecretPassphraseRevealedNotifier(revealed),
      ),
    ],
    child: _SecretPassphrasePreview(
      key: ValueKey('onboarding-secret-passphrase-$revealed-$privacyProtected'),
      privacyProtected: privacyProtected,
    ),
  );
}

class _SecretPassphrasePreview extends StatefulWidget {
  const _SecretPassphrasePreview({required this.privacyProtected, super.key});

  final bool privacyProtected;

  @override
  State<_SecretPassphrasePreview> createState() =>
      _SecretPassphrasePreviewState();
}

class _SecretPassphrasePreviewState extends State<_SecretPassphrasePreview> {
  late final SensitivePrivacyOverlayController _privacyController =
      SensitivePrivacyOverlayController(
        initiallySafe: !widget.privacyProtected,
      );

  @override
  void dispose() {
    _privacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingFlowHarness(
      location: OnboardingStep.secretPassphrase.routePath,
      stubPaths: const [
        '/onboarding/things-to-know',
        '/onboarding/set-password',
        '/onboarding/customise-account',
      ],
      builder: (_) => OnboardingSplitViewShell(
        activeStep: OnboardingStep.secretPassphrase,
        showPasswordStep: true,
        child: SecretPassphraseScreen(
          privacyOverlayController: _privacyController,
        ),
      ),
    );
  }
}

// --- Set password ----------------------------------------------------------

/// The password step of all four setup flows. `flow` picks both the args and
/// the sidebar shell the real route wraps the screen in.
Widget onboardingSetPasswordFixture({required SetPasswordFlow flow}) {
  final args = _setPasswordArgs(flow);
  return ProviderScope(
    child: _OnboardingFlowHarness(
      key: ValueKey('onboarding-set-password-${flow.name}'),
      location: _setPasswordLocation(flow),
      stubPaths: [args.backRoutePath],
      builder: (_) => _setPasswordShell(flow, SetPasswordScreen(args: args)),
    ),
  );
}

SetPasswordScreenArgs _setPasswordArgs(SetPasswordFlow flow) {
  return switch (flow) {
    SetPasswordFlow.create => const SetPasswordScreenArgs.create(
      mnemonic: _previewMnemonic,
    ),
    SetPasswordFlow.importWallet => const SetPasswordScreenArgs.importWallet(
      mnemonic: _previewMnemonic,
      birthdayHeight: 2500000,
    ),
    SetPasswordFlow.importKeystone =>
      const SetPasswordScreenArgs.importKeystone(
        name: 'Keystone Account',
        ufvk: _previewKeystoneUfvk,
        seedFingerprint: [1, 2, 3, 4],
        zip32Index: 0,
        birthdayHeight: 2500000,
      ),
    SetPasswordFlow.importWalletLink =>
      const SetPasswordScreenArgs.importWalletLink(
        network: 'main',
        accounts: [],
        contacts: [],
        packageId: 'preview-package',
        completionToken: 'preview-token',
        keyBytes: [],
      ),
  };
}

String _setPasswordLocation(SetPasswordFlow flow) {
  return switch (flow) {
    SetPasswordFlow.create => OnboardingStep.setPassword.routePath,
    SetPasswordFlow.importWallet => '/import/set-password',
    SetPasswordFlow.importKeystone =>
      KeystoneOnboardingStep.setPassword.routePath,
    SetPasswordFlow.importWalletLink => '/onboarding/link-desktop/set-password',
  };
}

Widget _setPasswordShell(SetPasswordFlow flow, Widget child) {
  return switch (flow) {
    SetPasswordFlow.create => OnboardingSplitViewShell(
      activeStep: OnboardingStep.setPassword,
      showPasswordStep: true,
      child: child,
    ),
    // Wallet Link renders the import pane, so it keeps the import sidebar.
    SetPasswordFlow.importWallet ||
    SetPasswordFlow.importWalletLink => ImportOnboardingShell(
      activeStep: ImportOnboardingStep.setPassword,
      showPasswordStep: true,
      child: child,
    ),
    SetPasswordFlow.importKeystone => KeystoneOnboardingShell(
      activeStep: KeystoneOnboardingStep.setPassword,
      showPasswordStep: true,
      child: child,
    ),
  };
}

// --- Unlock card body ------------------------------------------------------

/// The unlock card's content on its real auth shell. Every state is a
/// constructor prop, so no provider or router is involved.
Widget onboardingUnlockContentFixture({
  String? messageText,
  bool showForgotPassword = true,
  bool reserveForgotPasswordSpace = false,
  String descriptionText = 'Enter your password to open Vizor.',
  bool canSubmit = false,
}) {
  return _UnlockContentPreview(
    messageText: messageText,
    showForgotPassword: showForgotPassword,
    reserveForgotPasswordSpace: reserveForgotPasswordSpace,
    descriptionText: descriptionText,
    canSubmit: canSubmit,
  );
}

class _UnlockContentPreview extends StatefulWidget {
  const _UnlockContentPreview({
    required this.messageText,
    required this.showForgotPassword,
    required this.reserveForgotPasswordSpace,
    required this.descriptionText,
    required this.canSubmit,
  });

  final String? messageText;
  final bool showForgotPassword;
  final bool reserveForgotPasswordSpace;
  final String descriptionText;
  final bool canSubmit;

  @override
  State<_UnlockContentPreview> createState() => _UnlockContentPreviewState();
}

class _UnlockContentPreviewState extends State<_UnlockContentPreview> {
  final _controller = TextEditingController();

  @override
  void didUpdateWidget(_UnlockContentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFieldText();
  }

  @override
  void initState() {
    super.initState();
    _syncFieldText();
  }

  // A submittable card needs a password in the field; the knob drives both.
  void _syncFieldText() {
    final text = widget.canSubmit ? 'PreviewPassword1!' : '';
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: OnboardingAuthShell(
          card: OnboardingAuthCard(
            width: DesktopUnlockContent.cardWidth,
            height: DesktopUnlockContent.cardHeight,
            borderRadius: AppSpacing.base,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.lg,
            ),
            child: IgnorePointer(
              child: DesktopUnlockContent(
                passwordController: _controller,
                canSubmit: widget.canSubmit,
                messageText: widget.messageText,
                showForgotPassword: widget.showForgotPassword,
                reserveForgotPasswordSpace: widget.reserveForgotPasswordSpace,
                descriptionText: widget.descriptionText,
                onChanged: () {},
                onSubmit: () async {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Lost password ---------------------------------------------------------

/// Adds the Gift Card claims axis to the lost-password card. The two existing
/// `buildLostPassword*UseCase` builders keep serving the no-claims states.
Widget onboardingLostPasswordFixture({
  required int countdownSeconds,
  required int claimsInFlight,
}) {
  return ProviderScope(
    overrides: [
      appLayoutProvider.overrideWith(_OnboardingNoOpLayoutNotifier.new),
      paymentLinkClaimsInFlightProvider.overrideWith((_) => claimsInFlight),
    ],
    child: WbDesktopWindowBox(
      child: IgnorePointer(
        child: LostPasswordScreen(
          initialCountdownSeconds: countdownSeconds,
          countdownEnabled: false,
          onBack: () {},
          onReset: () async {},
        ),
      ),
    ),
  );
}

// --- Storage unavailable ---------------------------------------------------

Widget onboardingStorageUnavailableFixture({
  required AppBootstrapFailureKind failureKind,
  required String failureMessage,
}) {
  return ProviderScope(
    overrides: [
      appLayoutProvider.overrideWith(_OnboardingNoOpLayoutNotifier.new),
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState.blocked(
          failureKind: failureKind,
          failureMessage: failureMessage,
        ),
      ),
      // Retry must not run a real bootstrap from the preview.
      appBootstrapRetryProvider.overrideWithValue(() async {}),
    ],
    child: const WbDesktopWindowBox(child: StorageUnavailableScreen()),
  );
}

// --- Import: wallet birthday -----------------------------------------------

/// Chain metadata the birthday previews answer with: pinned dates and heights
/// so the calendar bounds and the height validator never move.
final _previewBirthdayFirstDate = DateTime(2016, 10, 28);
final _previewBirthdayLastDate = DateTime(2026, 9, 1);
final _previewBirthdayMetadata = ImportBirthdayMetadata(
  saplingActivationHeight: 419200,
  saplingActivationDate: _previewBirthdayFirstDate,
  tipHeight: 2800000,
  tipDate: _previewBirthdayLastDate,
);

/// The desktop import birthday step. The screen loads chain metadata through
/// the endpoint failover notifier in `initState`, so the preview overrides
/// that notifier to answer from a constant instead of reaching lightwalletd.
Widget importWalletBirthdayFixture({
  required ImportBirthdayTab tab,
  required bool metadataLoaded,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      rpcEndpointFailoverProvider.overrideWith(
        () => _PreviewBirthdayMetadataNotifier(
          metadata: metadataLoaded ? _previewBirthdayMetadata : null,
        ),
      ),
    ],
    child: _OnboardingFlowHarness(
      key: ValueKey('onboarding-import-birthday-${tab.name}-$metadataLoaded'),
      location: '/import/birthday',
      stubPaths: const ['/import', '/import/customise-account'],
      builder: (_) => ImportOnboardingShell(
        activeStep: ImportOnboardingStep.walletBirthdayHeight,
        showPasswordStep: true,
        child: ImportWalletBirthdayScreen(
          // A seeded height is what selects the block-height tab at mount.
          args: ImportBirthdayArgs(
            mnemonic: _previewMnemonic,
            initialBirthdayHeight: tab == ImportBirthdayTab.blockHeight
                ? 2500000
                : null,
          ),
        ),
      ),
    ),
  );
}

// --- Import: account discovery modal ---------------------------------------

/// How the preview's transparent-balance loader answers each row.
enum OnboardingImportDiscoveryBalance { loading, loaded, failed }

/// The 'we found more accounts' surface, driven entirely by its own props:
/// the balance loader is a preview callback, never a Rust read. Desktop is the
/// pane modal, mobile the sheet — two classes, one surface.
Widget importAccountDiscoveryFixture({
  required int accountCount,
  required OnboardingImportDiscoveryBalance balance,
  required bool allowEmptySelection,
  WbLayout layout = WbLayout.desktop,
}) {
  Future<BigInt> loadBalance(
    rust_wallet.SoftwareWalletDiscoveredAccount account,
  ) {
    return switch (balance) {
      // A future that never settles is the row's own loading state.
      OnboardingImportDiscoveryBalance.loading => Completer<BigInt>().future,
      OnboardingImportDiscoveryBalance.loaded => Future.value(
        BigInt.from((account.zip32AccountIndex + 1) * 12500000),
      ),
      OnboardingImportDiscoveryBalance.failed => Future<BigInt>.error(
        StateError('Preview transparent balance unavailable.'),
      ),
    };
  }

  if (layout == WbLayout.mobile) {
    return _onboardingMobileSheetFrame(
      MobileImportAccountDiscoverySheet(
        key: ValueKey(
          'onboarding-import-discovery-mobile-$accountCount-${balance.name}-'
          '$allowEmptySelection',
        ),
        accounts: _previewDiscoveredAccounts(accountCount),
        allowEmptySelection: allowEmptySelection,
        bip44CoinType: 133,
        loadTransparentBalance: loadBalance,
        onConfirm: (_) {},
        onCancel: () {},
      ),
    );
  }

  return _onboardingPaneModalFrame(
    ImportAccountDiscoveryModal(
      key: ValueKey(
        'onboarding-import-discovery-$accountCount-${balance.name}-'
        '$allowEmptySelection',
      ),
      accounts: _previewDiscoveredAccounts(accountCount),
      allowEmptySelection: allowEmptySelection,
      // Mainnet ZEC coin type, which is what the account path label shows.
      bip44CoinType: 133,
      loadTransparentBalance: loadBalance,
      onConfirm: (_) {},
      onCancel: () {},
    ),
  );
}

List<rust_wallet.SoftwareWalletDiscoveredAccount> _previewDiscoveredAccounts(
  int count,
) {
  return [
    for (var i = 1; i <= count; i++)
      rust_wallet.SoftwareWalletDiscoveredAccount(
        zip32AccountIndex: i,
        firstTransparentAddress: 't1PreviewDiscovered${i}AccountAddress0000',
      ),
  ];
}

// --- Import: birthday calendar ---------------------------------------------

/// Where the previewed month sits inside the selectable range, which is what
/// decides whether the previous / next nav buttons are enabled.
enum OnboardingBirthdayCalendarRange { midRange, earliest, latest }

/// The birthday calendar, either as the desktop pane overlay or as the bare
/// panel the mobile birthday sheet reuses.
Widget importBirthdayCalendarFixture({
  required bool asOverlay,
  required OnboardingBirthdayCalendarRange range,
}) {
  final selected = switch (range) {
    OnboardingBirthdayCalendarRange.midRange => DateTime(2021, 6, 15),
    OnboardingBirthdayCalendarRange.earliest => _previewBirthdayFirstDate,
    OnboardingBirthdayCalendarRange.latest => _previewBirthdayLastDate,
  };
  final key = ValueKey('onboarding-birthday-calendar-${range.name}');

  if (!asOverlay) {
    return WbFrame(
      layout: WbLayout.desktop,
      child: Center(
        child: ImportBirthdayCalendarPanel(
          key: key,
          initialMonth: selected,
          selectedDate: selected,
          firstDate: _previewBirthdayFirstDate,
          lastDate: _previewBirthdayLastDate,
          onDateSelected: (_) {},
        ),
      ),
    );
  }

  return _onboardingPaneModalFrame(
    ImportBirthdayCalendarOverlay(
      key: key,
      initialMonth: selected,
      selectedDate: selected,
      firstDate: _previewBirthdayFirstDate,
      lastDate: _previewBirthdayLastDate,
      onDismiss: () {},
      onDateSelected: (_) {},
    ),
  );
}

// --- Import: unknown birthday height modal ---------------------------------

Widget importBirthdayUnknownHeightFixture({
  WbLayout layout = WbLayout.desktop,
}) {
  if (layout == WbLayout.mobile) {
    return _onboardingMobileSheetFrame(
      const MobileImportBirthdayUnknownHeightSheet(
        onConfirm: _noop,
        onCancel: _noop,
      ),
    );
  }
  return _onboardingPaneModalFrame(
    ImportBirthdayUnknownHeightModal(onConfirm: () {}, onCancel: () {}),
  );
}

void _noop() {}

// --- Keystone: desktop pairing steps ---------------------------------------

Widget keystoneHowToConnectFixture() {
  return ProviderScope(
    child: _OnboardingFlowHarness(
      location: KeystoneOnboardingStep.howToConnect.routePath,
      stubPaths: ['/welcome', KeystoneOnboardingStep.scanQrCode.routePath],
      builder: (_) => const KeystoneOnboardingShell(
        activeStep: KeystoneOnboardingStep.howToConnect,
        showPasswordStep: true,
        child: KeystoneHowToConnectScreen(onOpenFirmware: _noop),
      ),
    ),
  );
}

/// The desktop Keystone account picker. `selectedIndex` null is the state the
/// screen reaches before the user picks a row: the confirm button is disabled.
Widget keystoneSelectAccountFixture({
  required int accountCount,
  required int? selectedIndex,
}) {
  return ProviderScope(
    overrides: [
      keystoneOnboardingProvider.overrideWith(
        () => _PreviewKeystoneOnboardingNotifier(
          accountCount: accountCount,
          selectedIndex: selectedIndex,
        ),
      ),
    ],
    child: _OnboardingFlowHarness(
      key: ValueKey(
        'onboarding-keystone-accounts-$accountCount-$selectedIndex',
      ),
      location: KeystoneOnboardingStep.selectAccount.routePath,
      stubPaths: [
        KeystoneOnboardingStep.scanQrCode.routePath,
        KeystoneOnboardingStep.walletBirthdayHeight.routePath,
      ],
      builder: (_) => const KeystoneOnboardingShell(
        activeStep: KeystoneOnboardingStep.selectAccount,
        showPasswordStep: true,
        child: KeystoneSelectAccountScreen(),
      ),
    ),
  );
}

/// The desktop Keystone birthday step. The screen loads its chain metadata in
/// `initState`, so the preview answers that load through the screen's loader
/// seam: the pinned constant, or an error for the 'Could not load wallet
/// birthday metadata.' state. Either way the preview never reaches Rust.
Widget keystoneWalletBirthdayFixture({required bool metadataLoaded}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      keystoneOnboardingProvider.overrideWith(
        () => _PreviewKeystoneOnboardingNotifier(
          accountCount: 1,
          selectedIndex: 0,
        ),
      ),
    ],
    child: _OnboardingFlowHarness(
      // The loader runs in `initState`, so the option has to remount.
      key: ValueKey('onboarding-keystone-birthday-$metadataLoaded'),
      location: KeystoneOnboardingStep.walletBirthdayHeight.routePath,
      stubPaths: [
        KeystoneOnboardingStep.selectAccount.routePath,
        KeystoneOnboardingStep.setPassword.routePath,
      ],
      builder: (_) => KeystoneOnboardingShell(
        activeStep: KeystoneOnboardingStep.walletBirthdayHeight,
        showPasswordStep: true,
        child: KeystoneWalletBirthdayScreen(
          metadataLoader: metadataLoaded
              ? () async => _previewBirthdayMetadata
              : () => Future<ImportBirthdayMetadata>.error(
                  StateError('Preview endpoint has no birthday metadata.'),
                ),
          heightEstimator: (_, _) async => 2_700_000,
        ),
      ),
    ),
  );
}

// --- Keystone: transaction progress ----------------------------------------

/// The submit-progress surfaces shared by the desktop send / swap / voting
/// flows: the standalone panel, and the same label as a blurred overlay over
/// the scanner viewport. Both are pure-prop widgets.
Widget keystoneTransactionProgressFixture({
  required bool asOverlay,
  required String label,
  required bool showCameraRow,
}) {
  if (!asOverlay) {
    return WbFrame(
      layout: WbLayout.desktop,
      child: Center(
        child: KeystoneTransactionProgressPanel(
          label: label,
          showCameraRow: showCameraRow,
          cameraLabel: 'FaceTime HD Camera',
        ),
      ),
    );
  }
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: SizedBox(
        width: KeystoneTransactionProgressPanel.width,
        height: KeystoneTransactionProgressPanel.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The overlay blurs whatever it covers; in production that is the
            // live camera, so the preview gives it something to blur.
            const _KeystoneProgressViewport(),
            KeystoneTransactionProgressOverlay(
              label: label,
              borderRadius: BorderRadius.circular(
                KeystoneTransactionProgressPanel.radius,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _KeystoneProgressViewport extends StatelessWidget {
  const _KeystoneProgressViewport();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.raised,
      child: Center(
        child: Text(
          'Scanner viewport',
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
        ),
      ),
    );
  }
}

// --- Shared preview scaffolding --------------------------------------------

Widget _onboardingCreateStep({
  required OnboardingStep step,
  required List<String> stubPaths,
  required Widget child,
}) {
  return ProviderScope(
    child: _OnboardingFlowHarness(
      location: step.routePath,
      stubPaths: stubPaths,
      builder: (_) => OnboardingSplitViewShell(
        activeStep: step,
        showPasswordStep: true,
        child: child,
      ),
    ),
  );
}

/// Minimal router so the step's buttons resolve instead of throwing.
///
/// `builder` is read through `widget.` on every rebuild, so a knob change
/// reaches the previewed screen even when this State is reused.
class _OnboardingFlowHarness extends StatefulWidget {
  const _OnboardingFlowHarness({
    required this.location,
    required this.builder,
    this.stubPaths = const [],
    this.paintWindowUnderlay = true,
    super.key,
  });

  final String location;
  final WidgetBuilder builder;
  final List<String> stubPaths;

  /// The desktop shells are acrylic, so they need the window underlay; the
  /// phone frame already paints its own background.
  final bool paintWindowUnderlay;

  @override
  State<_OnboardingFlowHarness> createState() => _OnboardingFlowHarnessState();
}

class _OnboardingFlowHarnessState extends State<_OnboardingFlowHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.location,
      routes: [
        GoRoute(
          path: widget.location,
          builder: (context, _) => widget.builder(context),
        ),
        for (final path in widget.stubPaths)
          if (path != widget.location)
            GoRoute(
              path: path,
              builder: (_, _) => _OnboardingRoutePlaceholder(label: path),
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
    if (!widget.paintWindowUnderlay) return router;
    // Mirrors the app-level opaque window underlay so the acrylic shells do
    // not show Widgetbook chrome through their transparent regions.
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: router,
      ),
    );
  }
}

class _OnboardingRoutePlaceholder extends StatelessWidget {
  const _OnboardingRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

class _OnboardingNoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: the real notifier reshapes the dev tool's window.
  }
}

class _PreviewCreateMnemonicNotifier extends CreateOnboardingMnemonicNotifier {
  _PreviewCreateMnemonicNotifier(this.mnemonic);

  final String mnemonic;

  @override
  String? build() => mnemonic;
}

class _PreviewSecretPassphraseRevealedNotifier
    extends OnboardingSecretPassphraseRevealedNotifier {
  _PreviewSecretPassphraseRevealedNotifier(this.revealed);

  final bool revealed;

  @override
  bool build() => revealed;
}

/// Desktop pane frame for the import overlays: each one is a `Positioned.fill`
/// pane modal, so it needs a Stack — and a plain pane, never a live composer.
Widget _onboardingPaneModalFrame(Widget modal) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Stack(children: [modal]),
  );
}

/// A mobile sheet body in the card `showAppMobileSheet` wraps it in, bottom
/// anchored on the phone frame — the sheet route itself needs a navigator.
Widget _onboardingMobileSheetFrame(Widget sheet) {
  return WbFrame(
    layout: WbLayout.mobile,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        MobileModalCard(child: sheet),
      ],
    ),
  );
}

/// Answers the birthday metadata load without running `action`, which is what
/// keeps the preview off lightwalletd; a null metadata is the failed state.
class _PreviewBirthdayMetadataNotifier extends RpcEndpointFailoverNotifier {
  _PreviewBirthdayMetadataNotifier({required this.metadata});

  final ImportBirthdayMetadata? metadata;

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    final metadata = this.metadata;
    if (metadata == null) {
      throw StateError('Preview endpoint has no metadata for "$operation".');
    }
    return metadata as T;
  }
}

class _PreviewKeystoneOnboardingNotifier extends KeystoneOnboardingNotifier {
  _PreviewKeystoneOnboardingNotifier({
    required this.accountCount,
    required this.selectedIndex,
  });

  final int accountCount;
  final int? selectedIndex;

  @override
  KeystoneOnboardingState build() {
    final accounts = <KeystoneAccountInfo>[
      for (var i = 0; i < accountCount; i++)
        KeystoneAccountInfo(
          name: 'Account ${i + 1}',
          ufvk: '$_previewKeystoneUfvk$i',
          index: i,
          seedFingerprint: Uint8List.fromList(const [1, 2, 3, 4]),
        ),
    ];
    final index = selectedIndex;
    // The picker compares by identity, so the selection has to be one of the
    // instances the list itself holds.
    return KeystoneOnboardingState(
      accounts: accounts,
      selectedAccount: index == null || index < 0 || index >= accounts.length
          ? null
          : accounts[index],
    );
  }
}

// --- Mobile onboarding entry / create steps --------------------------------

/// Mobile first-run entry. `showBackButton` is the screen's only prop: false
/// on `/welcome`, true when `/add-account` re-enters it from a live wallet.
Widget onboardingMobileWelcomeFixture({required bool showBackButton}) {
  return _mobileOnboardingScreen(
    location: '/welcome',
    stubPaths: const ['/onboarding/method', '/home'],
    builder: (_) => MobileWelcomeScreen(showBackButton: showBackButton),
  );
}

Widget buildOnboardingMobileMethodSelectionUseCase(BuildContext context) {
  return _mobileOnboardingScreen(
    location: '/onboarding/method',
    stubPaths: const [
      '/onboarding/intro',
      '/import',
      '/onboarding/link-desktop',
      '/onboarding/keystone',
    ],
    builder: (_) => const MobileMethodSelectionScreen(),
  );
}

Widget buildOnboardingMobileIntroZcashUseCase(BuildContext context) {
  return _mobileOnboardingScreen(
    location: '/onboarding/intro',
    stubPaths: const [
      '/onboarding/address-types',
      '/onboarding/secret-passphrase',
    ],
    builder: (_) => const MobileOnboardingIntroScreen(),
  );
}

Widget buildOnboardingMobileAddressTypesUseCase(BuildContext context) {
  return _mobileOnboardingScreen(
    location: '/onboarding/address-types',
    stubPaths: const ['/onboarding/things-to-know'],
    builder: (_) => const MobileAddressTypesScreen(),
  );
}

Widget buildOnboardingMobileThingsToKnowUseCase(BuildContext context) {
  return _mobileOnboardingScreen(
    location: '/onboarding/things-to-know',
    stubPaths: const ['/onboarding/secret-passphrase'],
    builder: (_) => const MobileThingsToKnowScreen(),
  );
}

// --- Mobile wallet link ----------------------------------------------------

Widget buildOnboardingMobileWalletLinkIntroUseCase(BuildContext context) {
  return _mobileOnboardingScreen(
    location: '/onboarding/link-desktop',
    stubPaths: const ['/onboarding/link-desktop/scan'],
    builder: (_) => const MobileWalletLinkIntroScreen(),
  );
}

/// The desktop-link scanner. `previewCameraStatus` is the screen's own preview
/// seam: anything but `active` renders the permission card with no controller,
/// and `active` gets a non-started controller, so no option opens a camera.
Widget onboardingMobileWalletLinkScanFixture({
  required AddressQrCameraStatus camera,
  required MobileWalletLinkScanError? error,
  required bool loading,
}) {
  return _mobileOnboardingScreen(
    location: '/onboarding/link-desktop/scan',
    stubPaths: const ['/onboarding/link-desktop/accounts'],
    overrides: [
      mobileWalletLinkControllerProvider.overrideWith(
        () => _PreviewWalletLinkController(
          MobileWalletLinkState(loading: loading),
        ),
      ),
    ],
    builder: (_) => MobileWalletLinkScanScreen(
      previewCameraStatus: camera,
      previewError: error,
    ),
  );
}

/// How many accounts the wallet-link preview payload carries, so the gallery's
/// selection axis can size "all selected" against the pending rows.
const onboardingMobileWalletLinkAccountCount = 3;

/// The account-selection step of the desktop link. Everything the screen reads
/// is a constant payload on an overridden controller — no relay, no crypto.
///
/// The payload keeps two contacts whenever it has accounts: with no importable
/// contact left, an all-already-imported payload collapses into the
/// "nothing to import" card instead of showing the imported section.
Widget onboardingMobileWalletLinkAccountsFixture({
  required bool hasAccounts,
  required int alreadyImportedCount,
  required int selectedCount,
  required bool submitting,
}) {
  final accounts = hasAccounts
      ? _previewWalletLinkAccounts
      : const <WalletLinkTransferAccount>[];
  final importedFrom =
      accounts.length - alreadyImportedCount.clamp(0, accounts.length);
  final alreadyImported = {
    for (final account in accounts.skip(importedFrom)) account.uuid,
  };
  final pending = [
    for (final account in accounts)
      if (!alreadyImported.contains(account.uuid)) account,
  ];
  final selected = {
    for (final account in pending.take(selectedCount)) account.uuid,
  };

  return _walletLinkSelectionScreen(
    location: '/onboarding/link-desktop/accounts',
    stubPaths: const [
      '/onboarding/link-desktop',
      '/onboarding/link-desktop/contacts',
      '/onboarding/set-passcode',
    ],
    state: MobileWalletLinkState(
      payload: _previewWalletLinkPayload(
        accounts: accounts,
        contacts: hasAccounts
            ? _previewWalletLinkContacts
            : const <AddressBookContact>[],
      ),
      packageId: 'preview-package',
      completionToken: 'preview-token',
      keyBytes: const [0, 1, 2, 3],
      selectedAccountUuids: selected,
      alreadyImportedAccountUuids: alreadyImported,
      submitting: submitting,
    ),
    builder: (_) => MobileWalletLinkSelectAccountsScreen(
      completeWalletLinkPackage:
          ({
            required packageId,
            required completionToken,
            required keyBytes,
            required importedAccountCount,
            required importedContactCount,
          }) async {},
    ),
  );
}

/// How many contacts the wallet-link preview payload carries.
const onboardingMobileWalletLinkContactCount = 2;

/// The contact-selection step of the same link, which shares the accounts
/// screen's scaffold. Every account stays selected because that is the state
/// the user arrives in — the step is only reachable from the account step.
Widget onboardingMobileWalletLinkContactsFixture({
  required bool hasContacts,
  required int alreadyImportedCount,
  required int selectedCount,
  required bool submitting,
}) {
  final contacts = hasContacts
      ? _previewWalletLinkContacts
      : const <AddressBookContact>[];
  final importedFrom =
      contacts.length - alreadyImportedCount.clamp(0, contacts.length);
  final alreadyImported = {
    for (final contact in contacts.skip(importedFrom)) contact.id,
  };
  final pending = [
    for (final contact in contacts)
      if (!alreadyImported.contains(contact.id)) contact,
  ];

  return _walletLinkSelectionScreen(
    location: '/onboarding/link-desktop/contacts',
    stubPaths: const [
      '/onboarding/link-desktop/accounts',
      '/onboarding/set-passcode',
    ],
    state: MobileWalletLinkState(
      payload: _previewWalletLinkPayload(
        accounts: _previewWalletLinkAccounts,
        contacts: contacts,
      ),
      packageId: 'preview-package',
      completionToken: 'preview-token',
      keyBytes: const [0, 1, 2, 3],
      selectedAccountUuids: {
        for (final account in _previewWalletLinkAccounts) account.uuid,
      },
      selectedContactIds: {
        for (final contact in pending.take(selectedCount)) contact.id,
      },
      alreadyImportedContactIds: alreadyImported,
      submitting: submitting,
    ),
    builder: (_) => const MobileWalletLinkSelectContactsScreen(),
  );
}

WalletLinkTransferPayload _previewWalletLinkPayload({
  required List<WalletLinkTransferAccount> accounts,
  required List<AddressBookContact> contacts,
}) {
  return WalletLinkTransferPayload(
    version: 1,
    exportedAt: null,
    network: 'main',
    activeAccountUuid: null,
    accounts: accounts,
    contacts: contacts,
  );
}

Widget _walletLinkSelectionScreen({
  required String location,
  required List<String> stubPaths,
  required MobileWalletLinkState state,
  required WidgetBuilder builder,
}) {
  return _mobileOnboardingScreen(
    location: location,
    stubPaths: stubPaths,
    overrides: [
      appSecurityProvider.overrideWith(_PreviewOnboardingSecurityNotifier.new),
      mobileWalletLinkControllerProvider.overrideWith(
        () => _PreviewWalletLinkController(state),
      ),
    ],
    builder: builder,
  );
}

const _previewWalletLinkAccounts = <WalletLinkTransferAccount>[
  WalletLinkTransferAccount(
    uuid: '11111111-1111-4111-8111-111111111111',
    name: 'Everyday',
    order: 0,
    isHardware: false,
    isSeedAnchor: true,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 2500000,
    zip32AccountIndex: 0,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: _previewMnemonic,
  ),
  WalletLinkTransferAccount(
    uuid: '22222222-2222-4222-8222-222222222222',
    name: 'Savings',
    order: 1,
    isHardware: false,
    isSeedAnchor: false,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 2510000,
    zip32AccountIndex: 1,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: _previewMnemonic,
  ),
  WalletLinkTransferAccount(
    uuid: '33333333-3333-4333-8333-333333333333',
    name: 'Donations',
    order: 2,
    isHardware: false,
    isSeedAnchor: false,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 2520000,
    zip32AccountIndex: 2,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: _previewMnemonic,
  ),
];

const _previewWalletLinkContacts = <AddressBookContact>[
  AddressBookContact(
    id: 'preview-contact-1',
    label: 'Mira',
    network: AddressBookNetwork.zcash,
    address: 'u1previewcontactmira',
    profilePictureId: '',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  AddressBookContact(
    id: 'preview-contact-2',
    label: 'Ovis',
    network: AddressBookNetwork.zcash,
    address: 'u1previewcontactovis',
    profilePictureId: '',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

/// Phone frame plus the throwaway router the mobile onboarding screens need:
/// every one of them leaves through `context.push` / `context.pop`.
Widget _mobileOnboardingScreen({
  required String location,
  required List<String> stubPaths,
  required WidgetBuilder builder,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: WbFrame(
      layout: WbLayout.mobile,
      child: _OnboardingFlowHarness(
        location: location,
        stubPaths: stubPaths,
        paintWindowUnderlay: false,
        builder: builder,
      ),
    ),
  );
}

class _PreviewWalletLinkController extends MobileWalletLinkController {
  _PreviewWalletLinkController(this.initial);

  final MobileWalletLinkState initial;

  @override
  MobileWalletLinkState build() => initial;
}

/// The wallet-link account step gates "contacts only" on a configured
/// password; the preview answers without touching secure storage.
class _PreviewOnboardingSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

// --- Onboarding shells -----------------------------------------------------

/// The create-flow desktop shell around a neutral pane, so each step's sidebar
/// art and window background are reviewable without the step screen itself.
Widget onboardingCreateShellFixture({
  required OnboardingStep step,
  required bool showPasswordStep,
  required bool passphraseRevealed,
}) {
  return _onboardingShellFrame(
    overrides: [
      onboardingSecretPassphraseRevealedProvider.overrideWith(
        () => _PreviewSecretPassphraseRevealedNotifier(passphraseRevealed),
      ),
    ],
    child: OnboardingSplitViewShell(
      activeStep: step,
      showPasswordStep: showPasswordStep,
      child: const _OnboardingShellPlaceholderPane(),
    ),
  );
}

Widget onboardingImportShellFixture({
  required ImportOnboardingStep step,
  required bool showPasswordStep,
}) {
  return _onboardingShellFrame(
    child: ImportOnboardingShell(
      activeStep: step,
      showPasswordStep: showPasswordStep,
      child: const _OnboardingShellPlaceholderPane(),
    ),
  );
}

Widget onboardingKeystoneShellFixture({
  required KeystoneOnboardingStep step,
  required bool showPasswordStep,
}) {
  return _onboardingShellFrame(
    child: KeystoneOnboardingShell(
      activeStep: step,
      showPasswordStep: showPasswordStep,
      child: const _OnboardingShellPlaceholderPane(),
    ),
  );
}

/// The shells are acrylic windows, so they paint over the same opaque window
/// underlay the app gives them.
Widget _onboardingShellFrame({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: Builder(
      builder: (context) => WbDesktopWindowBox(
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child: child,
        ),
      ),
    ),
  );
}

/// Stands in for the step screen so the case is about the shell only.
class _OnboardingShellPlaceholderPane extends StatelessWidget {
  const _OnboardingShellPlaceholderPane();

  @override
  Widget build(BuildContext context) {
    return AppDesktopPane(
      child: Center(
        child: Text(
          'Step content',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

// --- Onboarding sidebar ----------------------------------------------------

/// Which flow's step list the sidebar nav is built from.
enum OnboardingSidebarFlow { create, importWallet, keystone }

/// Where the active row sits; the flows have different step counts, so the
/// position is named instead of indexed.
enum OnboardingSidebarActive { first, middle, last }

/// The sidebar nav on its real chrome, with the illustration slot left empty
/// so the case is about the step rows.
Widget onboardingSidebarFixture({
  required OnboardingSidebarFlow flow,
  required OnboardingSidebarActive active,
  required bool tappable,
}) {
  final steps = _onboardingSidebarSteps(flow);
  final activeIndex = switch (active) {
    OnboardingSidebarActive.first => 0,
    OnboardingSidebarActive.middle => steps.length ~/ 2,
    OnboardingSidebarActive.last => steps.length - 1,
  };
  return Center(
    child: SizedBox(
      width: kAppDesktopSidebarWidth,
      height: kWbDesktopWindowHeight - 2 * kAppDesktopShellMargin,
      child: OnboardingSidebarChrome(
        illustration: const SizedBox.shrink(),
        steps: [
          for (var i = 0; i < steps.length; i++)
            OnboardingSidebarStepData(
              label: steps[i].$1,
              iconName: steps[i].$2,
              active: i == activeIndex,
              onTap: tappable ? () {} : null,
            ),
        ],
      ),
    ),
  );
}

List<(String, String)> _onboardingSidebarSteps(OnboardingSidebarFlow flow) {
  return switch (flow) {
    OnboardingSidebarFlow.create => [
      for (final step in OnboardingStep.values) (step.label, step.iconName),
    ],
    OnboardingSidebarFlow.importWallet => [
      for (final step in ImportOnboardingStep.values)
        (step.label, step.iconName),
    ],
    OnboardingSidebarFlow.keystone => [
      for (final step in KeystoneOnboardingStep.values)
        (step.label, step.iconName),
    ],
  };
}

// --- Onboarding pane chrome ------------------------------------------------

/// How the toolbar's back link is wired. The two wired forms carry the labels
/// their real callers pass, which is also what tells them apart on screen.
enum OnboardingPaneBack { route, callback, none }

/// The pane toolbar plus the overlay slot, which no registered screen case
/// fills today.
Widget onboardingPaneChromeFixture({
  required OnboardingPaneBack back,
  required bool withOverlay,
}) {
  final backTarget = switch (back) {
    OnboardingPaneBack.route => const OnboardingBackTarget.route(
      label: 'Welcome',
      routePath: '/welcome',
    ),
    OnboardingPaneBack.callback => OnboardingBackTarget.callback(
      label: ImportOnboardingStep.secretPassphrase.label,
      onTap: () {},
    ),
    OnboardingPaneBack.none => null,
  };
  return _OnboardingFlowHarness(
    location: '/onboarding/pane',
    stubPaths: const ['/welcome'],
    paintWindowUnderlay: false,
    builder: (_) => WbFrame(
      layout: WbLayout.desktop,
      child: OnboardingPaneScaffold(
        backTarget: backTarget,
        overlay: withOverlay ? const _OnboardingPaneOverlayPlaceholder() : null,
        child: const _OnboardingPaneBodyPlaceholder(),
      ),
    ),
  );
}

class _OnboardingPaneBodyPlaceholder extends StatelessWidget {
  const _OnboardingPaneBodyPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Center(
        child: Text(
          'Pane body',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _OnboardingPaneOverlayPlaceholder extends StatelessWidget {
  const _OnboardingPaneOverlayPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.neutralScrim,
      child: Center(
        child: Text(
          'Pane overlay',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.primary,
          ),
        ),
      ),
    );
  }
}

// --- Onboarding auth shell -------------------------------------------------

/// The two card boxes the auth shell is asked for today, plus a smaller one
/// that shows the shell does not depend on either.
enum OnboardingAuthCardBox { unlock, lostPassword, custom }

Widget onboardingAuthShellFixture({
  required OnboardingAuthCardBox box,
  required bool compactPadding,
}) {
  // Each option carries the box its own screen passes, padding included: the
  // two screens differ in the horizontal inset, not only in height. The
  // lost-password numbers stay literals because its content class is private.
  final (width, height, radius, sidePadding) = switch (box) {
    OnboardingAuthCardBox.unlock => (
      DesktopUnlockContent.cardWidth,
      DesktopUnlockContent.cardHeight,
      AppSpacing.base,
      AppSpacing.sm,
    ),
    OnboardingAuthCardBox.lostPassword => (
      396.0,
      520.0,
      AppSpacing.md,
      AppSpacing.md,
    ),
    OnboardingAuthCardBox.custom => (
      320.0,
      360.0,
      AppSpacing.md,
      AppSpacing.md,
    ),
  };
  return Center(
    child: WbDesktopWindowBox(
      child: OnboardingAuthShell(
        card: OnboardingAuthCard(
          width: width,
          height: height,
          borderRadius: radius,
          padding: compactPadding
              ? const EdgeInsets.all(AppSpacing.s)
              : EdgeInsets.fromLTRB(
                  sidePadding,
                  AppSpacing.xl,
                  sidePadding,
                  AppSpacing.lg,
                ),
          child: const _OnboardingAuthCardPlaceholder(),
        ),
      ),
    ),
  );
}

/// Fills the card so the padding axis is visible as a box inset.
class _OnboardingAuthCardPlaceholder extends StatelessWidget {
  const _OnboardingAuthCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Center(
        child: Text(
          'Card content',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

// --- Keystone scan help ----------------------------------------------------

/// The scan-help tooltip beside a stand-in for the request QR it anchors to.
///
/// A local `Overlay` hosts the `OverlayPortal` so the tooltip lands inside the
/// previewed frame instead of over the widgetbook chrome.
Widget keystoneScanHelpFixture({required bool visible}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => Center(
            child: KeystoneScanHelpOverlay(
              visible: visible,
              onOpenFirmware: _noop,
              child: const _KeystoneScanHelpAnchor(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _KeystoneScanHelpAnchor extends StatelessWidget {
  const _KeystoneScanHelpAnchor();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('keystone_scan_help_anchor'),
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Center(
        child: Text(
          'Request QR',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

// --- Mobile unlock: submit states ------------------------------------------

/// What the unlock attempt does once the six digits are in. Idle is the
/// existing fixture; these three are only reachable through a real submit.
enum OnboardingMobileUnlockSubmit { submitting, incorrectPasscode, openFailed }

/// Real `MobileUnlockScreen`, driven to a submit state by entering six digits
/// on the real keypad at mount. The unlock outcome comes from the overridden
/// security notifier, so nothing touches secure storage or Rust.
Widget onboardingMobileUnlockSubmitFixture({
  required BiometricKind biometric,
  required OnboardingMobileUnlockSubmit submit,
}) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewOnboardingBiometricNotifier(
          BiometricUnlockState(
            availability: BiometricAvailability(
              supported: biometric != BiometricKind.none,
              enrolled: biometric != BiometricKind.none,
              kind: biometric,
            ),
            enabled: biometric != BiometricKind.none,
          ),
        ),
      ),
      appSecurityProvider.overrideWith(
        () => _PreviewUnlockSecurityNotifier(submit),
      ),
      accountProvider.overrideWith(_PreviewOnboardingAccountNotifier.new),
      syncProvider.overrideWith(_PreviewOnboardingSyncNotifier.new),
    ],
    child: WbFrame(
      layout: WbLayout.mobile,
      child: _OnboardingFlowHarness(
        location: '/unlock',
        stubPaths: const ['/home', '/welcome'],
        paintWindowUnderlay: false,
        builder: (_) => const _MobileUnlockEnterPasscodeOnMount(
          child: MobileUnlockScreen(autoPromptBiometric: false),
        ),
      ),
    ),
  );
}

/// Enters a full passcode through the keypad's own `onDigit`, not a synthetic
/// pointer: the widgetbook chrome would intercept a hit test from the root.
class _MobileUnlockEnterPasscodeOnMount extends StatefulWidget {
  const _MobileUnlockEnterPasscodeOnMount({required this.child});

  final Widget child;

  @override
  State<_MobileUnlockEnterPasscodeOnMount> createState() =>
      _MobileUnlockEnterPasscodeOnMountState();
}

class _MobileUnlockEnterPasscodeOnMountState
    extends State<_MobileUnlockEnterPasscodeOnMount> {
  static const _digits = [1, 2, 3, 4, 5, 6];
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  void _enter() {
    if (_done || !mounted) return;
    final numpad = _findNumpad();
    if (numpad == null) {
      if (++_attempts >= _maxAttempts) {
        // Loud in debug: a silent give-up renders as the idle unlock screen,
        // which is exactly the neighbouring option.
        assert(false, 'unlock passcode driver never found PasscodeNumpad');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    for (final digit in _digits) {
      numpad.onDigit(digit);
    }
  }

  PasscodeNumpad? _findNumpad() {
    PasscodeNumpad? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is PasscodeNumpad) {
        found = widget;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PreviewUnlockSecurityNotifier extends AppSecurityNotifier {
  _PreviewUnlockSecurityNotifier(this.submit);

  final OnboardingMobileUnlockSubmit submit;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false);

  @override
  Future<bool> unlock(String password) {
    return switch (submit) {
      // Never completes: the screen's submitting branch without a timer.
      OnboardingMobileUnlockSubmit.submitting => Completer<bool>().future,
      OnboardingMobileUnlockSubmit.incorrectPasscode => Future.value(false),
      OnboardingMobileUnlockSubmit.openFailed => Future<bool>.error(
        StateError('Preview unlock failure'),
      ),
    };
  }
}

class _PreviewOnboardingAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState();

  @override
  Future<void> restoreAfterUnlock() async {}
}

class _PreviewOnboardingSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> startSyncAnyway() async {}
}

// --- Mobile biometrics: enabling -------------------------------------------

/// Real `MobileBiometricsScreen` held in its enabling state: the enable button
/// is pressed at mount and the escrow write never answers.
Widget onboardingMobileBiometricsEnablingFixture({
  required BiometricKind biometric,
}) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewOnboardingBiometricNotifier(
          BiometricUnlockState(
            availability: BiometricAvailability(
              supported: true,
              enrolled: true,
              kind: biometric,
            ),
            enabled: false,
          ),
          enableNeverCompletes: true,
        ),
      ),
      appSecurityProvider.overrideWith(_PreviewBiometricsSecurityNotifier.new),
    ],
    child: WbFrame(
      layout: WbLayout.mobile,
      child: _OnboardingFlowHarness(
        location: '/onboarding/biometrics',
        stubPaths: const ['/home'],
        paintWindowUnderlay: false,
        builder: (_) => const _MobileBiometricsEnableOnMount(
          child: MobileBiometricsScreen(),
        ),
      ),
    ),
  );
}

/// Presses the screen's own enable button once it is mounted and enabled.
class _MobileBiometricsEnableOnMount extends StatefulWidget {
  const _MobileBiometricsEnableOnMount({required this.child});

  final Widget child;

  @override
  State<_MobileBiometricsEnableOnMount> createState() =>
      _MobileBiometricsEnableOnMountState();
}

class _MobileBiometricsEnableOnMountState
    extends State<_MobileBiometricsEnableOnMount> {
  static const _enableKey = ValueKey('mobile_biometrics_enable');
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _press());
  }

  void _press() {
    if (_done || !mounted) return;
    final onPressed = _enableCallback();
    if (onPressed == null) {
      if (++_attempts >= _maxAttempts) {
        // Loud in debug: giving up leaves the button enabled, which reads as
        // the 'Offered' option rather than as a broken driver.
        assert(false, 'biometrics driver never found an enabled button');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _press());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    onPressed();
  }

  VoidCallback? _enableCallback() {
    AppButton? button;
    void visit(Element element) {
      if (button != null) return;
      final widget = element.widget;
      if (widget is AppButton && widget.key == _enableKey) {
        button = widget;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return button?.onPressed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Answers the escrow's passcode read without an unlocked secure session,
/// which is what the real store requires.
class _PreviewBiometricsSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  String requireSessionPasswordForNativeSecretUse() => '123456';
}

class _PreviewOnboardingBiometricNotifier extends BiometricUnlockNotifier {
  _PreviewOnboardingBiometricNotifier(
    this.initial, {
    this.enableNeverCompletes = false,
  });

  final BiometricUnlockState initial;
  final bool enableNeverCompletes;

  @override
  Future<BiometricUnlockState> build() async => initial;

  @override
  Future<void> enable(String passcode) {
    if (enableNeverCompletes) return Completer<void>().future;
    return Future.value();
  }

  @override
  Future<String?> readPasscode({required String reason}) async => null;
}

// --- Onboarding components -------------------------------------------------

/// Word counts BIP-39 allows; the wallet writes 24 and reads any of them.
enum OnboardingSeedCardWords {
  twelve,
  fifteen,
  eighteen,
  twentyOne,
  twentyFour,
}

/// The card header's copy affordance: absent, offered, or just used.
enum OnboardingSeedCardCopy { none, copy, copied }

Widget onboardingSeedCardFixture({
  required OnboardingSeedCardWords words,
  required bool obscured,
  required OnboardingSeedCardCopy copy,
  required bool onboardingRowGap,
}) {
  final count = switch (words) {
    OnboardingSeedCardWords.twelve => 12,
    OnboardingSeedCardWords.fifteen => 15,
    OnboardingSeedCardWords.eighteen => 18,
    OnboardingSeedCardWords.twentyOne => 21,
    OnboardingSeedCardWords.twentyFour => 24,
  };
  return _onboardingComponentFrame(
    child: SeedCard(
      words: _previewMnemonic.split(' ').take(count).toList(growable: false),
      obscured: obscured,
      onCopy: copy == OnboardingSeedCardCopy.none ? null : () {},
      copied: copy == OnboardingSeedCardCopy.copied,
      // The mobile passphrase screen spreads the grid to the Figma 44px pitch.
      rowGap: onboardingRowGap ? 19 : AppSpacing.s,
    ),
  );
}

/// The passcode prompt (dots plus the message line under them).
Widget onboardingPasscodeFieldFixture({
  required int filled,
  required String? error,
}) {
  return _onboardingComponentFrame(
    child: SizedBox(
      height: kPasscodePromptDigitsHeight,
      child: PasscodePromptField(
        length: kMobilePasscodeLength,
        filled: filled,
        error: error,
        minGap: 0,
      ),
    ),
  );
}

/// Which biometric action sits under the keypad, if any.
enum OnboardingPasscodeBiometric { none, faceId, touchId, fingerprint }

/// The keypad block as the unlock screen composes it: the numpad with its two
/// auxiliary slots, and the biometric retry pill below.
Widget onboardingPasscodeKeypadFixture({
  required bool canDelete,
  required bool showHelp,
  required bool enabled,
  required OnboardingPasscodeBiometric biometric,
}) {
  final kind = switch (biometric) {
    OnboardingPasscodeBiometric.none => BiometricKind.none,
    OnboardingPasscodeBiometric.faceId => BiometricKind.face,
    OnboardingPasscodeBiometric.touchId => BiometricKind.touchId,
    OnboardingPasscodeBiometric.fingerprint => BiometricKind.fingerprint,
  };
  return _onboardingComponentFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PasscodeNumpad(
          onDigit: (_) {},
          onBackspace: () {},
          canDelete: canDelete,
          onHelp: showHelp ? () {} : null,
          enabled: enabled,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 36,
          child: biometric == OnboardingPasscodeBiometric.none
              ? const SizedBox.shrink()
              : PasscodeBiometricButton(
                  label: kind.signInLabel,
                  icon: Center(
                    child: BiometricIcon(
                      kind: kind,
                      size: 13.5,
                      fingerprintSize: 16,
                    ),
                  ),
                  // The screen nulls this while a submit is in flight, which
                  // is the same axis as the keypad's `enabled`.
                  onPressed: enabled ? () {} : null,
                ),
        ),
      ],
    ),
  );
}

/// Which flow's progress track the step scaffold shows.
enum OnboardingStepScaffoldProgress { create, importWallet, walletLink }

/// Which optional slots the step fills.
enum OnboardingStepScaffoldSlots {
  titleOnly,
  subtitle,
  aboveTitleHero,
  bottomAction,
}

Widget onboardingStepScaffoldFixture({
  required OnboardingStepScaffoldProgress progress,
  required OnboardingStepScaffoldSlots slots,
  required bool showBackButton,
  required bool scrollable,
}) {
  final progressValue = switch (progress) {
    OnboardingStepScaffoldProgress.create => mobileCreateProgress(3),
    OnboardingStepScaffoldProgress.importWallet => mobileImportProgress(1),
    OnboardingStepScaffoldProgress.walletLink => 0.2,
  };
  return WbFrame(
    layout: WbLayout.mobile,
    child: MobileOnboardingStepScaffold(
      progress: progressValue,
      showBackButton: showBackButton,
      scrollable: scrollable,
      onBack: () {},
      title: 'Step title',
      subtitle: slots == OnboardingStepScaffoldSlots.subtitle
          ? 'Step subtitle, on the two lines the Figma steps wrap to.'
          : null,
      aboveTitle: slots == OnboardingStepScaffoldSlots.aboveTitleHero
          ? const _OnboardingStepHeroPlaceholder()
          : null,
      bottomArea: slots == OnboardingStepScaffoldSlots.bottomAction
          ? AppButton(
              expand: true,
              onPressed: () {},
              child: const Text('Continue'),
            )
          : null,
      child: const _OnboardingStepBodyPlaceholder(),
    ),
  );
}

class _OnboardingStepHeroPlaceholder extends StatelessWidget {
  const _OnboardingStepHeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Center(
        child: Text(
          'Hero slot',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _OnboardingStepBodyPlaceholder extends StatelessWidget {
  const _OnboardingStepBodyPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Center(
        child: Text(
          'Step body',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

/// Phone frame for the component-level onboarding cases: the widgets below
/// only ever render inside a mobile screen's horizontal padding.
Widget _onboardingComponentFrame({required Widget child}) {
  return WbFrame(
    layout: WbLayout.mobile,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Center(child: child),
    ),
  );
}
