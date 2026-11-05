import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/send/services/recent_send_recipients.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

const _account = 'account-1';
const _otherAccount = 'account-2';
const _friend = 'u1friend0000000000000000000000000000000000';
const _shop = 't1shop00000000000000000000000000000';
const _ownActive = 'u1activeaccount00000000000000000000000000';
const _ownOther = 'u1otheraccount000000000000000000000000000';

SendRecentRecipient _shielded(String address) =>
    SendRecentRecipient(address: address, isShielded: true);

List<String> _addresses(List<SendRecentRecipient> recents) => [
  for (final recent in recents) recent.address,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore secureStore;
  late SendRecentRecipientStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStore = AppSecureStore.instance;
    await secureStore.deleteAll();
    store = AppSecureStoreSendRecentRecipientStore(secureStore);
  });

  tearDown(() async {
    await secureStore.deleteAll();
  });

  group('AppSecureStoreSendRecentRecipientStore', () {
    test('keeps one row per address, newest first', () async {
      await store.record(accountUuid: _account, recipient: _shielded(_friend));
      await store.record(
        accountUuid: _account,
        recipient: const SendRecentRecipient(address: _shop, isShielded: false),
      );
      await store.record(
        accountUuid: _account,
        recipient: _shielded(' $_friend '),
      );

      final recents = await store.load(accountUuid: _account);
      expect(_addresses(recents), [_friend, _shop]);
      expect(recents.last.isShielded, isFalse);
    });

    test('keeps each account separate and deletes one account', () async {
      await store.record(accountUuid: _account, recipient: _shielded(_friend));
      await store.record(
        accountUuid: _otherAccount,
        recipient: _shielded(_shop),
      );

      await store.deleteForAccount(accountUuid: _otherAccount);

      expect(_addresses(await store.load(accountUuid: _account)), [_friend]);
      expect(await store.load(accountUuid: _otherAccount), isEmpty);
    });

    test('keeps the newest 20 recipients', () async {
      for (var index = 0; index < 25; index++) {
        await store.record(
          accountUuid: _account,
          recipient: _shielded('u1recipient$index'),
        );
      }

      final recents = await store.load(accountUuid: _account);
      expect(recents, hasLength(20));
      expect(recents.first.address, 'u1recipient24');
      expect(recents.last.address, 'u1recipient5');
    });

    test('concurrent records keep every recipient', () async {
      await Future.wait([
        for (var index = 0; index < 5; index++)
          store.record(
            accountUuid: _account,
            recipient: _shielded('u1recipient$index'),
          ),
      ]);

      expect(await store.load(accountUuid: _account), hasLength(5));
    });

    test('unreadable data reads as empty and is replaced', () async {
      final key = sendRecentRecipientStorageKeyForTest(_account);
      await secureStore.writeString(key, '{not json');
      expect(await store.load(accountUuid: _account), isEmpty);

      await store.record(accountUuid: _account, recipient: _shielded(_friend));
      expect(_addresses(await store.load(accountUuid: _account)), [_friend]);
    });

    test('a newer version is neither read nor overwritten', () async {
      final key = sendRecentRecipientStorageKeyForTest(_account);
      final newer = jsonEncode({'version': 2, 'recipients': <Object>[]});
      await secureStore.writeString(key, newer);

      await store.record(accountUuid: _account, recipient: _shielded(_friend));

      expect(await store.load(accountUuid: _account), isEmpty);
      expect(await secureStore.readString(key), newer);
    });
  });

  group('visibleSendRecentRecipients', () {
    test('hides the active account and keeps other own accounts', () {
      final visible = visibleSendRecentRecipients(
        stored: [
          _shielded(_friend),
          _shielded(_ownActive),
          _shielded(_ownOther),
        ],
        accountUuid: _account,
        ownAccounts: const {
          _ownActive: AccountInfo(uuid: _account, name: 'Main', order: 0),
          _ownOther: AccountInfo(
            uuid: _otherAccount,
            name: 'Savings',
            order: 1,
          ),
        },
      );

      expect(_addresses(visible), [_friend, _ownOther]);
    });

    test('shows at most five recipients', () {
      final visible = visibleSendRecentRecipients(
        stored: [
          for (var index = 0; index < 8; index++)
            _shielded('u1recipient$index'),
        ],
        accountUuid: _account,
        ownAccounts: const {},
      );

      expect(visible, hasLength(kSendRecentRecipientLimit));
      expect(visible.first.address, 'u1recipient0');
    });
  });

  group('recentSendRecipientsProvider', () {
    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [sendRecentRecipientStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('reloads when the revision is bumped', () async {
      final read = container();
      final subscription = read.listen(
        recentSendRecipientsProvider(_account),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        await read.read(recentSendRecipientsProvider(_account).future),
        isEmpty,
      );

      await store.record(accountUuid: _account, recipient: _shielded(_friend));
      read.read(sendRecentRecipientsRevisionProvider.notifier).bump();

      expect(
        _addresses(
          await read.read(recentSendRecipientsProvider(_account).future),
        ),
        [_friend],
      );
    });
  });
}
