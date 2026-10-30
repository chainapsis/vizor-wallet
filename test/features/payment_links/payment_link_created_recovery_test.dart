import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_cards_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_reconciler.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_gift_link_rust_api.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: FakeGiftLinkRustApi()));
  tearDownAll(RustLib.dispose);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<({ProviderContainer container, PaymentLinkRecoveryStore store})>
  fixture(Future<void> Function() lookup, {int height = 200}) async {
    final store = PaymentLinkRecoveryStore(_CreatedStorage());
    await store.saveDraft(
      link: incomingLink,
      sourceAccountUuid: 'account-1',
      claimFeeReserveZatoshi: BigInt.from(10000),
    );
    await store.markPrepared(
      address: incomingLink.address,
      fundingTxid: 'funding',
      expiryHeight: 120,
    );
    final reconciler = PaymentLinkRecoveryReconciler(
      store,
      loadCurrentHeight: () async => BigInt.from(height),
      loadScannedHeight: () async => BigInt.from(height),
      loadTransactionsByAccount: (_) async {
        await lookup();
        return const <String, List<rust_sync.TransactionInfo>>{};
      },
      loadLinkFundingHistory: (_) async => const [],
    );
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_Security.new),
        accountProvider.overrideWith(_Accounts.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
        paymentLinkRecoveryStoreProvider.overrideWithValue(store),
        paymentLinkReceivedStoreProvider.overrideWithValue(
          PaymentLinkReceivedStore(_ReceivedStorage()),
        ),
        paymentLinkRecoveryReconcilerProvider.overrideWithValue(reconciler),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    return (container: container, store: store);
  }

  testWidgets('entry reads locally without running prepared-card lookups', (
    tester,
  ) async {
    var lookups = 0;
    final f = await fixture(() async {
      lookups++;
    });
    final snapshot = await f.container.read(paymentLinkCardsLoaderProvider)();
    expect(snapshot.created, hasLength(1));
    expect(snapshot.created.single.state, PaymentLinkRecoveryState.draft);
    expect(lookups, 0);
    expect(await f.store.load(), hasLength(1));
  });

  testWidgets('concurrent created-card recovery shares the chain lookup', (
    tester,
  ) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var lookups = 0;
    final f = await fixture(() async {
      lookups++;
      entered.complete();
      await release.future;
    });
    final service = f.container.read(paymentLinkServiceProvider);
    final first = service.recoverCreatedLinks();
    final second = service.recoverCreatedLinks();
    expect(identical(first, second), isTrue);
    await entered.future;
    expect(lookups, 1);
    release.complete();
    expect(await first, isEmpty); // The draft has expired.
    expect(await second, isEmpty);
  });

  testWidgets('recovery publishes cards created and shared during a lookup', (
    tester,
  ) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final f = await fixture(() async {
      entered.complete();
      await release.future;
    }, height: 100);
    final recovery = f.container
        .read(paymentLinkServiceProvider)
        .recoverCreatedLinks();
    await entered.future;
    await f.store.markFunded(
      address: incomingLink.address,
      fundingTxids: 'funding',
    );
    await f.store.markShared(address: incomingLink.address);
    await f.store.saveDraft(
      link: otherAccountLink,
      sourceAccountUuid: 'account-1',
      claimFeeReserveZatoshi: BigInt.from(10000),
    );
    release.complete();
    final records = await recovery;
    expect(records, hasLength(2));
    expect(
      records.firstWhere((r) => r.link.address == incomingLink.address).state,
      PaymentLinkRecoveryState.shared,
    );
    expect(
      records.any((r) => r.link.address == otherAccountLink.address),
      isTrue,
    );
  });

  for (final lock in [false, true]) {
    testWidgets(
      'late lookup cannot mutate after ${lock ? 'lock' : 'reset fence'}',
      (tester) async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final f = await fixture(() async {
          entered.complete();
          await release.future;
        });
        final recovery = f.container
            .read(paymentLinkServiceProvider)
            .recoverCreatedLinks();
        final interrupted = expectLater(
          recovery,
          throwsA(isA<GiftCardPreparationInterrupted>()),
        );
        await entered.future;
        var drained = false;
        Future<void>? drain;
        if (lock) {
          f.container.read(appSecurityProvider.notifier).lock();
        } else {
          drain = f.container
              .read(paymentLinkClaimLifecycleRegistryProvider)
              .quiesceAndDrain()
              .then((_) => drained = true);
        }
        await tester.pump();
        expect(drained, isFalse);
        release.complete();
        await interrupted;
        await drain;
        expect(
          await f.store.load(),
          hasLength(1),
        ); // No expiry removal after pause.
        if (!lock) expect(drained, isTrue);
      },
    );
  }
}

class _Accounts extends AccountNotifier {
  @override
  Future<AccountState> build() async => paymentLinksAccountState;
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}

class _CreatedStorage implements PaymentLinkRecoveryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

class _ReceivedStorage implements PaymentLinkReceivedStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}
