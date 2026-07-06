import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _figmaSyncingText = Color(0xFFA3A4A4);
const _figmaSyncingHighlight = Color(0xFFFFFFFF);

void main() {
  testWidgets('desktop sidebar syncing state uses Figma static colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _desktopHarness(
        SyncState(isSyncing: true, displayPercentage: 0.34),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(find.text('34% Syncing...'));
    expect(text.style?.color, _figmaSyncingText);
    expect(_desktopSyncIndicatorColor(tester), _figmaSyncingText);
    expect(AppThemeData.light.colors.sync.textSyncing, _figmaSyncingText);
    expect(AppThemeData.light.colors.sync.lightSyncing, _figmaSyncingText);
  });

  testWidgets('desktop sidebar syncing shimmer uses Figma highlight color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _desktopHarness(
        SyncState(isSyncing: true, displayPercentage: 0.34),
        disableAnimations: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final syncText = find.byKey(const ValueKey('sidebar_sync_text'));
    expect(
      find.descendant(of: syncText, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    final text = tester.widget<Text>(
      find.descendant(of: syncText, matching: find.text('34% Syncing...')),
    );
    expect(text.style?.color, _figmaSyncingHighlight);
    expect(_desktopSyncIndicatorColor(tester), _figmaSyncingText);
    expect(
      AppThemeData.light.colors.sync.textSyncingHighlight,
      _figmaSyncingHighlight,
    );

    await tester.pumpWidget(const SizedBox());
  });
}

Widget _desktopHarness(SyncState syncState, {required bool disableAnimations}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('home')),
        ),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(syncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

Color? _desktopSyncIndicatorColor(WidgetTester tester) {
  final indicator = find.byKey(const ValueKey('sidebar_sync_indicator'));
  final decoratedBox = tester.widget<DecoratedBox>(
    find.ancestor(of: indicator, matching: find.byType(DecoratedBox)).first,
  );
  final decoration = decoratedBox.decoration as BoxDecoration;
  return decoration.color;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
