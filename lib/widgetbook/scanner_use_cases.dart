// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    show MobileScannerCameraInfo, MobileScannerException;

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/storage/app_secure_store.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/keystone/widgets/keystone_qr_scanner_card.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/migration/screens/ironwood_migration_flow_screen.dart'
    show
        MobileIronwoodMigrationKeystoneCombinedSignScreen,
        MobileIronwoodMigrationKeystoneImmediateSignScreen;
import '../src/features/migration/services/ironwood_migration_service.dart';
import '../src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import '../src/features/onboarding/keystone/keystone_scan_qr_screen.dart';
import '../src/features/send/screens/keystone_send_scan_screen.dart';
import '../src/features/voting/screens/keystone_voting_scan_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/services/qr_scanner.dart';
import 'support/wb_fake_scanner_platform.dart';
import 'support/wb_layout.dart';

// Every surface here owns a live `MobileScannerController`; the camera and the
// UR decoder come from the fakes in `support/wb_fake_scanner_platform.dart`,
// which `lib/widgetbook.dart` installs before `runApp` and tests install
// themselves.

// --- Shared scanner axes ---------------------------------------------------

/// What the camera does when a scanner mounts.
enum ScannerCameraCase { live, requesting, denied, unavailable }

/// How many cameras the host reports. Desktop only offers the picker with
/// more than one, and the footer label names the default.
enum ScannerCameraListCase { noneFound, one, two }

/// Which overlay the Keystone card has open over its feed.
enum ScannerCardOverlayCase { none, cameraPicker, troubleScanning }

/// How far the card's own scan session has got.
enum ScannerCardScanCase { waiting, readingCode, decoding }

/// What a Keystone scan screen has read, which is the only thing that puts
/// its error line on screen.
enum ScannerScreenScanCase { waiting, readingCode, wrongCode, unreadable }

/// Which response the send scan expects — the two [KeystoneSendScanArgs]
/// shapes `send_review_screen.dart` pushes. It picks the UR type the screen
/// accepts and the line it prints when another one is shown.
enum ScannerSendExpectedCase { signedTransaction, signatureResult }

/// Box the bare scanner view is given; the scan window is derived from it.
enum ScannerViewFrameCase { square, portrait }

/// Whether the animated UR view draws the plugin's error widget or a
/// caller-supplied one.
enum ScannerViewErrorCase { pluginDefault, callerBuilder }

/// Which migration signing screen hosts the scanner.
enum ScannerMigrationStepCase { combined, immediate }

const String _kAccountsUrType = 'zcash-accounts';
const String _kPcztUrType = 'zcash-pczt';
const String _kBatchResultUrType = 'zcash-batch-sig-result';

/// A UR part that is 2 of 5, so the decoder reports 40%.
String _partialUrPart(String urType) => 'ur:$urType/2-5/aabbcc';

/// A single-part UR that completes immediately.
String _completeUrPart(String urType) => 'ur:$urType/1-1/aabbcc';

/// A UR of a type no scanner here expects, so the decoder raises.
const String _wrongUrPart = 'ur:zcash-address/1-2/aabbcc';

/// A UR of the expected type whose fragment the decoder cannot read, which is
/// a session reset rather than a wrong code.
String _corruptUrPart(String urType) => 'ur:$urType/1-1/';

/// Cameras the host reports for [cameras].
List<MobileScannerCameraInfo> _fakeCameras(ScannerCameraListCase cameras) {
  return switch (cameras) {
    ScannerCameraListCase.noneFound => const [],
    ScannerCameraListCase.one => const [kWbFakeBackCamera],
    ScannerCameraListCase.two => const [
      kWbFakeBuiltInCamera,
      kWbFakeExternalCamera,
    ],
  };
}

/// The footer label the card prints for [cameras], which is the control that
/// opens the picker; null when the picker cannot open, because the card
/// ignores the tap with fewer than two cameras.
String? _cameraPickerLabel(ScannerCameraListCase cameras) {
  final list = _fakeCameras(cameras);
  if (list.length < 2) return null;
  final selected = list.firstWhere(
    (camera) => camera.isDefault,
    orElse: () => list.first,
  );
  return selected.isDefault ? '${selected.name} (Default)' : selected.name;
}

/// Points the shared fake camera at [camera] / [cameras] before the scanner
/// under test mounts.
void _configureFakeCamera(
  ScannerCameraCase camera,
  ScannerCameraListCase cameras,
) {
  WbFakeMobileScannerPlatform.ensureInstalled().configure(
    startResult: switch (camera) {
      ScannerCameraCase.live => WbFakeScannerStart.running,
      ScannerCameraCase.requesting => WbFakeScannerStart.requesting,
      ScannerCameraCase.denied => WbFakeScannerStart.permissionDenied,
      ScannerCameraCase.unavailable => WbFakeScannerStart.unavailable,
    },
    cameras: _fakeCameras(cameras),
    errorMessage: 'This camera is already in use by another app.',
  );
}

/// Remount key for a scanner subtree.
///
/// Every scanner here seeds its state at mount — the fake is configured before
/// the controller starts, the router captures its builder in `initState`, and
/// the mount driver pushes and taps from a post-frame callback. A knob change
/// rebuilds the use case at the same widget position, so without a
/// knob-derived key the element is reused and the previous option stays on
/// screen.
Key _scannerRemountKey(List<Object?> axes) =>
    ValueKey('wb_scanner_${axes.map((axis) => '$axis').join('_')}');

/// The UR part a screen-level scan case pushes, or null for 'nothing scanned'.
String? _screenScanPart(ScannerScreenScanCase scan, String expectedUrType) {
  return switch (scan) {
    ScannerScreenScanCase.waiting => null,
    ScannerScreenScanCase.readingCode => _partialUrPart(expectedUrType),
    ScannerScreenScanCase.wrongCode => _wrongUrPart,
    ScannerScreenScanCase.unreadable => _completeUrPart(expectedUrType),
  };
}

// --- Keystone scanner card -------------------------------------------------

/// The real [KeystoneQrScannerCard] — the camera surface every Keystone scan
/// screen embeds — on the fake camera.
///
/// The overlays and the scan progress are reached the way the app reaches
/// them: a tap on the card's own control, and a UR part arriving from the
/// camera stream.
Widget keystoneScannerCardFixture({
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerCameraListCase cameras = ScannerCameraListCase.two,
  ScannerCardOverlayCase overlay = ScannerCardOverlayCase.none,
  ScannerCardScanCase scan = ScannerCardScanCase.waiting,
  bool showError = false,
}) {
  _configureFakeCamera(camera, cameras);
  return _ScannerCardCenter(
    child: _ScannerMountDriver(
      key: _scannerRemountKey([camera, cameras, overlay, scan, showError]),
      // The camera-control row is labelled with the started camera's name, so
      // tapping that label is what opens the picker. It is only on screen with
      // a live feed and more than one camera; other combinations have no
      // picker to open.
      tapText: switch (overlay) {
        ScannerCardOverlayCase.none => null,
        ScannerCardOverlayCase.cameraPicker =>
          camera == ScannerCameraCase.live ? _cameraPickerLabel(cameras) : null,
        ScannerCardOverlayCase.troubleScanning => 'Trouble scanning?',
      },
      urPart: switch (scan) {
        ScannerCardScanCase.readingCode => _partialUrPart(_kAccountsUrType),
        _ => null,
      },
      child: KeystoneQrScannerCard(
        expectedUrType: _kAccountsUrType,
        decoding: scan == ScannerCardScanCase.decoding,
        error: showError ? 'Keep the QR code steady and fully visible.' : null,
        onProgress: _ignoreProgress,
        onDecodeError: _ignoreDecodeError,
        onComplete: _ignoreScanResult,
        openCameraSettings: _handlePreviewCameraSettings,
        decodingLabel: 'Reading accounts...',
        unavailableMessage:
            'Keystone import uses camera QR scanning only. Connect a camera '
            'and try again.',
      ),
    ),
  );
}

/// Handles the settings action without leaving Widgetbook or opening a native
/// system surface. Returning true keeps the production widget on its normal
/// successful-action path.
Future<bool> _handlePreviewCameraSettings() async => true;

class _ScannerCardCenter extends StatelessWidget {
  const _ScannerCardCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(child: SingleChildScrollView(child: child)),
    );
  }
}

// --- Keystone scan screens -------------------------------------------------

/// The desktop onboarding step ([KeystoneScanQrScreen]) in its onboarding
/// shell.
Widget keystoneOnboardingScanScreenFixture({
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerScreenScanCase scan = ScannerScreenScanCase.waiting,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.two);
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: ProviderScope(
      child: _ScannerRouteHarness(
        key: _scannerRemountKey([camera, scan]),
        location: KeystoneOnboardingStep.scanQrCode.routePath,
        stubPaths: [
          KeystoneOnboardingStep.howToConnect.routePath,
          KeystoneOnboardingStep.selectAccount.routePath,
        ],
        builder: (_) => _ScannerMountDriver(
          urPart: _screenScanPart(scan, _kAccountsUrType),
          child: const KeystoneOnboardingShell(
            activeStep: KeystoneOnboardingStep.scanQrCode,
            showPasswordStep: true,
            child: KeystoneScanQrScreen(),
          ),
        ),
      ),
    ),
  );
}

/// The desktop signed-transaction scan ([KeystoneSendScanScreen]).
///
/// Desktop-lane only: the embedded [KeystoneQrScannerCard] branches on the
/// compile-time `kAppFormFactor`, so under the mobile token set this screen
/// overflows rather than approximating the mobile layout.
Widget keystoneSendScanScreenFixture({
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerScreenScanCase scan = ScannerScreenScanCase.waiting,
  ScannerSendExpectedCase expected = ScannerSendExpectedCase.signedTransaction,
  bool suppressSidebarSelection = false,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.two);
  final args = switch (expected) {
    ScannerSendExpectedCase.signedTransaction => KeystoneSendScanArgs(
      suppressSidebarSelection: suppressSidebarSelection,
    ),
    ScannerSendExpectedCase.signatureResult => KeystoneSendScanArgs.batch(
      suppressSidebarSelection: suppressSidebarSelection,
    ),
  };
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _scannerShellScope(
      child: _ScannerRouteHarness(
        key: _scannerRemountKey([camera, scan, expected]),
        location: '/send/keystone/scan',
        stubPaths: _kScannerSidebarRoutes,
        builder: (_) => _ScannerMountDriver(
          urPart: _sendScanPart(scan, args),
          child: KeystoneSendScanScreen(args: args),
        ),
      ),
    ),
  );
}

/// Only the signed-transaction response is CBOR-decoded, so a complete UR is
/// what fails to decode there. The signature result is handed back raw, so a
/// complete UR would pop the route instead; its undecodable QR is one whose
/// fragment the UR decoder cannot read.
String? _sendScanPart(ScannerScreenScanCase scan, KeystoneSendScanArgs args) {
  if (scan == ScannerScreenScanCase.unreadable && !args.decodePcztResponse) {
    return _corruptUrPart(args.expectedUrType);
  }
  return _screenScanPart(scan, args.expectedUrType);
}

/// The desktop signed-voting scan ([KeystoneVotingScanScreen]).
///
/// Desktop-lane only, for the same `kAppFormFactor` reason as the send scan.
Widget keystoneVotingScanScreenFixture({
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerScreenScanCase scan = ScannerScreenScanCase.waiting,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.two);
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _scannerShellScope(
      child: _ScannerRouteHarness(
        key: _scannerRemountKey([camera, scan]),
        location: '/voting/keystone/scan',
        stubPaths: _kScannerSidebarRoutes,
        builder: (_) => _ScannerMountDriver(
          // A completed voting scan pops the route, so the completing part is
          // not offered here; the two partial outcomes are.
          urPart: _screenScanPart(scan, _kBatchResultUrType),
          child: const KeystoneVotingScanScreen(),
        ),
      ),
    ),
  );
}

// --- Ironwood migration Keystone scans --------------------------------------

/// The Ironwood migration signing screens on their scanning stage, mobile only.
///
/// `previewStartScanning` is the production preview seam that opens the screen
/// on the signed-result scanner instead of the request QR, so no Rust prepare
/// runs. Only the mobile shell reaches the real scanner from a preview — the
/// desktop branch swaps it for a static placeholder
/// (`keystone_signing.dart:1813`).
///
/// Mobile-lane only: under the desktop token set the real card falls back to
/// its 396x310 desktop geometry, which overflows the phone frame by 96px, so
/// the desktop lane would preview a broken layout rather than an
/// approximation.
Widget migrationKeystoneScanFixture({
  ScannerMigrationStepCase step = ScannerMigrationStepCase.combined,
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerScreenScanCase scan = ScannerScreenScanCase.waiting,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.two);
  final screen = switch (step) {
    ScannerMigrationStepCase.combined =>
      MobileIronwoodMigrationKeystoneCombinedSignScreen(
        approvedSchedule: const [],
        previewRequest: _migrationScanRequest(),
        previewUrParts: _kMigrationUrParts,
        previewStartScanning: true,
      ),
    ScannerMigrationStepCase.immediate =>
      MobileIronwoodMigrationKeystoneImmediateSignScreen(
        approvedPlan: _migrationScanImmediatePlan(),
        previewRequest: _migrationScanRequest(),
        previewUrParts: _kMigrationUrParts,
        previewStartScanning: true,
      ),
  };

  return WbLaneOnly(
    layout: WbLayout.mobile,
    child: _scannerShellScope(
      overrides: [
        privacyModeProvider.overrideWith(_ScannerPrivacyModeNotifier.new),
        // The screen reads the service on mount; with a preview request it never
        // calls it, and these stubs keep it away from storage and Rust anyway.
        ironwoodMigrationServiceProvider.overrideWithValue(
          IronwoodMigrationService(
            getWalletDbPath: _pendingMigrationWalletDbPath,
            getStatus: _unusedMigrationStatus,
            getPrivatePlan: _unusedMigrationPrivatePlan,
            secureStore: AppSecureStore.instance,
          ),
        ),
      ],
      child: _ScannerRouteHarness(
        key: _scannerRemountKey([step, camera, scan]),
        location: _migrationScanRoute(step),
        stubPaths: const [
          '/home',
          '/migration/options',
          '/migration/immediate/review',
          '/migration/private/review',
          '/migration/private/status',
        ],
        paintWindowUnderlay: false,
        builder: (_) => _ScannerMountDriver(
          urPart: _screenScanPart(scan, _kBatchResultUrType),
          child: screen,
        ),
        frameLayout: WbLayout.mobile,
      ),
    ),
  );
}

String _migrationScanRoute(ScannerMigrationStepCase step) {
  return switch (step) {
    ScannerMigrationStepCase.combined => '/migration/private/keystone/sign',
    ScannerMigrationStepCase.immediate => '/migration/immediate/keystone/sign',
  };
}

const _kMigrationUrParts = <String>[
  'ur:zcash-sign-request/preview-migration-round-1',
];

rust_sync.KeystoneMigrationSigningRequest _migrationScanRequest() {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'preview-scanner-migration',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'preview-scanner-migration-1',
        redactedPczt: Uint8List.fromList(const [1, 2, 3]),
        expectedSignatureCount: 0,
      ),
    ],
    signingBatchLimit: 1,
  );
}

rust_sync.OrchardMigrationImmediatePlan _migrationScanImmediatePlan() {
  return rust_sync.OrchardMigrationImmediatePlan(
    totalInputZatoshi: BigInt.from(14223060000),
    feeZatoshi: BigInt.from(60000),
    migratedZatoshi: BigInt.from(14223000000),
    inputNoteCount: 12,
  );
}

Future<String> _pendingMigrationWalletDbPath() => Completer<String>().future;

Future<rust_sync.MigrationStatus> _unusedMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) => Future<rust_sync.MigrationStatus>.error(
  StateError('Preview migration status is not available.'),
);

Future<rust_sync.OrchardMigrationPrivatePlan?> _unusedMigrationPrivatePlan({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async => null;

// --- Bare scanner views ----------------------------------------------------

/// [PlainQrScannerView] — the single-frame scanner behind every address and
/// payment-URI scan — in the two box shapes its scan window is derived from.
Widget plainQrScannerViewFixture({
  ScannerCameraCase camera = ScannerCameraCase.live,
  ScannerViewFrameCase frame = ScannerViewFrameCase.square,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.one);
  return _ScannerViewFrame(
    key: _scannerRemountKey([camera, frame]),
    frame: frame,
    child: PlainQrScannerView(onComplete: _ignoreScannedText),
  );
}

/// [AnimatedUrScannerView] — the multi-part UR scanner — with the plugin's own
/// error widget or the `errorBuilder` a caller supplies.
Widget animatedUrScannerViewFixture({
  ScannerCameraCase camera = ScannerCameraCase.denied,
  ScannerViewErrorCase error = ScannerViewErrorCase.pluginDefault,
}) {
  _configureFakeCamera(camera, ScannerCameraListCase.one);
  return _ScannerViewFrame(
    key: _scannerRemountKey([camera, error]),
    frame: ScannerViewFrameCase.square,
    child: AnimatedUrScannerView(
      expectedUrType: _kPcztUrType,
      onComplete: _ignoreScanResult,
      onProgress: _ignoreProgress,
      onDecodeError: _ignoreDecodeError,
      errorBuilder: error == ScannerViewErrorCase.callerBuilder
          ? _scannerViewErrorBuilder
          : null,
    ),
  );
}

Widget _scannerViewErrorBuilder(
  BuildContext context,
  MobileScannerException error,
) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.raised,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'Camera error: ${error.errorCode.name}',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.destructive,
          ),
        ),
      ),
    ),
  );
}

class _ScannerViewFrame extends StatelessWidget {
  const _ScannerViewFrame({
    required this.frame,
    required this.child,
    super.key,
  });

  final ScannerViewFrameCase frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = switch (frame) {
      ScannerViewFrameCase.square => const Size.square(360),
      ScannerViewFrameCase.portrait => const Size(280, 520),
    };
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: SizedBox.fromSize(
          size: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.large),
            child: child,
          ),
        ),
      ),
    );
  }
}

// --- Harness ---------------------------------------------------------------

/// Routes the desktop sidebar and the scan screens' back links reach.
const _kScannerSidebarRoutes = <String>[
  '/home',
  '/send',
  '/receive',
  '/activity',
  '/accounts',
  '/settings',
  '/swap',
  '/pay',
  '/voting',
];

/// The provider floor a scanner screen inside `AppDesktopShell` needs: the
/// real `AppMainSidebar` otherwise reaches storage, lightwalletd and the
/// migration coordinator, and `AppLayoutNotifier.setMode` would reshape the
/// dev tool's window.
Widget _scannerShellScope({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appLayoutProvider.overrideWith(_ScannerNoOpLayoutNotifier.new),
      appBootstrapProvider.overrideWithValue(_scannerBootstrap),
      accountProvider.overrideWith(
        () => _ScannerAccountNotifier(_scannerAccountState),
      ),
      syncProvider.overrideWith(
        () => _ScannerSyncNotifier(_scannerAccountState.activeAccountUuid),
      ),
      networkPrivacyProvider.overrideWith(_ScannerNetworkPrivacyNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodPostMigrationStateProvider.overrideWith(
        (ref) => const IronwoodPostMigrationState.inactive(),
      ),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _ScannerMigrationCoordinator.new,
      ),
      ...overrides,
    ],
    child: child,
  );
}

final _scannerAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: 'wb-scanner-account',
      name: 'Keystone Vault',
      order: 0,
      isHardware: true,
      profilePictureId: 'pfp-02',
    ),
  ],
  activeAccountUuid: 'wb-scanner-account',
  activeAddress: 'u1widgetbookscanneraddress',
);

final _scannerBootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _scannerAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _ScannerAccountNotifier extends AccountNotifier {
  _ScannerAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _ScannerSyncNotifier extends SyncNotifier {
  _ScannerSyncNotifier(this.activeAccountUuid);

  final String? activeAccountUuid;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: activeAccountUuid,
    hasAccountScopedData: activeAccountUuid != null,
    isSyncComplete: true,
    percentage: 1,
    totalBalance: BigInt.from(14223000000),
    orchardBalance: BigInt.from(14223000000),
    spendableBalance: BigInt.from(14223000000),
  );
}

class _ScannerNoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Both scan screens call this on mount; the real one resizes the native
    // window, which belongs to the dev tool here.
  }
}

class _ScannerNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

class _ScannerPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _ScannerMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

/// A router the scan screens can resolve their back link and sidebar against.
class _ScannerRouteHarness extends StatefulWidget {
  const _ScannerRouteHarness({
    required this.location,
    required this.builder,
    this.stubPaths = const [],
    this.paintWindowUnderlay = true,
    this.frameLayout,
    super.key,
  });

  final String location;
  final WidgetBuilder builder;
  final List<String> stubPaths;

  /// The desktop shells are acrylic, so they need the opaque window underlay
  /// the app paints behind them.
  final bool paintWindowUnderlay;

  /// Wraps the router in a [WbFrame] of this layout; null leaves the screen
  /// filling the canvas the way the desktop shells expect.
  final WbLayout? frameLayout;

  @override
  State<_ScannerRouteHarness> createState() => _ScannerRouteHarnessState();
}

class _ScannerRouteHarnessState extends State<_ScannerRouteHarness> {
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
              builder: (_, _) => _ScannerRoutePlaceholder(label: path),
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
    Widget content = Router.withConfig(config: _router);
    if (widget.paintWindowUnderlay) {
      content = ColoredBox(
        color: context.colors.macosUtility.window,
        child: content,
      );
    }
    final frameLayout = widget.frameLayout;
    if (frameLayout == null) return WbDesktopWindowBox(child: content);
    return WbFrame(layout: frameLayout, child: content);
  }
}

class _ScannerRoutePlaceholder extends StatelessWidget {
  const _ScannerRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

/// Drives a scanner surface to a state it only reaches from the camera: pushes
/// one UR part into the fake's barcode stream, and taps one of the card's own
/// controls by its label.
///
/// Both steps retry per frame until their target exists, then run exactly
/// once — the scanner needs a frame to subscribe, and the camera-control row
/// only appears once the feed is live.
class _ScannerMountDriver extends StatefulWidget {
  const _ScannerMountDriver({
    required this.child,
    this.urPart,
    this.tapText,
    super.key,
  });

  final Widget child;
  final String? urPart;
  final String? tapText;

  @override
  State<_ScannerMountDriver> createState() => _ScannerMountDriverState();
}

class _ScannerMountDriverState extends State<_ScannerMountDriver> {
  static const _maxAttempts = 12;

  var _pushAttempts = 0;
  var _tapAttempts = 0;
  var _pushed = false;
  var _tapped = false;

  @override
  void initState() {
    super.initState();
    if (widget.urPart != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _push());
    }
    if (widget.tapText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tap());
    }
  }

  void _push() {
    if (_pushed || !mounted) return;
    final fake = WbFakeMobileScannerPlatform.current;
    // `hasListener` is the scanner's own subscription: pushing before it lands
    // would drop the part on the floor.
    if (fake == null || !fake.barcodeController.hasListener) {
      if (++_pushAttempts >= _maxAttempts) {
        // Debug-only, so a fixture whose scan state silently never arrives
        // fails in the widgetbook and in tests instead of previewing the
        // un-driven screen.
        assert(false, 'No scanner subscribed to the fake camera.');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _push());
      // A post-frame callback only runs if another frame is produced, and an
      // idle scanner state animates nothing.
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _pushed = true;
    fake.pushBarcode(widget.urPart!);
  }

  void _tap() {
    if (_tapped || !mounted) return;
    final onTap = _tapCallbackFor(widget.tapText!);
    if (onTap == null) {
      if (++_tapAttempts >= _maxAttempts) {
        assert(false, 'Scanner control "${widget.tapText}" never appeared.');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _tap());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _tapped = true;
    onTap();
  }

  /// The control's own `onTap`, not a synthetic pointer: hit-testing from the
  /// root would be intercepted by whatever the widgetbook chrome overlays.
  VoidCallback? _tapCallbackFor(String text) {
    Element? label;
    void findLabel(Element element) {
      if (label != null) return;
      final widget = element.widget;
      if (widget is Text && widget.data == text) {
        label = element;
        return;
      }
      element.visitChildren(findLabel);
    }

    context.visitChildElements(findLabel);
    if (label == null) return null;

    VoidCallback? onTap;
    label!.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is GestureDetector && widget.onTap != null) {
        onTap = widget.onTap;
        return false;
      }
      return true;
    });
    return onTap;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void _ignoreProgress(int progress) {}

void _ignoreDecodeError(Object error) {}

void _ignoreScanResult(ScanResult result) {}

void _ignoreScannedText(String value) {}
