/// Where the app-level payment-request card lands, and whether it fits.
///
/// The card is hosted above the router, so nothing in the route tree bounds
/// it: these tests mount the real desktop shell under it at the window sizes
/// `windows/runner/main.cpp` opens at (1095x726) and `app_layout.dart` allows
/// as the smallest drag-resize (1080x720), and assert both the pane-centered
/// geometry and the absence of any overflow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

/// The default window `windows/runner/main.cpp` opens.
const _defaultWindow = Size(1095, 726);

/// The smallest window `AppLayoutMode.large.minimumSize` allows.
const _minimumWindow = Size(1080, 720);

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

/// A 512-byte memo and an 80-character label: the widest a request can be.
final _longMessage = 'a memo that keeps going. ' * 20;
const _longLabel =
    'A payment requester with a name long enough to fill eighty characters '
    'exactly!!';

final _shortRequest = SendPrefillArgs(
  id: 'payment-uri-short',
  source: kPaymentUriPrefillSource,
  address: _address,
  amountText: '0.5',
  label: 'Coffee shop',
);

final _longRequest = SendPrefillArgs(
  id: 'payment-uri-long',
  source: kPaymentUriPrefillSource,
  address: _address,
  amountText: '123456.12345678',
  label: _longLabel,
  memoText: _longMessage,
  message: 'A note the requester attached to the link, kept local.',
);

void main() {
  testWidgets('the card centers on the content pane, not on the window', (
    tester,
  ) async {
    final container = await _pumpHost(tester, size: _defaultWindow);
    await _present(tester, container, _shortRequest);

    // The geometry the shell itself lays the pane out with.
    final paneLeft = appDesktopPaneLeftInset(kAppDesktopSidebarWidth);
    final paneWidth = _defaultWindow.width - paneLeft - kAppDesktopShellMargin;

    final card = find.byType(AppModalCard);
    expect(
      tester.getCenter(card).dx,
      moreOrLessEquals(paneLeft + paneWidth / 2, epsilon: 0.01),
    );
    // Not the window's center — that is what the sidebar was pushing it to.
    expect(
      tester.getCenter(card).dx,
      isNot(moreOrLessEquals(_defaultWindow.width / 2, epsilon: 1)),
    );
    // And it agrees with where the shell actually put the pane.
    expect(
      tester.getCenter(card).dx,
      moreOrLessEquals(
        tester.getCenter(find.byType(AppDesktopPane)).dx,
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('a card with no shell mounted still centers on the window', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      size: _defaultWindow,
      shell: false,
    );
    await _present(tester, container, _shortRequest);

    expect(
      tester.getCenter(find.byType(AppModalCard)).dx,
      moreOrLessEquals(_defaultWindow.width / 2, epsilon: 0.01),
    );
  });

  for (final size in const [_defaultWindow, _minimumWindow]) {
    testWidgets('the card fits at $size, plain and with long values', (
      tester,
    ) async {
      final container = await _pumpHost(tester, size: size);

      await _present(tester, container, _shortRequest);
      _expectFits(tester, size);

      container.read(paymentRequestFlowProvider.notifier).dismiss();
      await tester.pumpAndSettle();

      await _present(tester, container, _longRequest);
      _expectFits(tester, size);

      // The disclosures are what make the card grow past its own frame.
      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();
      _expectFits(tester, size);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('payment_request_memo')),
          matching: find.byType(ReviewListRow),
        ),
      );
      await tester.pumpAndSettle();
      _expectFits(tester, size);
    });
  }
}

/// No overflow, and the card is inside the window it was drawn in.
void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  final card = tester.getRect(find.byType(AppModalCard));
  expect(card.top, greaterThanOrEqualTo(-0.01));
  expect(card.bottom, lessThanOrEqualTo(window.height + 0.01));
  expect(card.left, greaterThanOrEqualTo(-0.01));
  expect(card.right, lessThanOrEqualTo(window.width + 0.01));
  expect(card.width, moreOrLessEquals(kPaymentRequestCardWidth, epsilon: 0.01));
}

Future<void> _present(
  WidgetTester tester,
  ProviderContainer container,
  SendPrefillArgs request,
) async {
  container
      .read(paymentRequestFlowProvider.notifier)
      .present(request, source: PaymentRequestSource.link);
  await tester.pumpAndSettle();
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  validateAddress: ({required String address}) async =>
      rust_sync.AddressValidationResult(isValid: true, addressType: 'unified'),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => SendReviewArgs(
        proposalId: BigInt.from(11),
        sendFlowId: sendFlowId,
        proposalAccountUuid: accountUuid,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
        isPaymentRequest: isPaymentRequest,
        requestedBy: requestedBy,
        requestedAmountZatoshi: requestedAmountZatoshi,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async {},
);

Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  required Size size,
  bool shell = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in ['/home', '/send', '/send/review'])
        GoRoute(
          path: path,
          builder: (_, _) => shell
              ? const AppDesktopShell(
                  sidebar: ColoredBox(color: Color(0xFF202020)),
                  pane: AppDesktopPane(child: SizedBox.expand()),
                )
              : const Scaffold(body: SizedBox.expand()),
        ),
    ],
  );
  addTearDown(router.dispose);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
        accountProvider.overrideWith(_FakeAccountNotifier.new),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              spendableBalance: BigInt.from(100000000),
            ),
          ),
        ),
        migrationSendGateProvider.overrideWithValue(false),
        zecHomeUsdUnitPriceProvider.overrideWithValue(null),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context, listen: false);
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => AppTheme(
              data: AppThemeData.light,
              child: PaymentRequestHost(router: router, child: child!),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
