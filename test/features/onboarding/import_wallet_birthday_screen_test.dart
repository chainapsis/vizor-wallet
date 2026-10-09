import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_account_discovery_incomplete_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_account_discovery_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  test('import flow ends with account customisation', () {
    expect(ImportOnboardingStep.customiseAccount.label, 'Customise wallet');
    expect(
      importOnboardingStepFromLocation('/import/customise-account'),
      ImportOnboardingStep.customiseAccount,
    );
  });

  testWidgets('birthday tab labels show a click cursor', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(_birthdayHarness());
    await tester.pump();

    expect(_cursorForText(tester, 'Enter the date'), SystemMouseCursors.click);
    expect(
      _cursorForText(tester, 'Enter the block height'),
      SystemMouseCursors.click,
    );
  });

  testWidgets('birthday date field shows a click cursor when enabled', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(_birthdayHarness());
    await tester.pump();
    await tester.pump();

    expect(_cursorForText(tester, 'mm/dd/yyyy'), SystemMouseCursors.click);
  });

  testWidgets('birthday date field opens before endpoint metadata finishes', (
    tester,
  ) async {
    final metadataCompleter = Completer<ImportBirthdayMetadata>();
    addTearDown(() {
      if (!metadataCompleter.isCompleted) {
        metadataCompleter.complete(_metadataFixture());
      }
    });

    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _birthdayHarness(
        failoverBuilder: () => _PendingMetadataRpcEndpointFailoverNotifier(
          metadataCompleter.future,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('mm/dd/yyyy'));
    await tester.pump();

    expect(find.byType(ImportBirthdayCalendarOverlay), findsOneWidget);

    metadataCompleter.complete(_metadataFixture());
    await tester.pump();
  });

  testWidgets('block height error state shows the design message', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _birthdayHarness(
        args: const ImportBirthdayArgs(
          mnemonic: 'test mnemonic',
          initialBirthdayHeight: 312009123,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final errorText = find.text("Doesn't seem like a legit block height");
    expect(errorText, findsOneWidget);

    final textWidget = tester.widget<Text>(errorText);
    expect(
      textWidget.style?.color,
      AppThemeData.light.colors.border.utilityDestructive,
    );
    expect(textWidget.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('configured wallet continues to account customisation', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _birthdayRouterHarness(
        args: const ImportBirthdayArgs(
          mnemonic: 'test mnemonic',
          initialBirthdayHeight: 1000000,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('import_birthday_submit_button')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Customise route'), findsOneWidget);
  });

  testWidgets('completed discovery without candidates continues directly', (
    tester,
  ) async {
    CustomiseAccountArgs? customiseArgs;
    await _submitWithDiscovery(
      tester,
      _discovery(rust_wallet.SoftwareAccountDiscoveryStatus.completed),
      onCustomiseArgs: (args) => customiseArgs = args,
    );

    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsNothing);
    expect(find.text('Customise route'), findsOneWidget);
    expect(customiseArgs?.setupArgs.selectedAdditionalAccountIndices, isEmpty);
  });

  testWidgets(
    'withheld discovery warns before continuing with the primary account',
    (tester) async {
      CustomiseAccountArgs? customiseArgs;
      await _submitWithDiscovery(
        tester,
        _discovery(rust_wallet.SoftwareAccountDiscoveryStatus.withheld),
        onCustomiseArgs: (args) => customiseArgs = args,
      );

      expect(
        find.byType(ImportAccountDiscoveryIncompleteModal),
        findsOneWidget,
      );
      expect(find.textContaining('Private queries'), findsOneWidget);
      expect(
        find.textContaining("doesn't mean the other accounts are empty"),
        findsOneWidget,
      );
      expect(find.text('Customise route'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('import_account_discovery_incomplete_continue'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Customise route'), findsOneWidget);
      expect(
        customiseArgs?.setupArgs.selectedAdditionalAccountIndices,
        isEmpty,
      );
    },
  );

  testWidgets('partial discovery warns, then offers the found accounts', (
    tester,
  ) async {
    CustomiseAccountArgs? customiseArgs;
    await _submitWithDiscovery(
      tester,
      _discovery(
        rust_wallet.SoftwareAccountDiscoveryStatus.partial,
        accounts: const [
          rust_wallet.SoftwareWalletDiscoveredAccount(
            zip32AccountIndex: 1,
            firstTransparentAddress: 't1VzLrfU8ZRs3xEGzR84xHWL2QK7C9Tt6yV',
          ),
        ],
      ),
      onCustomiseArgs: (args) => customiseArgs = args,
    );

    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsOneWidget);
    expect(find.byType(ImportAccountDiscoveryModal), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('import_account_discovery_incomplete_continue'),
      ),
    );
    await tester.pump();

    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsNothing);
    expect(find.byType(ImportAccountDiscoveryModal), findsOneWidget);
    expect(
      find.byKey(const ValueKey('import_account_discovery_row_1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Customise route'), findsOneWidget);
    expect(customiseArgs?.setupArgs.selectedAdditionalAccountIndices, [1]);
  });

  testWidgets('an open discovery warning blocks a second submit', (
    tester,
  ) async {
    CustomiseAccountArgs? customiseArgs;
    final accountNotifier = _FailingImportAccountNotifier(
      discovery: _discovery(
        rust_wallet.SoftwareAccountDiscoveryStatus.withheld,
      ),
    );
    await _submitWithDiscovery(
      tester,
      accountNotifier.discovery,
      accountNotifier: accountNotifier,
      onCustomiseArgs: (args) => customiseArgs = args,
    );
    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsOneWidget);

    // The overlay does not trap keyboard focus, so the submit action itself
    // must stay disabled while the warning is open.
    final submit = tester.widget<AppButton>(
      find.byKey(const ValueKey('import_birthday_submit_button')),
    );
    expect(submit.onPressed, isNull);
    submit.onPressed?.call();
    await tester.pump();
    await tester.pump();

    expect(accountNotifier.discoveryCalls, 1);
    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('import_account_discovery_incomplete_continue'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Customise route'), findsOneWidget);
    expect(customiseArgs?.setupArgs.selectedAdditionalAccountIndices, isEmpty);
  });

  testWidgets('unavailable discovery back keeps the birthday screen', (
    tester,
  ) async {
    CustomiseAccountArgs? customiseArgs;
    await _submitWithDiscovery(
      tester,
      _discovery(rust_wallet.SoftwareAccountDiscoveryStatus.unavailable),
      onCustomiseArgs: (args) => customiseArgs = args,
    );

    expect(find.textContaining("couldn't be reached"), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_incomplete_back')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImportAccountDiscoveryIncompleteModal), findsNothing);
    expect(find.text('Customise route'), findsNothing);
    expect(customiseArgs, isNull);
    expect(find.byType(ImportWalletBirthdayScreen), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('import_birthday_submit_button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('account discovery modal imports all candidates by default', (
    tester,
  ) async {
    List<int>? selected;

    await tester.pumpWidget(
      _modalHarness(onConfirm: (value) => selected = value),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
    );

    expect(selected, [1, 2]);
  });

  testWidgets('account discovery modal labels candidates by BIP44 path', (
    tester,
  ) async {
    await tester.pumpWidget(_modalHarness(onConfirm: (_) {}));

    expect(find.text("m/44'/133'/1'/..."), findsOneWidget);
    expect(find.text("m/44'/133'/2'/..."), findsOneWidget);
    expect(find.text('Account 1'), findsNothing);
    expect(find.text('Account 2'), findsNothing);
  });

  testWidgets('account discovery modal removes toggled off candidates', (
    tester,
  ) async {
    List<int>? selected;

    await tester.pumpWidget(
      _modalHarness(onConfirm: (value) => selected = value),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_row_1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
    );

    expect(selected, [2]);
  });

  testWidgets('account discovery modal blocks empty selection when required', (
    tester,
  ) async {
    List<int>? selected;

    await tester.pumpWidget(
      _modalHarness(
        allowEmptySelection: false,
        onConfirm: (value) => selected = value,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_row_1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_row_2')),
    );
    await tester.tap(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
    );

    expect(selected, isNull);
  });

  testWidgets('account discovery modal action buttons split available width', (
    tester,
  ) async {
    await tester.pumpWidget(_modalHarness(onConfirm: (_) {}));

    final cancelSize = tester.getSize(
      find.descendant(
        of: find.byKey(
          const ValueKey('import_account_discovery_cancel_button'),
        ),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final confirmSize = tester.getSize(
      find.descendant(
        of: find.byKey(
          const ValueKey('import_account_discovery_confirm_button'),
        ),
        matching: find.byType(AnimatedContainer),
      ),
    );

    expect((cancelSize.width - confirmSize.width).abs(), lessThan(0.1));
    expect(cancelSize.width, greaterThan(160));
  });

  testWidgets('account discovery modal updates transparent balance previews', (
    tester,
  ) async {
    final account1Balance = Completer<BigInt>();
    final account2Balance = Completer<BigInt>();

    await tester.pumpWidget(
      _modalHarness(
        onConfirm: (_) {},
        loadTransparentBalance: (account) {
          return switch (account.zip32AccountIndex) {
            1 => account1Balance.future,
            2 => account2Balance.future,
            _ => Future.error(StateError('unexpected account')),
          };
        },
      ),
    );

    expect(find.text('Transparent'), findsNWidgets(2));
    expect(find.text('Loading'), findsNWidgets(2));

    account1Balance.complete(BigInt.from(123456789));
    await tester.pump();

    expect(find.text('1.2345 ZEC'), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);

    account2Balance.completeError(Exception('utxo unavailable'));
    await tester.pump();
    await tester.pump();

    expect(find.text('-'), findsOneWidget);
  });
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1512, 982));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _birthdayHarness({
  ImportBirthdayArgs args = const ImportBirthdayArgs(mnemonic: 'test mnemonic'),
  RpcEndpointFailoverNotifier Function()? failoverBuilder,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      rpcEndpointFailoverProvider.overrideWith(
        failoverBuilder ?? _FakeRpcEndpointFailoverNotifier.new,
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
        child: Material(
          type: MaterialType.transparency,
          child: AppTheme(
            data: AppThemeData.light,
            child: ImportWalletBirthdayScreen(args: args),
          ),
        ),
      ),
    ),
  );
}

rust_wallet.SoftwareWalletImportDiscoveryResult _discovery(
  rust_wallet.SoftwareAccountDiscoveryStatus status, {
  List<rust_wallet.SoftwareWalletDiscoveredAccount> accounts = const [],
}) {
  return rust_wallet.SoftwareWalletImportDiscoveryResult(
    primaryAccountAlreadyExists: false,
    accounts: accounts,
    status: status,
  );
}

Future<void> _submitWithDiscovery(
  WidgetTester tester,
  rust_wallet.SoftwareWalletImportDiscoveryResult discovery, {
  required ValueChanged<CustomiseAccountArgs> onCustomiseArgs,
  _FailingImportAccountNotifier? accountNotifier,
}) async {
  await _setDesktopSurface(tester);
  await tester.pumpWidget(
    _birthdayRouterHarness(
      args: const ImportBirthdayArgs(
        mnemonic: 'test mnemonic',
        initialBirthdayHeight: 1000000,
      ),
      accountNotifier:
          accountNotifier ??
          _FailingImportAccountNotifier(discovery: discovery),
      onCustomiseArgs: onCustomiseArgs,
    ),
  );
  await tester.pump();
  await tester.pump();

  await tester.tap(find.byKey(const ValueKey('import_birthday_submit_button')));
  await tester.pump();
  await tester.pump();
}

Widget _birthdayRouterHarness({
  required ImportBirthdayArgs args,
  _FailingImportAccountNotifier? accountNotifier,
  ValueChanged<CustomiseAccountArgs>? onCustomiseArgs,
}) {
  final router = GoRouter(
    initialLocation: '/import/birthday',
    routes: [
      GoRoute(
        path: '/import/birthday',
        builder: (_, _) => ImportWalletBirthdayScreen(args: args),
      ),
      GoRoute(path: '/import', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/import/set-password',
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/import/customise-account',
        builder: (_, state) {
          final args = state.extra as CustomiseAccountArgs;
          expect(args.flow, SetPasswordFlow.importWallet);
          expect(args.setupArgs.importBirthdayHeight, 1000000);
          onCustomiseArgs?.call(args);
          return const Text('Customise route');
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appSecurityProvider.overrideWith(_ConfiguredAppSecurityNotifier.new),
      accountProvider.overrideWith(
        () =>
            accountNotifier ??
            _FailingImportAccountNotifier(
              discovery: _discovery(
                rust_wallet.SoftwareAccountDiscoveryStatus.completed,
              ),
            ),
      ),
      syncProvider.overrideWith(_NoopSyncNotifier.new),
      rpcEndpointFailoverProvider.overrideWith(
        _FakeRpcEndpointFailoverNotifier.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
        child: Material(
          type: MaterialType.transparency,
          child: AppTheme(
            data: AppThemeData.light,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

Widget _modalHarness({
  bool allowEmptySelection = true,
  int bip44CoinType = 133,
  ImportAccountTransparentBalanceLoader? loadTransparentBalance,
  required ValueChanged<List<int>> onConfirm,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1)),
      child: AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              ImportAccountDiscoveryModal(
                accounts: const [
                  rust_wallet.SoftwareWalletDiscoveredAccount(
                    zip32AccountIndex: 1,
                    firstTransparentAddress:
                        't1VzLrfU8ZRs3xEGzR84xHWL2QK7C9Tt6yV',
                  ),
                  rust_wallet.SoftwareWalletDiscoveredAccount(
                    zip32AccountIndex: 2,
                    firstTransparentAddress:
                        't1UhrwzXxQBmduARnkbYqkKFSUMN6VAx9QS',
                  ),
                ],
                allowEmptySelection: allowEmptySelection,
                bip44CoinType: bip44CoinType,
                loadTransparentBalance:
                    loadTransparentBalance ?? ((_) async => BigInt.zero),
                onConfirm: onConfirm,
                onCancel: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

MouseCursor _cursorForText(WidgetTester tester, String text) {
  final mouseRegion = find.ancestor(
    of: find.text(text),
    matching: find.byType(MouseRegion),
  );
  expect(mouseRegion, findsOneWidget);
  return tester.widget<MouseRegion>(mouseRegion).cursor;
}

ImportBirthdayMetadata _metadataFixture() {
  return ImportBirthdayMetadata(
    saplingActivationHeight: 419200,
    saplingActivationDate: DateTime(2016, 10, 28),
    tipHeight: 3336000,
    tipDate: DateTime(2026, 5, 11),
  );
}

class _FakeRpcEndpointFailoverNotifier extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return _metadataFixture() as T;
    }
    return action(state.current);
  }
}

class _PendingMetadataRpcEndpointFailoverNotifier
    extends RpcEndpointFailoverNotifier {
  _PendingMetadataRpcEndpointFailoverNotifier(this.metadata);

  final Future<ImportBirthdayMetadata> metadata;

  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return await metadata as T;
    }
    return action(state.current);
  }
}

class _ConfiguredAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }
}

class _FailingImportAccountNotifier extends AccountNotifier {
  _FailingImportAccountNotifier({required this.discovery});

  final rust_wallet.SoftwareWalletImportDiscoveryResult discovery;
  int discoveryCalls = 0;

  @override
  FutureOr<AccountState> build() {
    return const AccountState();
  }

  @override
  Future<rust_wallet.SoftwareWalletImportDiscoveryResult>
  discoverAdditionalSoftwareAccounts({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
  }) async {
    discoveryCalls++;
    return discovery;
  }

  @override
  Future<BigInt> previewSoftwareAccountTransparentBalance({
    required String mnemonic,
    required int accountIndex,
    String bip39Passphrase = '',
  }) async {
    return BigInt.zero;
  }

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = 'pfp-01',
    List<int> additionalAccountIndices = const [],
  }) async {
    throw Exception('This account is already in your wallet.');
  }
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => false;
}
