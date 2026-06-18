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
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

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

    expect(_findRenewShieldedAddressButton(), findsOneWidget);
    final backLabelFinder = find.descendant(
      of: find.byKey(const ValueKey('receive_pane_back_button')),
      matching: find.text('Home'),
    );
    final backLabelStyle = tester.widget<Text>(backLabelFinder).style;
    expect(backLabelStyle?.fontSize, 14);
    expect(backLabelStyle?.height, 16 / 14);
    expect(backLabelStyle?.color, AppThemeData.light.colors.button.ghost.label);
    final paneTopLeft = tester.getTopLeft(find.byType(AppDesktopPane));
    expect(
      tester.getTopLeft(backLabelFinder).dx,
      moreOrLessEquals(
        paneTopLeft.dx + AppSpacing.sm + 16 + AppSpacing.xxs,
        epsilon: 0.1,
      ),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_copy_shielded_address_button')),
      ),
      const Size(230, 44),
    );
    expect(
      tester.getSize(_findRenewShieldedAddressButton()),
      const Size(48, 48),
    );
    expect(
      _findCopyButtonGap('receive_copy_shielded_address_button'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('receive_address_type_tabs'))),
      const Size(256, 36),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_address_type_tab_shielded')),
      ),
      const Size(128, 36),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_address_type_tab_transparent')),
      ),
      const Size(128, 36),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_address_type_tabs_indicator')),
      ),
      const Size(124, 32),
    );
    final shieldedTabLabel = tester.widget<Text>(find.text('Shielded'));
    expect(shieldedTabLabel.style?.fontFamily, 'Geist');
    expect(shieldedTabLabel.style?.fontWeight, FontWeight.w400);
    expect(shieldedTabLabel.style?.fontSize, 13);
    expect(shieldedTabLabel.style?.height, 14 / 13);
    expect(shieldedTabLabel.style?.letterSpacing, 0);
  });

  testWidgets('compacts receive addresses without shielded edge color', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness());
    await tester.pump();
    await tester.pump();

    final shieldedRichText = tester.widget<RichText>(
      _findAddressRichText('u1testshielde ... 00000000000'),
    );
    final shieldedSpan = shieldedRichText.text as TextSpan;
    expect(shieldedRichText.overflow, TextOverflow.clip);
    expect(shieldedSpan.style?.fontFamily, 'Geist');
    expect(shieldedSpan.style?.fontWeight, FontWeight.w500);
    expect(shieldedSpan.style?.fontSize, 14);
    expect(shieldedSpan.style?.height, 16 / 14);
    expect(shieldedSpan.style?.letterSpacing, -0.06);
    expect('...'.allMatches(shieldedSpan.toPlainText()).length, 1);
    expect(shieldedSpan.children, hasLength(1));
    expect((shieldedSpan.children!.single as TextSpan).style?.color, isNull);

    await tester.tap(find.text('Transparent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(
      _findAddressRichText('t1testtranspa ... 11111111111'),
      findsOneWidget,
    );
  });

  testWidgets('uses dark receive color for renew icon and address text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness(themeData: AppThemeData.dark));
    await tester.pump();
    await tester.pump();

    final renewIcon = tester.widget<AppIcon>(_findAppIcon(AppIcons.renew));
    expect(renewIcon.color, AppThemeData.dark.colors.text.homeCard);

    final shieldedRichText = tester.widget<RichText>(
      _findAddressRichText('u1testshielde ... 00000000000'),
    );
    final shieldedSpan = shieldedRichText.text as TextSpan;
    expect(shieldedSpan.style?.color, AppThemeData.dark.colors.text.accent);
    expect(shieldedSpan.children, hasLength(1));
    expect((shieldedSpan.children!.single as TextSpan).style?.color, isNull);
  });

  testWidgets('shows shielded renew button for hardware accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness(bootstrap: _hardwareBootstrap));
    await tester.pump();
    await tester.pump();

    expect(_findRenewShieldedAddressButton(), findsOneWidget);
  });

  testWidgets('renews shielded address for hardware accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    late _RecordingReceiveAddressService service;
    await tester.pumpWidget(
      _receiveHarness(
        bootstrap: _hardwareBootstrap,
        receiveAddressService: (ref) {
          service = _RecordingReceiveAddressService(ref);
          return service;
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(_findRenewShieldedAddressButton());
    await tester.pump();

    expect(service.renewedAccountUuid, 'account-1');
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

    expect(find.text('Shielded address'), findsOneWidget);
    expect(
      find.text(
        'A new Zcash shielded address is generated only when you click the renew button.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('fixed shielded address'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('receive_shielded_info_modal'))),
      const Size(312, 382),
    );
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

    expect(find.text('Shielded address'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('Activity'),
        matching: find.byType(AppSidebarItem),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('activity route'), findsOneWidget);
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

Finder _findRenewShieldedAddressButton() {
  return find.byKey(const ValueKey('receive_renew_shielded_address_button'));
}

Finder _findCopyButtonGap(String buttonKey) {
  return find.descendant(
    of: find.byKey(ValueKey(buttonKey)),
    matching: find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.width == 8,
    ),
  );
}

Widget _receiveHarness({
  AppBootstrapState? bootstrap,
  ReceiveAddressService Function(Ref ref)? receiveAddressService,
  AppThemeData themeData = AppThemeData.light,
}) {
  final effectiveBootstrap = bootstrap ?? _bootstrap;
  final router = GoRouter(
    initialLocation: '/receive',
    routes: [
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(effectiveBootstrap),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          _syncedStateFor(effectiveBootstrap.initialAccountState),
        ),
      ),
      receiveAddressServiceProvider.overrideWith(
        receiveAddressService ?? _FakeReceiveAddressService.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: themeData, child: child!),
    ),
  );
}

SyncState _syncedStateFor(AccountState accountState) {
  return SyncState(
    accountUuid: accountState.activeAccountUuid,
    hasAccountScopedData: true,
    percentage: 1,
    displayPercentage: 1,
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
      syncProvider.overrideWith(FakeSyncNotifier.new),
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
const _renewedShieldedAddress =
    'u1testrenewedshieldedaddress0000000000000000000000000000000000000000000';
const _transparentAddress =
    't1testtransparentaddress111111111111111111111111111111111111';
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
    return _transparentAddress;
  }

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return _transparentAddress;
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return _shieldedAddress;
  }
}

class _RecordingReceiveAddressService extends _FakeReceiveAddressService {
  _RecordingReceiveAddressService(super.ref);

  String? renewedAccountUuid;

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    renewedAccountUuid = accountUuid;
    return _renewedShieldedAddress;
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
