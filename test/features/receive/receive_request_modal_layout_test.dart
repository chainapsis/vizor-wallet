/// Whether the desktop request modal fits the windows the app actually opens.
///
/// The modal mounts inside the real `AppDesktopShell` here rather than in a
/// bare `SizedBox`, so the height it gets is the height the pane gets: the
/// window minus the shell's own margins. Both sizes are the ones the product
/// ships with — `windows/runner/main.cpp` opens at 1095x726, and
/// `AppLayoutMode.large.minimumSize` in `app_layout.dart` is the smallest
/// drag-resize the window allows.
///
/// A RenderFlex overflow throws in debug, so `tester.takeException()` being
/// null is the overflow assertion; the card-inside-viewport check is what
/// catches the softer failure the two-step split was for — a card that fits
/// only because the surface silently scrolled it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_card.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

/// The default window `windows/runner/main.cpp` opens.
const _defaultWindow = Size(1095, 726);

/// The smallest window `AppLayoutMode.large.minimumSize` allows.
const _minimumWindow = Size(1080, 720);

/// An amount whose USD conversion is seven figures, so the conversion row
/// under the field is as wide as it ever gets.
const _longAmount = '123456.12345678';

/// A memo at the ZIP-321 limit: the tallest step one can be.
final _longMessage = 'a memo that keeps going and going. ' * 14;

void main() {
  for (final size in const [_defaultWindow, _minimumWindow]) {
    testWidgets('the request modal fits at $size, both steps', (tester) async {
      await _pumpReceive(tester, size);

      await _openRequest(tester);
      _expectFits(tester, 'step one, empty');

      await _enterAmount(tester, '0.5');
      _expectFits(tester, 'step one, amount');

      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pump();
      _expectFits(tester, 'step two, shielded');

      await tester.tap(find.byKey(const ValueKey('request_modal_back')));
      await tester.pump();
      _expectFits(tester, 'step one, returned');
    });

    testWidgets('the request modal fits at $size with a long message', (
      tester,
    ) async {
      await _pumpReceive(tester, size);

      await _openRequest(tester);
      await _enterAmount(tester, _longAmount);
      _expectFits(tester, 'step one, long fiat');

      await tester.tap(find.byKey(const ValueKey('request_add_message_card')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('request_message_field')),
        _longMessage,
      );
      await tester.pump();
      _expectFits(tester, 'step one, message expanded');

      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pump();
      _expectFits(tester, 'step two, long request');
    });

    testWidgets('the request modal fits at $size for a transparent address', (
      tester,
    ) async {
      await _pumpReceive(tester, size);

      await tester.tap(find.text('Transparent'));
      await tester.pump();
      await tester.pump();

      await _openRequest(tester);
      await _enterAmount(tester, _longAmount);
      _expectFits(tester, 'transparent, step one');

      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pump();
      _expectFits(tester, 'transparent, step two');
    });
  }
}

/// No overflow, and the card is whole inside the pane rather than scrolled.
void _expectFits(WidgetTester tester, String state) {
  expect(tester.takeException(), isNull, reason: 'overflow at: $state');

  final card = tester.getRect(find.byType(AppModalCard));
  final surface = tester.getRect(find.byType(RequestAmountSurface));
  expect(
    card.height,
    lessThanOrEqualTo(surface.height),
    reason: 'the card outgrew its pane at: $state',
  );
  expect(
    card.top,
    greaterThanOrEqualTo(surface.top - 0.01),
    reason: 'the card is clipped at the top at: $state',
  );
  expect(
    card.bottom,
    lessThanOrEqualTo(surface.bottom + 0.01),
    reason: 'the card is clipped at the bottom at: $state',
  );
}

Future<void> _openRequest(WidgetTester tester) async {
  // The Receive screen's own fixed-coordinate content is taller than the
  // minimum window, so at that size its action column sits below the fold —
  // it scrolls there, which is the pane's business, not the modal's.
  final button = find.byKey(const ValueKey('receive_request_button'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

Future<void> _enterAmount(WidgetTester tester, String amount) async {
  await tester.enterText(
    find.byKey(const ValueKey('request_amount_field')),
    amount,
  );
  await tester.pump();
}

Future<void> _pumpReceive(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(_receiveHarness());
  await tester.pump();
  await tester.pump();
}

const _shieldedAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000000';
const _transparentAddress =
    't1testtransparentaddress111111111111111111111111111111111111';

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

Widget _receiveHarness({List<Override> extraOverrides = const []}) {
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
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            percentage: 1,
          ),
        ),
      ),
      receiveAddressServiceProvider.overrideWith(
        _FakeReceiveAddressService.new,
      ),
      zecLiveUsdUnitPriceProvider.overrideWithValue(70),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(super.ref);

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => currentShieldedAddress ?? _shieldedAddress;

  @override
  String? getCachedTransparentAddress(String accountUuid) =>
      _transparentAddress;

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async => _transparentAddress;

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async =>
      _shieldedAddress;
}
