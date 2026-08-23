import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/create/customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_chrome.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';

void main() {
  testWidgets('Ledger birthday continues with a height callback', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    int? selectedHeight;

    await tester.pumpWidget(
      _harness(
        ImportWalletBirthdayScreen.ledger(
          onBirthdaySelected: (height) async {
            selectedHeight = height;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wallet Birthday Height'), findsOneWidget);
    await tester.tap(find.text('Enter the block height'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '2500000');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('import_birthday_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(selectedHeight, 2500000);
  });

  testWidgets('Ledger customisation returns name and avatar through callback', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    String? selectedName;
    String? selectedProfilePictureId;

    await tester.pumpWidget(
      _harness(
        CustomiseAccountScreen.ledger(
          ledgerBackTarget: const OnboardingBackTarget.route(
            label: 'Wallet Birthday Height',
            routePath: '/onboarding/ledger/birthday',
          ),
          onFinish: (name, profilePictureId) async {
            selectedName = name;
            selectedProfilePictureId = profilePictureId;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('customise_account_name_field')),
      'Ledger savings',
    );
    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pumpAndSettle();

    expect(selectedName, 'Ledger savings');
    expect(selectedProfilePictureId, isNotEmpty);
  });
}

Widget _harness(Widget screen) {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [GoRoute(path: '/test', builder: (_, _) => screen)],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      rpcEndpointFailoverProvider.overrideWith(
        _FakeRpcEndpointFailoverNotifier.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async => tester.binding.setSurfaceSize(null));
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
      return ImportBirthdayMetadata(
            saplingActivationHeight: 419200,
            saplingActivationDate: DateTime(2016, 10, 28),
            tipHeight: 3336000,
            tipDate: DateTime(2026, 5, 11),
          )
          as T;
    }
    return action(state.current);
  }
}
