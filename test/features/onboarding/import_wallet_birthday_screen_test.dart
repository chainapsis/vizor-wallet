import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_account_discovery_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  testWidgets('birthday tab labels show a click cursor', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(_birthdayHarness());
    await tester.pump();

    expect(_cursorForText(tester, 'Enter the Date'), SystemMouseCursors.click);
    expect(
      _cursorForText(tester, 'Enter the Block Height'),
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
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1512, 982));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _birthdayHarness({
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
        child: AppTheme(
          data: AppThemeData.light,
          child: const ImportWalletBirthdayScreen(
            args: ImportBirthdayArgs(mnemonic: 'test mnemonic'),
          ),
        ),
      ),
    ),
  );
}

Widget _modalHarness({
  bool allowEmptySelection = true,
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
