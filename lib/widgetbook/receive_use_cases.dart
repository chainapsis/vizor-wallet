// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:math' as math;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/receive/screens/mobile/mobile_receive_screen.dart';
import '../src/features/receive/widgets/mobile/receive_address_info_sheet.dart';
import '../src/features/receive/widgets/receive_desktop_preview.dart';
import '../src/features/receive/widgets/receive_address_widgets.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';

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

Widget buildReceiveMobileShieldedUseCase(BuildContext context) {
  return const _ReceiveMobileHarness(type: ReceiveAddressType.shielded);
}

Widget buildReceiveMobileTransparentUseCase(BuildContext context) {
  return const _ReceiveMobileHarness(type: ReceiveAddressType.transparent);
}

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
    return ColoredBox(
      color: colors.background.window,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : ReceiveDesktopPreview.size.width;
          final maxHeight =
              constraints.maxHeight.isFinite
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
    );
  }
}

class _ReceiveMobileHarness extends StatelessWidget {
  const _ReceiveMobileHarness({required this.type});

  final ReceiveAddressType type;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_mobileReceiveBootstrap),
        syncProvider.overrideWith(() => _WidgetbookSyncNotifier()),
        receiveAddressServiceProvider.overrideWithValue(
          const _WidgetbookReceiveAddressService(),
        ),
      ],
      child: SizedBox(
        width: 393,
        height: 852,
        child: MobileReceiveScreen(initialType: type),
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
    return SizedBox(
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
    displayPercentage: 1,
  );
}

class _WidgetbookReceiveAddressService implements ReceiveAddressService {
  const _WidgetbookReceiveAddressService();

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => currentShieldedAddress ?? _mobileShieldedAddress;

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async =>
      _mobileTransparentAddress;

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async =>
      _mobileShieldedAddress;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
