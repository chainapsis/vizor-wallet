import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';

void main() {
  testWidgets('shows shielded renew button for software accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness());
    await tester.pump();
    await tester.pump();

    expect(_findAppIcon(AppIcons.renew), findsOneWidget);
  });

  testWidgets('hides shielded renew button for hardware accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness(bootstrap: _hardwareBootstrap));
    await tester.pump();
    await tester.pump();

    expect(_findAppIcon(AppIcons.renew), findsNothing);
  });

  testWidgets('uses Keystone shielded help copy for hardware accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness(bootstrap: _hardwareBootstrap));
    await tester.pump();
    await tester.pump();

    await tester.tap(_findAppIcon(AppIcons.help));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Shielded Address'), findsOneWidget);
    expect(
      find.text(
        "Keystone provides an Orchard-only shielded address, so Vizor can't renew it from this screen.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Renew button'), findsNothing);
  });

  testWidgets('receive info modal does not block sidebar navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness());
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.help,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Shielded Address'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('Send'),
        matching: find.byType(AppSidebarItem),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('send route'), findsOneWidget);
  });

  testWidgets('ignores stale shielded load failure after account switch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    late _RacyReceiveAddressService service;
    final bootstrap = _twoAccountBootstrap;
    await tester.pumpWidget(
      _receiveRaceHarness(
        bootstrap: bootstrap,
        receiveAddressService: (ref) {
          service = _RacyReceiveAddressService(ref);
          return service;
        },
        accountNotifier: () => _FakeAccountNotifier(
          bootstrap.initialAccountState,
          {'account-1': _accountOneAddress, 'account-2': null},
        ),
      ),
    );
    await tester.pump();

    expect(service.hasPending('account-1'), isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReceiveScreen)),
      listen: false,
    );
    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();

    expect(service.hasPending('account-2'), isTrue);

    service.fail('account-1', StateError('old account load failed'));
    await tester.pump();

    expect(_findAddressRichText('u1accountone'), findsNothing);
    expect(find.textContaining('old account load failed'), findsNothing);

    service.complete('account-2', _accountTwoAddress);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_findAddressRichText('u1accounttwo'), findsOneWidget);
  });
}

Finder _findAddressRichText(String fragment) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains(fragment),
  );
}

Finder _findAppIcon(String iconName) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == iconName,
  );
}

Widget _receiveHarness({
  AppBootstrapState? bootstrap,
  ReceiveAddressService Function(Ref ref)? receiveAddressService,
}) {
  final router = GoRouter(
    initialLocation: '/receive',
    routes: [
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap),
      receiveAddressServiceProvider.overrideWith(
        receiveAddressService ?? _FakeReceiveAddressService.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Widget _receiveRaceHarness({
  required AppBootstrapState bootstrap,
  required ReceiveAddressService Function(Ref ref) receiveAddressService,
  required AccountNotifier Function() accountNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/receive',
    routes: [
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap),
      receiveAddressServiceProvider.overrideWith(receiveAddressService),
      accountProvider.overrideWith(accountNotifier),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: _shieldedAddress,
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _twoAccountBootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: _accountOneAddress,
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone Vault',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: _shieldedAddress,
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _shieldedAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000000';
const _accountOneAddress = 'u1accountone-stale';
const _accountTwoAddress = 'u1accounttwo-current';

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(super.ref);

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return currentShieldedAddress ?? _shieldedAddress;
  }

  @override
  String? getCachedTransparentAddress(String accountUuid) {
    return 't1testtransparentaddress';
  }

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return 't1testtransparentaddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return _shieldedAddress;
  }
}

class _RacyReceiveAddressService extends ReceiveAddressService {
  _RacyReceiveAddressService(super.ref);

  final _pending = <String, Completer<String>>{};

  bool hasPending(String accountUuid) => _pending.containsKey(accountUuid);

  void complete(String accountUuid, String address) {
    _pending.remove(accountUuid)?.complete(address);
  }

  void fail(String accountUuid, Object error) {
    _pending.remove(accountUuid)?.completeError(error);
  }

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) {
    return _pending.putIfAbsent(accountUuid, Completer<String>.new).future;
  }

  @override
  String? getCachedTransparentAddress(String accountUuid) => null;

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return 't1transparent-$accountUuid';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) {
    return loadShieldedAddress(accountUuid: accountUuid);
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState, this.addresses);

  final AccountState initialState;
  final Map<String, String?> addresses;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      AccountState(
        accounts: prev.accounts,
        activeAccountUuid: uuid,
        activeAddress: addresses[uuid],
      ),
    );
  }
}
