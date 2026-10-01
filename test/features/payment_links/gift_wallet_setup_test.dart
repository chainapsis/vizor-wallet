import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_wallet_setup.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_links_screen_support.dart' show incomingLink;

void main() {
  late _Security security;
  late _Accounts accounts;
  final events = <String>[];

  Future<String> setUp(
    WidgetTester tester, {
    Object? creationError,
    bool prepareFails = false,
    bool cleanupFails = false,
  }) async {
    events.clear();
    security = _Security(events, prepareFails: prepareFails);
    accounts = _Accounts(
      events,
      creationError: creationError,
      cleanupFails: cleanupFails,
    );
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSecurityProvider.overrideWith(() => security),
          accountProvider.overrideWith(() => accounts),
          syncProvider.overrideWith(_IdleSync.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    return setUpGiftCardWallet(
      widgetRef,
      passcode: '135790',
      link: incomingLink,
      accountName: 'My gift wallet',
      profilePictureId: 'pfp-11',
    );
  }

  testWidgets(
    'commits only after wallet and card persistence, then clears the journal',
    (tester) async {
      expect(await setUp(tester), 'gift-account');
      expect(events, [
        'prepare',
        'create and save',
        'commit',
        'cleanup gift-account',
      ]);
      expect(security.state.isPasswordConfigured, isTrue);
    },
  );

  testWidgets('a failed prepare never starts account creation', (tester) async {
    await expectLater(
      () => setUp(tester, prepareFails: true),
      throwsStateError,
    );
    expect(events, ['prepare']);
  });

  for (final error in [
    WalletCreationCurrentBlockHeightException(StateError('offline')),
    WalletAccountStateUncertainException(StateError('DB cannot be listed')),
  ]) {
    testWidgets(
      'a pre-account failure rolls the passcode back: ${error.runtimeType}',
      (tester) async {
        await expectLater(
          () => setUp(tester, creationError: error),
          throwsA(same(error)),
        );
        expect(events, ['prepare', 'create and save', 'rollback']);
        expect(security.state.isPasswordConfigured, isFalse);
      },
    );
  }

  for (final error in [
    GiftClaimAccountCreatedException('gift-account', StateError('save failed')),
    GiftClaimAccountCreatedException(null, StateError('outcome unknown')),
  ]) {
    testWidgets(
      'an existing or uncertain account preserves its credential: ${error.runtimeType} ${error.toString()}',
      (tester) async {
        await expectLater(
          () => setUp(tester, creationError: error),
          throwsA(same(error)),
        );
        expect(events, ['prepare', 'create and save', 'commit']);
        expect(security.state.isPasswordConfigured, isTrue);
      },
    );
  }

  testWidgets(
    'a journal cleanup failure keeps the successfully created wallet',
    (tester) async {
      expect(await setUp(tester, cleanupFails: true), 'gift-account');
      expect(events, [
        'prepare',
        'create and save',
        'commit',
        'cleanup gift-account',
      ]);
      expect(security.state.isPasswordConfigured, isTrue);
      expect(accounts.state.value!.activeAccountUuid, 'gift-account');
    },
  );
}

class _Security extends AppSecurityNotifier {
  _Security(this.events, {required this.prepareFails});
  final List<String> events;
  final bool prepareFails;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> prepareGiftWalletPasswordSetup(String password) async {
    events.add('prepare');
    if (prepareFails) throw StateError('prepare failed');
  }

  @override
  void commitPasswordSetup() {
    events.add('commit');
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async => events.add('rollback');
}

class _Accounts extends AccountNotifier {
  _Accounts(this.events, {this.creationError, required this.cleanupFails});
  final List<String> events;
  final Object? creationError;
  final bool cleanupFails;

  @override
  AccountState build() => const AccountState();

  @override
  Future<String> createGiftClaimAccount({
    required String name,
    required String profilePictureId,
    required VizorPaymentLink link,
  }) async {
    events.add('create and save');
    if (creationError case final error?) throw error;
    state = AsyncData(
      AccountState(
        accounts: [AccountInfo(uuid: 'gift-account', name: name, order: 0)],
        activeAccountUuid: 'gift-account',
      ),
    );
    return 'gift-account';
  }

  @override
  Future<void> clearPendingGiftAccountSetup({
    required String accountUuid,
  }) async {
    events.add('cleanup $accountUuid');
    if (cleanupFails) throw StateError('cleanup failed');
  }
}

class _IdleSync extends FakeSyncNotifier {
  _IdleSync() : super(SyncState());

  @override
  bool needsPauseForWalletMutation() => false;
}
