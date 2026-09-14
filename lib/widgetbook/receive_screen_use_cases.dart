// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

/// Fixtures for the real Receive screen and the live mobile request sheet.
///
/// `receive_use_cases.dart` keeps the desktop mock and the mobile screen it
/// already shipped; this file drives the production `ReceiveScreen` and
/// `ReceiveRequestSheet` through provider overrides instead.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_toast.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/receive/screens/receive_screen.dart';
import '../src/features/receive/services/request_qr_export.dart';
import '../src/features/receive/widgets/mobile/receive_request_sheet.dart';
import '../src/features/receive/widgets/receive_address_widgets.dart';
import '../src/features/receive/widgets/request/request_amount_sheet.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import 'support/wb_layout.dart';
import 'support/wb_sidebar.dart';

/// The addresses the other Receive fixtures preview, so every Receive surface
/// describes the same wallet.
const kReceiveScreenShieldedAddress =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const kReceiveScreenTransparentAddress = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

/// 0.5 ZEC is $35.00, which is the conversion the request fixtures show.
const kReceiveScreenZecUsdPrice = 70.0;

/// Window height the desktop screen is previewed in.
///
/// Taller than the usual 720 fixture window: the pane puts the address-load
/// error under the 656pt content block, and at 720 that line sits below the
/// fold where a reviewer cannot see it.
const kReceiveScreenWindowHeight = 860.0;

/// How the address service answers the screen.
enum ReceiveScreenAddressOutcome {
  /// The address resolves.
  resolved,

  /// The load never completes, so the QR slot keeps its spinner.
  pending,

  /// The account has no address to show; copy and request are disabled.
  empty,

  /// The load fails, which is what puts the error text under the QR.
  failed,
}

// --- Desktop screen --------------------------------------------------------

/// The production [ReceiveScreen] on a desktop window.
Widget receiveDesktopScreenFixture({
  ReceiveAddressType pool = ReceiveAddressType.shielded,
  ReceiveScreenAddressOutcome outcome = ReceiveScreenAddressOutcome.resolved,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_receiveBootstrap),
      wbSidebarActions,
      // `setMode(large)` would reshape the dev tool's own window.
      appLayoutProvider.overrideWith(_ReceiveNoOpLayoutNotifier.new),
      receiveAddressServiceProvider.overrideWithValue(
        _ReceiveScreenAddressService(pool: pool, outcome: outcome),
      ),
      // Never open the host save panel or write a fixture QR to disk.
      requestQrSaveLocationPickerProvider.overrideWithValue(
        ({required suggestedName}) async => null,
      ),
      syncProvider.overrideWith(_ReceiveScreenSyncNotifier.new),
      zecLiveUsdUnitPriceProvider.overrideWithValue(kReceiveScreenZecUsdPrice),
      swapFeatureEnabledProvider.overrideWithValue(true),
      // The sidebar watches all three; the real ones read the wallet DB and
      // the coordinator additionally reads `DateTime.now()`.
      ironwoodPostMigrationStateProvider.overrideWith(
        (ref) async => const IronwoodPostMigrationState.inactive(),
      ),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _ReceiveScreenMigrationCoordinator.new,
      ),
    ],
    child: _ReceiveDesktopScreenHarness(pool: pool),
  );
}

class _ReceiveDesktopScreenHarness extends StatefulWidget {
  const _ReceiveDesktopScreenHarness({required this.pool});

  final ReceiveAddressType pool;

  @override
  State<_ReceiveDesktopScreenHarness> createState() =>
      _ReceiveDesktopScreenHarnessState();
}

class _ReceiveDesktopScreenHarnessState
    extends State<_ReceiveDesktopScreenHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // `AppMainSidebar` reads `GoRouterState.of(context)` while it builds, so
    // an `InheritedGoRouter` alone is not enough: it needs a matched route.
    _router = GoRouter(
      initialLocation: '/receive',
      routes: [
        GoRoute(
          path: '/receive',
          builder: (_, _) => _ReceivePoolSelector(
            pool: widget.pool,
            child: const ReceiveScreen(),
          ),
        ),
        for (final path in const [
          '/home',
          '/send',
          '/swap',
          '/pay',
          '/activity',
          '/settings',
          '/accounts',
          '/add-account',
          '/migration',
          '/voting',
          '/unlock',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _ReceivePreviewRoute(label: path),
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
    return Center(
      child: WbDesktopWindowBox(
        size: const Size(kWbDesktopWindowWidth, kReceiveScreenWindowHeight),
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child: AppToastHost(child: Router.withConfig(config: _router)),
        ),
      ),
    );
  }
}

/// Selects the transparent pool the way a user does.
///
/// `ReceiveScreen`'s selected pool is private state with no constructor seam,
/// so the fixture invokes the real `ReceiveTabs.onChanged` once after mount
/// rather than reproducing the pane with its own tab state.
class _ReceivePoolSelector extends StatefulWidget {
  const _ReceivePoolSelector({required this.pool, required this.child});

  final ReceiveAddressType pool;
  final Widget child;

  @override
  State<_ReceivePoolSelector> createState() => _ReceivePoolSelectorState();
}

class _ReceivePoolSelectorState extends State<_ReceivePoolSelector> {
  static const _maxFrames = 30;
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    if (widget.pool == ReceiveAddressType.shielded) return;
    _selectWhenTabsExist();
  }

  /// The tabs only exist once the shielded address has loaded, so the first
  /// frame is usually too early; re-arm until they are there.
  void _selectWhenTabsExist() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = _findTabs(context);
      if (tabs != null) {
        tabs.onChanged(widget.pool);
        return;
      }
      if (++_frames >= _maxFrames) return;
      _selectWhenTabsExist();
    });
  }

  ReceiveTabs? _findTabs(BuildContext root) {
    ReceiveTabs? found;
    void visit(Element element) {
      if (found != null) return;
      final candidate = element.widget;
      if (candidate is ReceiveTabs) {
        found = candidate;
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReceivePreviewRoute extends StatelessWidget {
  const _ReceivePreviewRoute({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Navigated to $label'));
}

// --- Mobile request sheet --------------------------------------------------

/// The live [ReceiveRequestSheet] on the chrome `showAppMobileSheet` gives it.
Widget receiveRequestSheetFixture({
  ReceiveAddressType pool = ReceiveAddressType.shielded,
  bool priceAvailable = true,
}) {
  return ProviderScope(
    overrides: [
      zecLiveUsdUnitPriceProvider.overrideWithValue(
        priceAvailable ? kReceiveScreenZecUsdPrice : null,
      ),
      requestShareHandlerProvider.overrideWithValue(_previewShare),
    ],
    child: _ReceiveRequestSheetFrame(
      address: pool == ReceiveAddressType.shielded
          ? kReceiveScreenShieldedAddress
          : kReceiveScreenTransparentAddress,
    ),
  );
}

Future<void> _previewShare({
  required Uint8List png,
  required String fileName,
}) async {
  debugPrint('request: share $fileName (${png.length} bytes)');
}

class _ReceiveRequestSheetFrame extends StatelessWidget {
  const _ReceiveRequestSheetFrame({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: WbScaleDownBox(
        size: kWbPhoneSize,
        child: SizedBox.fromSize(
          size: kWbPhoneSize,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: kWbPhoneSize,
              viewPadding: const EdgeInsets.only(top: kWbPhoneStatusBarInset),
              padding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            // A nested navigator so the sheet's own `Navigator.pop` in `_close`
            // lands on this blank route instead of the widgetbook root, and a
            // toast host so copy/share render the real toast.
            child: AppToastHost(
              child: Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  _instantRoute(const SizedBox.shrink()),
                  _instantRoute(
                    RequestAmountSheetSurface(
                      child: ReceiveRequestSheet(address: address),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Route<void> _instantRoute(Widget child) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

// --- Shared fixture state --------------------------------------------------

const _receiveAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'widgetbook-receive-screen',
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'widgetbook-receive-screen',
  activeAddress: kReceiveScreenShieldedAddress,
);

final _receiveBootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: _receiveAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _ReceiveScreenSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _receiveAccountState.activeAccountUuid,
    hasAccountScopedData: true,
    percentage: 1,
    totalBalance: BigInt.from(14223000000),
  );
}

class _ReceiveNoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: the real one reshapes the native window, which
    // belongs to the dev tool in a widgetbook preview.
  }
}

class _ReceiveScreenMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

/// Deterministic [ReceiveAddressService] covering the four load outcomes.
///
/// Only the previewed [pool] gets the outcome; the other pool always resolves.
/// The screen hides its tabs while the selected address is loading, so a
/// transparent preview needs the shielded load to finish for the tab to exist.
class _ReceiveScreenAddressService implements ReceiveAddressService {
  _ReceiveScreenAddressService({required this.pool, required this.outcome});

  final ReceiveAddressType pool;
  final ReceiveScreenAddressOutcome outcome;

  Future<String> _answer(String address, ReceiveAddressType of) {
    if (of != pool) return Future.value(address);
    return switch (outcome) {
      ReceiveScreenAddressOutcome.resolved => Future.value(address),
      // Never completes, which is exactly what the spinner state is.
      ReceiveScreenAddressOutcome.pending => Completer<String>().future,
      ReceiveScreenAddressOutcome.empty => Future.value(''),
      ReceiveScreenAddressOutcome.failed => Future.error(
        const _ReceiveAddressLoadFailure(),
      ),
    };
  }

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) => _answer(
    currentShieldedAddress ?? kReceiveScreenShieldedAddress,
    ReceiveAddressType.shielded,
  );

  @override
  Future<String> loadTransparentReceiveAddress({required String accountUuid}) =>
      _answer(kReceiveScreenTransparentAddress, ReceiveAddressType.transparent);

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) =>
      Future.value(kReceiveScreenShieldedAddress);

  @override
  String? getCachedTransparentAddress(String accountUuid) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The pane renders `e.toString()` verbatim, so this text is a preview
/// stand-in: production shows whatever the address service reports.
class _ReceiveAddressLoadFailure {
  const _ReceiveAddressLoadFailure();

  @override
  String toString() => 'Preview: address load failed';
}

// --- Address components ----------------------------------------------------

/// The props the desktop pane and the mobile receive frame hand the shared
/// address widgets, so a component preview is the size it really occupies.
abstract final class _ReceiveComponentMetrics {
  static const copyWidth = 230.0;
  static const copyHeight = 44.0;

  static const desktopTabsWidth = 256.0;
  static const desktopTabsHeight = 36.0;
  static const mobileTabsWidth = 320.0;
  static const mobileTabsHeight = 44.0;
  static const mobileTabsIconSize = 20.0;

  static const desktopQrSize = 230.0;
  static const mobileQrSize = 260.0;
  static const qrPaddingX = 16.0;
  static const qrPaddingY = 24.0;
  static const desktopQrBadgeSize = 48.0;
  static const mobileQrBadgeSize = 54.26;

  /// Both call sites ask for the same 48pt button.
  static const renewSize = 48.0;

  static const desktopAddressWidth = 262.0;
  static const mobileAddressWidth = 288.0;
  static const mobileAddressLineHeight = 40.0;
}

/// The copy action from the desktop pane, in the 230x44 slot it sits in.
Widget receiveCopyAddressButtonFixture({
  ReceiveAddressType type = ReceiveAddressType.shielded,
  bool enabled = true,
}) {
  final shielded = type == ReceiveAddressType.shielded;
  return _receiveComponentFrame(
    SizedBox(
      width: _ReceiveComponentMetrics.copyWidth,
      height: _ReceiveComponentMetrics.copyHeight,
      child: ReceiveCopyAddressButton(
        label: shielded ? 'Copy shielded address' : 'Copy transparent address',
        type: type,
        enabled: enabled,
        onTap: () => debugPrint('receive: copy address'),
      ),
    ),
  );
}

/// The segmented tabs with each call site's full argument set.
///
/// Stateful so a tap moves the indicator the way it does on screen; the knob
/// still wins whenever it changes.
Widget receiveTabsFixture({
  ReceiveAddressType selected = ReceiveAddressType.shielded,
  WbLayout layout = WbLayout.desktop,
}) {
  return _receiveComponentFrame(
    _ReceiveTabsPreview(selected: selected, layout: layout),
    layout: layout,
  );
}

class _ReceiveTabsPreview extends StatefulWidget {
  const _ReceiveTabsPreview({required this.selected, required this.layout});

  final ReceiveAddressType selected;
  final WbLayout layout;

  @override
  State<_ReceiveTabsPreview> createState() => _ReceiveTabsPreviewState();
}

class _ReceiveTabsPreviewState extends State<_ReceiveTabsPreview> {
  late ReceiveAddressType _selected = widget.selected;

  @override
  void didUpdateWidget(covariant _ReceiveTabsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A knob move overrides whatever the last tap left behind.
    if (oldWidget.selected != widget.selected) _selected = widget.selected;
  }

  void _select(ReceiveAddressType type) => setState(() => _selected = type);

  @override
  Widget build(BuildContext context) {
    if (widget.layout == WbLayout.mobile) {
      return ReceiveTabs(
        width: _ReceiveComponentMetrics.mobileTabsWidth,
        height: _ReceiveComponentMetrics.mobileTabsHeight,
        iconSize: _ReceiveComponentMetrics.mobileTabsIconSize,
        iconGap: AppSpacing.xs,
        labelStyle: AppTypography.labelLarge,
        labelFontWeight: FontWeight.w500,
        alwaysDarkSelected: true,
        selectedType: _selected,
        onChanged: _select,
      );
    }
    return SizedBox(
      width: _ReceiveComponentMetrics.desktopTabsWidth,
      height: _ReceiveComponentMetrics.desktopTabsHeight,
      child: ReceiveTabs(selectedType: _selected, onChanged: _select),
    );
  }
}

/// The QR block on its own, at the size and badge its call site asks for.
Widget receiveQrSurfaceFixture({
  ReceiveAddressType type = ReceiveAddressType.shielded,
  WbLayout layout = WbLayout.desktop,
  bool addressAvailable = true,
}) {
  final mobile = layout == WbLayout.mobile;
  return _receiveComponentFrame(
    ReceiveQrSurface(
      address: addressAvailable ? _receiveComponentAddress(type) : '',
      size: mobile
          ? _ReceiveComponentMetrics.mobileQrSize
          : _ReceiveComponentMetrics.desktopQrSize,
      paddingX: _ReceiveComponentMetrics.qrPaddingX,
      paddingY: _ReceiveComponentMetrics.qrPaddingY,
      type: type,
      badgeSize: mobile
          ? _ReceiveComponentMetrics.mobileQrBadgeSize
          : _ReceiveComponentMetrics.desktopQrBadgeSize,
    ),
    layout: layout,
  );
}

/// The renew button, including the spinner both screens only reach by tapping.
Widget receiveRenewButtonFixture({bool renewing = false}) {
  return _receiveComponentFrame(
    ReceiveRenewButton(
      renewing: renewing,
      size: _ReceiveComponentMetrics.renewSize,
      onTap: () => debugPrint('receive: renew shielded address'),
    ),
  );
}

/// The compact address line with each call site's own styling.
Widget receiveAddressLineFixture({
  ReceiveAddressType type = ReceiveAddressType.shielded,
  WbLayout layout = WbLayout.desktop,
  bool addressAvailable = true,
}) {
  final mobile = layout == WbLayout.mobile;
  final address = addressAvailable ? _receiveComponentAddress(type) : '';
  return _receiveComponentFrame(
    SizedBox(
      width: mobile
          ? _ReceiveComponentMetrics.mobileAddressWidth
          : _ReceiveComponentMetrics.desktopAddressWidth,
      child: Builder(
        builder: (context) => mobile
            ? ReceiveAddressLine(
                type: type,
                address: address,
                secondaryTint: true,
                height: _ReceiveComponentMetrics.mobileAddressLineHeight,
                helpButtonSize:
                    _ReceiveComponentMetrics.mobileAddressLineHeight,
                helpIconSize: 20,
                helpIconColor: context.colors.icon.muted,
                helpGap: 10,
                scaleToFit: true,
                onShowHelp: _receiveComponentHelp,
              )
            : ReceiveAddressLine(
                type: type,
                address: address,
                onShowHelp: _receiveComponentHelp,
              ),
      ),
    ),
    layout: layout,
  );
}

String _receiveComponentAddress(ReceiveAddressType type) =>
    type == ReceiveAddressType.shielded
    ? kReceiveScreenShieldedAddress
    : kReceiveScreenTransparentAddress;

void _receiveComponentHelp() => debugPrint('receive: show address help');

/// Components sit on the window colour of the screen they belong to: the renew
/// button's ring is painted with exactly that colour, so any other ground
/// would draw a halo the product never shows.
Widget _receiveComponentFrame(
  Widget child, {
  WbLayout layout = WbLayout.desktop,
}) {
  return Builder(
    builder: (context) => ColoredBox(
      color: layout == WbLayout.mobile
          ? context.colors.background.window
          : context.colors.macosUtility.window,
      child: Center(child: child),
    ),
  );
}
