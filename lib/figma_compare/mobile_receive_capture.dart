import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/formatting/sync_status_label.dart';
import '../src/core/layout/mobile/mobile_navigation_scope.dart';
import '../src/core/layout/mobile/mobile_page_viewport.dart';
import '../src/core/layout/mobile/mobile_wallet_sidebar.dart';
import '../src/core/layout/mobile/mobile_window_layout.dart';
import '../src/core/layout/mobile/mobile_window_policy.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/receive/screens/mobile/mobile_receive_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/services/native_mobile_navigation_geometry.dart';

/// Real receive widgets and pane geometry, with no storage, network or Rust.
class MobileReceiveCapture extends StatelessWidget {
  const MobileReceiveCapture({this.native, this.keystone = false, super.key});

  final MobileNavigationGeometry? native;
  final bool keystone;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final layout = MobileWindowLayout.resolve(media: media, native: native);
    final wide = layout.mode == MobileNavigationMode.sidebar;
    final account = AccountState(
      accounts: [
        AccountInfo(
          uuid: 'capture-receive',
          name: keystone ? 'Keystone Vault' : 'Account Name',
          order: 0,
          isHardware: keystone,
          hardwareSignerKind: keystone ? HardwareSignerKind.keystone : null,
        ),
      ],
      activeAccountUuid: 'capture-receive',
      activeAddress: _shielded,
    );
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/receive',
            initialAccountState: account,
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: defaultRpcEndpointConfig('main'),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        syncProvider.overrideWith(_CaptureSync.new),
        receiveAddressServiceProvider.overrideWithValue(
          const _CaptureAddresses(),
        ),
      ],
      child: MobileWindowPolicyScope(
        policy: layout.windowPolicy,
        child: MobileNavigationScope(
          mode: layout.mode,
          navigation: MobileBranchNavigation(),
          contentRect: wide
              ? layout.body.shift(-layout.viewport.topLeft)
              : null,
          availableContentRect: wide
              ? layout.availableContentRect?.shift(-layout.viewport.topLeft)
              : null,
          child: ColoredBox(
            color: context.colors.background.window,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: layout.viewport,
                  child: MediaQuery(
                    data: mobilePaneMedia(
                      media,
                      layout.viewport,
                      safeRect: layout.contentSafeRect,
                    ),
                    child: const MobilePageViewport(
                      maxContentWidth: MobileReceiveScreen.maximumWideWidth,
                      child: MobileReceiveScreen(),
                    ),
                  ),
                ),
                if (wide)
                  Positioned.fromRect(
                    rect: layout.sidebar!,
                    child: MediaQuery(
                      data: mobilePaneMedia(
                        media,
                        layout.sidebar!,
                        safeRect: layout.contentSafeRect,
                      ),
                      child: MobileWalletSidebar(
                        accountName: account.activeAccount!.name,
                        avatar: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(child: Text('M')),
                        ),
                        status: const SyncStatusLabel(
                          kind: SyncStatusKind.synced,
                          label: 'Vizor is synced',
                          semanticsLabel: 'Vizor is synced',
                        ),
                        currentPath: '/receive',
                        swapEnabled: true,
                        onSelect: (_) {},
                        onAccountTap: () {},
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _shielded =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _transparent = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

class _CaptureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(percentage: 1);
}

class _CaptureAddresses implements ReceiveAddressService {
  const _CaptureAddresses();

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => currentShieldedAddress ?? _shielded;

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async => _transparent;

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async =>
      '${_shielded}new';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildMobileReceiveWideCapture(BuildContext context) =>
    const MobileReceiveCapture();
