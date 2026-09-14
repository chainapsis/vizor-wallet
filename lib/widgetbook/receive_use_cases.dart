// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:math' as math;

import 'package:flutter/material.dart' show MaterialApp, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/receive/screens/mobile/mobile_receive_screen.dart';
import '../src/features/receive/services/request_qr_export.dart';
import '../src/features/receive/widgets/mobile/receive_address_info_sheet.dart';
import '../src/features/receive/widgets/receive_desktop_preview.dart';
import '../src/features/receive/widgets/receive_address_widgets.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import 'support/wb_layout.dart';

Widget buildReceiveDesktopShieldedUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.shielded,
  );
}

Widget buildReceiveDesktopTransparentUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.transparent,
  );
}

Widget buildReceiveDesktopShieldedModalUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.shieldedModal,
  );
}

Widget buildReceiveDesktopTransparentModalUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.transparentModal,
  );
}

/// Receive with the "Request ZEC" entry under the copy button.
///
/// Entry mock only — the live screen is untouched, so this is the one place
/// the second CTA and its re-tuned coordinates can be reviewed.
Widget buildReceiveDesktopRequestEntryUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.shieldedRequestEntry,
  );
}

Widget buildReceiveMobileShieldedUseCase(BuildContext context) {
  return const _ReceiveMobileHarness(type: ReceiveAddressType.shielded);
}

Widget buildReceiveMobileTransparentUseCase(BuildContext context) {
  return const _ReceiveMobileHarness(type: ReceiveAddressType.transparent);
}

/// The mobile Receive screen with the pool and the address outcome as inputs.
///
/// `addressAvailable: false` makes the load fail, which is the one path that
/// leaves the pane with an empty address and its actions disabled.
Widget receiveMobileScreenFixture({
  required ReceiveAddressType type,
  bool addressAvailable = true,
}) {
  return _ReceiveMobileHarness(type: type, addressAvailable: addressAvailable);
}

/// The actual mobile receive screen and its request sheet, backed only by
/// in-memory addresses, price and sharing. This is used by the connected flow
/// playground; the snapshot fixture above intentionally remains unchanged.
Widget receiveMobileFlowFixture({
  required ReceiveAddressType type,
  bool addressAvailable = true,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_mobileReceiveBootstrap),
      syncProvider.overrideWith(() => _WidgetbookSyncNotifier()),
      receiveAddressServiceProvider.overrideWithValue(
        addressAvailable
            ? const _WidgetbookReceiveAddressService()
            : const _WidgetbookReceiveAddressService(available: false),
      ),
      zecLiveUsdUnitPriceProvider.overrideWithValue(70),
      requestShareHandlerProvider.overrideWithValue(
        ({required png, required fileName}) async {},
      ),
    ],
    child: WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
        width: 393,
        height: 852,
        // The live request flow intentionally presents on the root navigator.
        // A nested app keeps that root inside the phone frame instead of
        // escaping into Widgetbook's desktop-sized navigator.
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MobileReceiveScreen(
            initialType: type,
            shareAddress: _ignoreSharedAddress,
          ),
        ),
      ),
    ),
  );
}

Future<void> _ignoreSharedAddress(String address) async {}

Widget buildReceiveMobileShieldedSheetUseCase(BuildContext context) {
  return const _ReceiveMobileSheetHarness(type: ReceiveAddressType.shielded);
}

Widget buildReceiveMobileTransparentSheetUseCase(BuildContext context) {
  return const _ReceiveMobileSheetHarness(type: ReceiveAddressType.transparent);
}

class _ReceiveDesktopHarness extends StatelessWidget {
  const _ReceiveDesktopHarness({required this.state});

  final ReceiveDesktopPreviewState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: colors.background.window,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : ReceiveDesktopPreview.size.width;
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : ReceiveDesktopPreview.size.height;
            final contentWidth = math.max(320.0, maxWidth);
            final contentHeight = math.max(240.0, maxHeight);
            final scale = math.min(
              contentWidth / ReceiveDesktopPreview.size.width,
              contentHeight / ReceiveDesktopPreview.size.height,
            );

            return Center(
              child: SizedBox(
                width: ReceiveDesktopPreview.size.width * scale,
                height: ReceiveDesktopPreview.size.height * scale,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: ReceiveDesktopPreview(state: state),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReceiveMobileHarness extends StatelessWidget {
  const _ReceiveMobileHarness({
    required this.type,
    this.addressAvailable = true,
  });

  final ReceiveAddressType type;
  final bool addressAvailable;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_mobileReceiveBootstrap),
        syncProvider.overrideWith(() => _WidgetbookSyncNotifier()),
        // Both branches are const, so a rebuild never hands the provider a
        // new identity and the default render stays byte-identical.
        receiveAddressServiceProvider.overrideWithValue(
          addressAvailable
              ? const _WidgetbookReceiveAddressService()
              : const _WidgetbookReceiveAddressService(available: false),
        ),
      ],
      child: WbScaleDownBox(
        size: const Size(393, 852),
        child: SizedBox(
          width: 393,
          height: 852,
          child: MobileReceiveScreen(initialType: type),
        ),
      ),
    );
  }
}

class _ReceiveMobileSheetHarness extends StatelessWidget {
  const _ReceiveMobileSheetHarness({required this.type});

  final ReceiveAddressType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
        width: 393,
        height: 852,
        child: Stack(
          children: [
            Positioned.fill(child: _ReceiveMobileHarness(type: type)),
            Positioned.fill(
              child: ColoredBox(color: colors.background.neutralScrim),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: MobileModalCard(
                  child: ReceiveAddressInfoSheet(type: type),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _mobileShieldedAddress =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _mobileTransparentAddress = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

const _mobileAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'widgetbook-receive',
      name: 'Account Name',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'widgetbook-receive',
  activeAddress: _mobileShieldedAddress,
);

final _mobileReceiveBootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: _mobileAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _WidgetbookSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _mobileAccountState.activeAccountUuid,
    hasAccountScopedData: true,
    percentage: 1,
  );
}

class _WidgetbookReceiveAddressService implements ReceiveAddressService {
  const _WidgetbookReceiveAddressService({this.available = true});

  /// When false every load fails, which is how the screen reaches the empty
  /// address its share / request / copy actions are disabled on.
  final bool available;

  Future<String> _answer(String address) async {
    if (!available) throw const _WidgetbookAddressUnavailable();
    return address;
  }

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) => _answer(currentShieldedAddress ?? _mobileShieldedAddress);

  @override
  Future<String> loadTransparentReceiveAddress({required String accountUuid}) =>
      _answer(_mobileTransparentAddress);

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) =>
      _answer(_mobileShieldedAddress);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Preview stand-in, never product copy; the mobile pane has no error line, so
/// this only ever reaches a log.
class _WidgetbookAddressUnavailable {
  const _WidgetbookAddressUnavailable();

  @override
  String toString() => 'Preview: address load failed';
}
