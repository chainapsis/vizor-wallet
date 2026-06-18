@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_account_discovery_sheet.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const _accounts = [
  rust_wallet.SoftwareWalletDiscoveredAccount(
    zip32AccountIndex: 1,
    firstTransparentAddress: 't1mobileaccount000000000000000001',
  ),
  rust_wallet.SoftwareWalletDiscoveredAccount(
    zip32AccountIndex: 2,
    firstTransparentAddress: 't1mobileaccount000000000000000002',
  ),
];

Widget _app({
  required ValueChanged<List<int>> onConfirm,
  bool allowEmptySelection = true,
  MobileImportAccountTransparentBalanceLoader? loadTransparentBalance,
}) {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    home: MobileImportAccountDiscoverySheet(
      accounts: _accounts,
      allowEmptySelection: allowEmptySelection,
      bip44CoinType: 133,
      loadTransparentBalance:
          loadTransparentBalance ?? (_) async => BigInt.zero,
      onConfirm: onConfirm,
      onCancel: () {},
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('imports all candidates by default', (tester) async {
    List<int>? selected;

    await tester.pumpWidget(_app(onConfirm: (value) => selected = value));
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );

    expect(selected, [1, 2]);
  });

  testWidgets('labels candidates by BIP44 path', (tester) async {
    await tester.pumpWidget(_app(onConfirm: (_) {}));

    expect(find.text("m/44'/133'/1'/..."), findsOneWidget);
    expect(find.text("m/44'/133'/2'/..."), findsOneWidget);
  });

  testWidgets('removes toggled off candidates', (tester) async {
    List<int>? selected;

    await tester.pumpWidget(_app(onConfirm: (value) => selected = value));
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_row_1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );

    expect(selected, [2]);
  });

  testWidgets('blocks empty selection when required', (tester) async {
    List<int>? selected;

    await tester.pumpWidget(
      _app(allowEmptySelection: false, onConfirm: (value) => selected = value),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_row_1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_row_2')),
    );
    await tester.pump();

    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_account_discovery_confirm')),
    );
    expect(selected, isNull);
  });

  testWidgets('updates transparent balance previews', (tester) async {
    final account1Balance = Completer<BigInt>();
    final account2Balance = Completer<BigInt>();

    await tester.pumpWidget(
      _app(
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
    await tester.pump();

    expect(find.text('Transparent'), findsNWidgets(2));
    expect(find.text('Loading'), findsNWidgets(2));

    account1Balance.complete(BigInt.from(123456789));
    await tester.pump();
    await tester.pump();

    expect(find.text('1.2345 ZEC'), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);

    account2Balance.completeError(Exception('utxo unavailable'));
    await tester.pump();
    await tester.pump();

    expect(find.text('-'), findsOneWidget);
  });
}
