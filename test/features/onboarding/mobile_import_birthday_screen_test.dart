@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart'
    show ImportBirthdayCalendarPanel;
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/import/birthday',
  initialAccountState: const AccountState(accounts: []),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app({Future<void> Function(int height)? onHeightConfirmed}) {
  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: MobileImportBirthdayScreen(
        args: const ImportBirthdayArgs(mnemonic: 'stub mnemonic'),
        onHeightConfirmed: onHeightConfirmed,
        loadChainMetadata: false,
      ),
    ),
  );
}

Widget _routerApp({
  required _RecordingAccountNotifier accountNotifier,
  required AppSecurityNotifier appSecurityNotifier,
  ValueChanged<SetPasswordScreenArgs>? onPasscodeArgs,
}) {
  final router = GoRouter(
    initialLocation: '/import/birthday',
    routes: [
      GoRoute(
        path: '/import/birthday',
        builder: (_, _) => const MobileImportBirthdayScreen(
          args: ImportBirthdayArgs(mnemonic: 'stub mnemonic'),
          loadChainMetadata: false,
        ),
      ),
      GoRoute(
        path: '/onboarding/set-passcode',
        builder: (_, state) {
          final args = state.extra as SetPasswordScreenArgs;
          onPasscodeArgs?.call(args);
          return const Text('passcode route');
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(() => accountNotifier),
      appSecurityProvider.overrideWith(() => appSecurityNotifier),
      syncProvider.overrideWith(() => _NoopSyncNotifier()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

Future<void> _enterHeightAndContinue(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('mobile_import_birthday_height')),
    '2500000',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_continue')),
  );
  await tester.pumpAndSettle();
}

const _discoveredAccounts = [
  rust_wallet.SoftwareWalletDiscoveredAccount(
    zip32AccountIndex: 1,
    firstTransparentAddress: 't1mobilebirthday0000000000000001',
  ),
  rust_wallet.SoftwareWalletDiscoveredAccount(
    zip32AccountIndex: 2,
    firstTransparentAddress: 't1mobilebirthday0000000000000002',
  ),
];

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('continue stays disabled until a plausible height is typed', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    AppButton continueButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await tester.pump();

    expect(continueButton().onPressed, isNull);

    final heightField = find.byKey(
      const ValueKey('mobile_import_birthday_height'),
    );

    // Below the Sapling activation floor → still disabled.
    await tester.enterText(heightField, '1');
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    // A plausible mainnet height enables the action.
    await tester.enterText(heightField, '2500000');
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);

    // Clearing it disables again.
    await tester.enterText(heightField, '');
    await tester.pump();
    expect(continueButton().onPressed, isNull);
  });

  testWidgets('the height field only accepts digits', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await tester.pump();

    final heightField = find.byKey(
      const ValueKey('mobile_import_birthday_height'),
    );
    await tester.enterText(heightField, '25a.b00');
    await tester.pump();
    expect(tester.widget<TextField>(heightField).controller!.text, '2500');
  });

  testWidgets('skip asks before importing from the earliest supported height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);

    int? confirmedHeight;
    final expectedHeight = defaultRpcEndpointConfig(
      'main',
    ).network.saplingActivationHeight;

    await tester.pumpWidget(
      _app(onHeightConfirmed: (height) async => confirmedHeight = height),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_import_birthday_skip')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_import_birthday_unknown_height_sheet')),
      findsOneWidget,
    );
    expect(find.text('Import from the earliest height?'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Import from the earliest height?'))
          .maxLines,
      2,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(
              const ValueKey('mobile_import_birthday_unknown_height_confirm'),
            ),
          )
          .variant,
      AppButtonVariant.primary,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(
              const ValueKey('mobile_import_birthday_unknown_height_cancel'),
            ),
          )
          .variant,
      AppButtonVariant.ghost,
    );
    expect(confirmedHeight, isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('mobile_import_birthday_unknown_height_cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_import_birthday_unknown_height_sheet')),
      findsNothing,
    );
    expect(confirmedHeight, isNull);

    await tester.tap(find.byKey(const ValueKey('mobile_import_birthday_skip')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_import_birthday_unknown_height_confirm'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('mobile_import_birthday_unknown_height_sheet')),
      findsNothing,
    );
    expect(confirmedHeight, expectedHeight);
  });

  testWidgets('the date field is not typeable and opens the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    AppButton continueButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );

    // Date mode is the default — no editable text exists in it, and the
    // large bottom action opens the calendar until a date has been selected.
    expect(find.byType(EditableText), findsNothing);
    expect(continueButton().onPressed, isNotNull);
    expect(find.text('Select date'), findsOneWidget);
    expect(find.text('I don’t remember'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_import_birthday_continue')),
          )
          .width,
      greaterThan(300),
    );
    expect(find.text('mm/dd/yyyy'), findsOneWidget);

    // The bottom primary action opens the calendar sheet.
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImportBirthdayCalendarPanel), findsOneWidget);

    // The sheet hugs the calendar instead of claiming the full
    // scroll-controlled height: panel + the AppSpacing.sm padding, plus
    // the modal base frame's bottom gap (AppSpacing.base) that floats the
    // card off the screen edge. No device safe-area inset in tests, so
    // the gap is the bare AppSpacing.base on both platform branches.
    final panelHeight = tester
        .getSize(find.byType(ImportBirthdayCalendarPanel))
        .height;
    final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
    expect(
      sheetHeight,
      closeTo(panelHeight + AppSpacing.sm * 2 + AppSpacing.base, 1.0),
    );

    // The panel is its own card, so the sheet surface stays invisible —
    // only the scrim and the calendar render.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
      const Color(0x00000000),
    );

    // Selecting today's enabled day fills the field and enables continue.
    final todayLabel = DateTime.now().day.toString();
    final enabledToday = find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is GestureDetector && widget.onTap != null,
          ),
          matching: find.text(todayLabel),
        )
        .first;
    await tester.tap(enabledToday);
    await tester.pumpAndSettle();
    expect(find.byType(ImportBirthdayCalendarPanel), findsNothing);
    expect(continueButton().onPressed, isNotNull);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('mm/dd/yyyy'), findsNothing);
  });

  testWidgets('tapping the date field still opens the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_import_birthday_date')));
    await tester.pumpAndSettle();

    expect(find.byType(ImportBirthdayCalendarPanel), findsOneWidget);
  });

  testWidgets('busy skip action remains text-only', (tester) async {
    final submitCompleter = Completer<void>();

    await tester.pumpWidget(
      _app(onHeightConfirmed: (_) => submitCompleter.future),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_birthday_height')),
      '2500000',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );
    await tester.pump();

    final skipAction = find.byKey(
      const ValueKey('mobile_import_birthday_skip'),
    );
    expect(find.text('Importing wallet...'), findsOneWidget);
    expect(skipAction, findsOneWidget);
    expect(
      find.descendant(of: skipAction, matching: find.byType(AppButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: skipAction, matching: find.byType(DecoratedBox)),
      findsNothing,
    );

    submitCompleter.complete();
  });

  testWidgets('passes discovered account selection to passcode route', (
    tester,
  ) async {
    SetPasswordScreenArgs? passcodeArgs;
    final accountNotifier = _RecordingAccountNotifier(
      discovery: const rust_wallet.SoftwareWalletImportDiscoveryResult(
        primaryAccountAlreadyExists: false,
        accounts: _discoveredAccounts,
      ),
    );

    await tester.pumpWidget(
      _routerApp(
        accountNotifier: accountNotifier,
        appSecurityNotifier: _StaticAppSecurityNotifier(
          isPasswordConfigured: false,
        ),
        onPasscodeArgs: (args) => passcodeArgs = args,
      ),
    );
    await tester.pump();

    await _enterHeightAndContinue(tester);
    expect(find.text('Additional accounts found'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('passcode route'), findsOneWidget);
    expect(passcodeArgs?.selectedAdditionalAccountIndices, [1, 2]);
    expect(accountNotifier.importedAdditionalAccountIndices, isNull);
  });

  testWidgets(
    'returning from passcode after empty discovery restores birthday',
    (tester) async {
      final accountNotifier = _RecordingAccountNotifier(
        discovery: const rust_wallet.SoftwareWalletImportDiscoveryResult(
          primaryAccountAlreadyExists: false,
          accounts: [],
        ),
      );

      await tester.pumpWidget(
        _routerApp(
          accountNotifier: accountNotifier,
          appSecurityNotifier: _StaticAppSecurityNotifier(
            isPasswordConfigured: false,
          ),
        ),
      );
      await tester.pump();

      await _enterHeightAndContinue(tester);
      expect(find.text('passcode route'), findsOneWidget);

      final context = tester.element(find.text('passcode route'));
      GoRouter.of(context).pop();
      await tester.pumpAndSettle();

      expect(
        find.text('Around when did you create your wallet?'),
        findsOneWidget,
      );
      expect(find.text('Checking accounts...'), findsNothing);
      final continueButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('mobile_import_birthday_continue')),
      );
      expect(continueButton.onPressed, isNotNull);
    },
  );

  testWidgets('imports selected discovered accounts when passcode exists', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier(
      discovery: const rust_wallet.SoftwareWalletImportDiscoveryResult(
        primaryAccountAlreadyExists: false,
        accounts: _discoveredAccounts,
      ),
    );

    await tester.pumpWidget(
      _routerApp(
        accountNotifier: accountNotifier,
        appSecurityNotifier: _StaticAppSecurityNotifier(
          isPasswordConfigured: true,
        ),
      ),
    );
    await tester.pump();

    await _enterHeightAndContinue(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_row_1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.importedMnemonic, 'stub mnemonic');
    expect(accountNotifier.importedBirthdayHeight, 2500000);
    expect(accountNotifier.importedAdditionalAccountIndices, [2]);
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('cancelling discovery keeps the import on the birthday screen', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier(
      discovery: const rust_wallet.SoftwareWalletImportDiscoveryResult(
        primaryAccountAlreadyExists: false,
        accounts: _discoveredAccounts,
      ),
    );

    await tester.pumpWidget(
      _routerApp(
        accountNotifier: accountNotifier,
        appSecurityNotifier: _StaticAppSecurityNotifier(
          isPasswordConfigured: true,
        ),
      ),
    );
    await tester.pump();

    await _enterHeightAndContinue(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_cancel')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Around when did you create your wallet?'),
      findsOneWidget,
    );
    expect(accountNotifier.importedAdditionalAccountIndices, isNull);
  });
}

class _RecordingAccountNotifier extends AccountNotifier {
  _RecordingAccountNotifier({required this.discovery});

  final rust_wallet.SoftwareWalletImportDiscoveryResult discovery;
  String? importedMnemonic;
  int? importedBirthdayHeight;
  List<int>? importedAdditionalAccountIndices;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<rust_wallet.SoftwareWalletImportDiscoveryResult>
  discoverAdditionalSoftwareAccounts({
    required String mnemonic,
    int? birthdayHeight,
  }) async {
    return discovery;
  }

  @override
  Future<BigInt> previewSoftwareAccountTransparentBalance({
    required String mnemonic,
    required int accountIndex,
  }) async {
    return BigInt.zero;
  }

  @override
  Future<void> importAccount({
    required String mnemonic,
    int? birthdayHeight,
    String? name,
    List<int> additionalAccountIndices = const [],
  }) async {
    importedMnemonic = mnemonic;
    importedBirthdayHeight = birthdayHeight;
    importedAdditionalAccountIndices = additionalAccountIndices;
  }
}

class _StaticAppSecurityNotifier extends AppSecurityNotifier {
  _StaticAppSecurityNotifier({required this.isPasswordConfigured});

  final bool isPasswordConfigured;

  @override
  AppSecurityState build() {
    return AppSecurityState(
      isPasswordConfigured: isPasswordConfigured,
      isUnlocked: true,
    );
  }
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => false;
}
