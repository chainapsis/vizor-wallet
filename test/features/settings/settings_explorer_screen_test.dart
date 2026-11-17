import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/zcash_explorer.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_explorer_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zcash_explorer_provider.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/test_l10n.dart';

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1exploreraddress',
);

AppBootstrapState _bootstrap({
  String explorerUrlTemplate = '',
  String network = 'main',
}) => AppBootstrapState(
  initialLocation: '/settings/explorer',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: network,
  rpcEndpointConfig: defaultRpcEndpointConfig(network),
  explorerUrlTemplate: explorerUrlTemplate,
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeExplorerNotifier extends ZcashExplorerNotifier {
  _FakeExplorerNotifier(this.initial);

  final String initial;

  @override
  String build() => initial;

  @override
  Future<void> setCustom(String input) async {
    state = normalizeExplorerUrlTemplate(input);
  }

  @override
  Future<void> resetToDefault() async {
    state = '';
  }
}

Widget _harness({
  String explorerUrlTemplate = '',
  String network = 'main',
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: '/settings/explorer',
    routes: [
      GoRoute(
        path: '/settings/explorer',
        builder: (_, _) => const SettingsExplorerScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(explorerUrlTemplate: explorerUrlTemplate, network: network),
      ),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      zcashExplorerProvider.overrideWith(
        () => _FakeExplorerNotifier(explorerUrlTemplate),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to ZecBlock and saves a custom origin', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('ZecBlock'), findsOneWidget);
    expect(find.textContaining('zecblock.com'), findsWidgets);
    expect(find.text(testL10n.settingsExplorerPrivacyCopy), findsOneWidget);
    expect(find.text('Any explorer you prefer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('explorer_option_custom')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('explorer_custom_field')),
      'https://privacy.example',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('explorer_update')));
    await tester.pump();

    expect(find.textContaining('privacy.example'), findsWidgets);
  });

  testWidgets('resetting to ZecBlock clears a custom explorer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness(explorerUrlTemplate: 'https://privacy.example/tx/{txid}'),
    );
    await tester.pump();

    expect(find.textContaining('privacy.example'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('explorer_option_zecblock')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('explorer_update')));
    await tester.pump();

    expect(find.textContaining('(default)'), findsOneWidget);
  });

  testWidgets('saves ZecBlock Private and describes its trade-off', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Current: zecblock.com (default)'), findsOneWidget);
    expect(find.text(testL10n.settingsExplorerPrivateCopy), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('explorer_option_zecblock_private')),
    );
    await tester.pump();

    expect(find.text(testL10n.settingsExplorerPrivateCopy), findsOneWidget);
    expect(find.text(testL10n.settingsExplorerPrivacyCopy), findsNothing);

    await tester.tap(find.byKey(const ValueKey('explorer_update')));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsExplorerScreen)),
    );
    expect(
      container.read(zcashExplorerProvider),
      kZecBlockPrivateExplorerTemplate,
    );
    expect(find.text('Current: ZecBlock Private'), findsOneWidget);
  });

  testWidgets('a saved ZecBlock Private is not offered as a custom URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness(explorerUrlTemplate: kZecBlockPrivateExplorerTemplate),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('explorer_option_custom')));
    await tester.pump();

    expect(find.textContaining('private.zecblock.com'), findsNothing);
  });

  testWidgets('offers ZecBlock Private on mainnet only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness(
        explorerUrlTemplate: kZecBlockPrivateExplorerTemplate,
        network: 'test',
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('explorer_option_zecblock_private')),
      findsNothing,
    );
    expect(
      find.text('Current: testnet.zecblock.com (default)'),
      findsOneWidget,
    );
  });

  testWidgets('option cards announce their subtitle and grow with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final semantics = tester.ensureSemantics();
    // The sidebar and the button overflow at this scale on their own; only
    // errors raised from this screen's widgets count here.
    final layoutErrors = <String>[];
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) => layoutErrors.add(details.toString());

    await tester.pumpWidget(_harness(textScale: 2));
    await tester.pump();
    FlutterError.onError = reportError;

    expect(
      layoutErrors.where((e) => e.contains('settings_explorer_screen.dart')),
      isEmpty,
    );
    final card = find.byKey(const ValueKey('explorer_option_zecblock_private'));
    expect(tester.getSize(card).height, greaterThan(64));
    expect(
      tester
          .getRect(
            find.descendant(
              of: card,
              matching: find.text(testL10n.settingsExplorerPrivateSubtitle),
            ),
          )
          .bottom,
      lessThan(tester.getRect(card).bottom),
    );
    final announced = find.bySemanticsLabel(
      'ZecBlock Private, ${testL10n.settingsExplorerPrivateSubtitle}',
    );
    expect(announced, findsOneWidget);
    expect(
      tester
          .getSemantics(announced)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });
}
