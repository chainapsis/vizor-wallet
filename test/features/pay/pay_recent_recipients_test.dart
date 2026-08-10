import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/models/pay_recent_recipients.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const _evmA = '0x52908400098527886E0F7030069857D2E4169EE7';
const _evmB = '0x1111111111111111111111111111111111111111';
const _solana = '4Nd1mYQx4jJXAWe3zUKgnQz5pFa9qTqfjEBWWWk3tS9e';

SwapIntent _intent({
  required String id,
  required String? recipient,
  String sellAmount = '1 ZEC',
  String receiveEstimate = '10 USDC',
  SwapDirection direction = SwapDirection.zecToExternal,
  SwapAsset externalAsset = SwapAsset.usdc,
  SwapIntentStatus status = SwapIntentStatus.complete,
  String? depositTxHash,
  String? destinationChainTxHash,
  String? broadcastStatus,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? completedAt,
}) {
  return SwapIntent(
    id: id,
    pair: 'ZEC -> USDC',
    sellAmount: sellAmount,
    receiveEstimate: receiveEstimate,
    provider: 'NEAR Intents',
    status: status,
    nextAction: '',
    direction: direction,
    externalAsset: externalAsset,
    depositTxHash: depositTxHash,
    destinationChainTxHash: destinationChainTxHash,
    oneClickRecipient: recipient,
    broadcastStatus: broadcastStatus,
    createdAt: createdAt,
    updatedAt: updatedAt,
    completedAt: completedAt,
  );
}

void main() {
  group('payRecentRecipients', () {
    test(
      'keeps outgoing recipients valid on the pay network, newest first',
      () {
        final recents = payRecentRecipients(
          intents: [
            _intent(
              id: 'old',
              recipient: _evmA,
              createdAt: DateTime(2026, 7, 1),
            ),
            _intent(
              id: 'new',
              recipient: _evmB,
              sellAmount: '1.24 ZEC',
              receiveEstimate: ' ~24.0000 USDC ',
              createdAt: DateTime(2026, 7, 5),
            ),
            _intent(id: 'wrong-chain', recipient: _solana),
            _intent(
              id: 'inbound',
              recipient: _evmA,
              direction: SwapDirection.externalToZec,
              createdAt: DateTime(2026, 7, 8),
            ),
            _intent(id: 'no-recipient', recipient: null),
          ],
          network: AddressBookNetwork.ethereum,
          contacts: const [],
        );

        expect(recents.map((r) => r.address), [_evmB, _evmA]);
        expect(recents.first.amountText, '-24 USDC');
      },
    );

    test('keeps only completed or destination-chain-evidenced payouts', () {
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'failed',
            recipient: _evmB,
            status: SwapIntentStatus.failed,
            depositTxHash: 'failed-deposit',
            destinationChainTxHash: 'stale-failed-payout',
            updatedAt: DateTime(2026, 7, 9),
          ),
          _intent(
            id: 'refunded',
            recipient: _evmB,
            status: SwapIntentStatus.refunded,
            depositTxHash: 'refunded-deposit',
            updatedAt: DateTime(2026, 7, 8),
          ),
          _intent(
            id: 'expired',
            recipient: _evmB,
            status: SwapIntentStatus.expired,
            createdAt: DateTime(2026, 7, 7),
          ),
          _intent(
            id: 'unsent',
            recipient: _evmB,
            status: SwapIntentStatus.awaitingDeposit,
            createdAt: DateTime(2026, 7, 6),
          ),
          _intent(
            id: 'source-deposit-only',
            recipient: _evmB,
            status: SwapIntentStatus.processing,
            depositTxHash: 'zec-deposit-tx',
            updatedAt: DateTime(2026, 7, 6),
          ),
          _intent(
            id: 'payout-broadcast',
            recipient: _evmA,
            status: SwapIntentStatus.processing,
            receiveEstimate: '18.50 USDC',
            depositTxHash: 'zec-deposit-tx',
            destinationChainTxHash: 'usdc-payout-tx',
            createdAt: DateTime(2026, 7, 4),
            updatedAt: DateTime(2026, 7, 5),
          ),
        ],
        network: AddressBookNetwork.ethereum,
        contacts: const [],
      );

      expect(recents, hasLength(1));
      expect(recents.single.address, _evmA);
      expect(recents.single.amountText, '-18.5 USDC');
      expect(recents.single.lastUsedAt, DateTime(2026, 7, 5));
    });

    test('a newer failed attempt does not replace a completed recipient', () {
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'completed',
            recipient: _evmA,
            receiveEstimate: '12 USDC',
            completedAt: DateTime(2026, 7, 5),
          ),
          _intent(
            id: 'failed',
            recipient: _evmA,
            receiveEstimate: '99 USDC',
            status: SwapIntentStatus.failed,
            createdAt: DateTime(2026, 7, 8),
          ),
        ],
        network: AddressBookNetwork.ethereum,
        contacts: const [],
      );

      expect(recents, hasLength(1));
      expect(recents.single.amountText, '-12 USDC');
      expect(recents.single.lastUsedAt, DateTime(2026, 7, 5));
    });

    test('deduplicates by address keeping the most recent use', () {
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'older',
            recipient: _evmA,
            createdAt: DateTime(2026, 7, 1),
          ),
          _intent(
            id: 'newer',
            recipient: _evmA,
            createdAt: DateTime(2026, 7, 6),
            completedAt: DateTime(2026, 7, 7),
          ),
        ],
        network: AddressBookNetwork.ethereum,
        contacts: const [],
      );

      expect(recents, hasLength(1));
      expect(recents.single.lastUsedAt, DateTime(2026, 7, 7));
    });

    test('preserves case-distinct recipients on case-sensitive networks', () {
      final caseVariant = _solana.replaceFirst('N', 'n');
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'original',
            recipient: _solana,
            externalAsset: SwapAsset.sol,
            createdAt: DateTime(2026, 7, 1),
          ),
          _intent(
            id: 'case-variant',
            recipient: caseVariant,
            externalAsset: SwapAsset.sol,
            createdAt: DateTime(2026, 7, 2),
          ),
        ],
        network: AddressBookNetwork.solana,
        contacts: const [],
      );

      expect(recents.map((recent) => recent.address), [caseVariant, _solana]);
    });

    test('keeps only recipients from the selected rail', () {
      const dogecoinAddress = 'DExampleDogecoinRecipient';
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'ethereum',
            recipient: _evmA,
            externalAsset: SwapAsset.usdc,
          ),
          _intent(
            id: 'solana',
            recipient: _solana,
            externalAsset: SwapAsset.sol,
          ),
          _intent(
            id: 'dogecoin',
            recipient: dogecoinAddress,
            externalAsset: SwapAsset.doge,
          ),
        ],
        network: AddressBookNetwork.dogecoin,
        contacts: const [],
      );

      expect(recents.map((recent) => recent.address), [dogecoinAddress]);
    });

    test('treats EVM rails as compatible', () {
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'ethereum',
            recipient: _evmA,
            externalAsset: SwapAsset.usdc,
          ),
        ],
        network: AddressBookNetwork.base,
        contacts: const [],
      );

      expect(recents.map((recent) => recent.address), [_evmA]);
    });

    test('caps the list at the limit', () {
      final recents = payRecentRecipients(
        intents: [
          for (var i = 0; i < 9; i++)
            _intent(
              id: 'intent-$i',
              recipient: '0x${i.toString().padLeft(2, '0')}${'11' * 19}',
              createdAt: DateTime(2026, 7, 1 + i),
            ),
        ],
        network: AddressBookNetwork.ethereum,
        contacts: const [],
        limit: 5,
      );

      expect(recents, hasLength(5));
    });

    test('excludes saved contacts before applying the recent limit', () {
      const thirdAddress = '0x2222222222222222222222222222222222222222';
      final recents = payRecentRecipients(
        intents: [
          _intent(
            id: 'contact',
            recipient: _evmA,
            createdAt: DateTime(2026, 7, 3),
          ),
          _intent(
            id: 'recent-1',
            recipient: _evmB,
            createdAt: DateTime(2026, 7, 2),
          ),
          _intent(
            id: 'recent-2',
            recipient: thirdAddress,
            createdAt: DateTime(2026, 7, 1),
          ),
        ],
        network: AddressBookNetwork.ethereum,
        contacts: const [
          AddressBookContact(
            id: 'saved',
            label: 'Saved',
            network: AddressBookNetwork.ethereum,
            address: _evmA,
            profilePictureId: 'pfp-01',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
        limit: 2,
      );

      expect(recents.map((recent) => recent.address), [_evmB, thirdAddress]);
    });
  });

  group('PayRecipientSelection', () {
    const first = AddressBookContact(
      id: 'first',
      label: 'First',
      network: AddressBookNetwork.ethereum,
      address: _evmA,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    const second = AddressBookContact(
      id: 'second',
      label: 'Second',
      network: AddressBookNetwork.ethereum,
      address: _evmA,
      profilePictureId: 'pfp-02',
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    test('direct entry binds a unique contact but not duplicate contacts', () {
      expect(
        payRecipientSelectionForAddress(const [first], _evmA).contactId,
        'first',
      );
      expect(
        payRecipientSelectionForAddress(const [first, second], _evmA).contactId,
        isNull,
      );
    });

    test('an explicit contact selection preserves the clicked identity', () {
      const selection = PayRecipientSelection(
        address: _evmA,
        contactId: 'second',
      );

      expect(
        payContactForSelection(const [first, second], selection),
        same(second),
      );
    });

    test('an invalid explicit contact degrades to the raw address', () {
      const selection = PayRecipientSelection(
        address: _evmA,
        contactId: 'second',
      );

      final resolved = resolvePayRecipientSelection(
        const [first],
        _evmA,
        explicitSelection: selection,
      );

      expect(resolved.address, _evmA);
      expect(resolved.contactId, isNull);
    });

    test('direct entry still binds the unique matching contact', () {
      final resolved = resolvePayRecipientSelection(const [first], _evmA);

      expect(resolved.contactId, 'first');
    });
  });

  group('payRecentTimeLabel', () {
    final now = DateTime(2026, 7, 9, 12);

    test('uses relative labels within a week', () {
      expect(
        payRecentTimeLabel(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
      expect(
        payRecentTimeLabel(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        payRecentTimeLabel(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        payRecentTimeLabel(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('falls back to month + day beyond a week', () {
      expect(payRecentTimeLabel(DateTime(2026, 4, 27), now: now), 'April 27');
    });

    test('returns null for missing or future timestamps', () {
      expect(payRecentTimeLabel(null, now: now), isNull);
      expect(
        payRecentTimeLabel(now.add(const Duration(minutes: 1)), now: now),
        isNull,
      );
    });
  });

  group('payCompatibleContacts / payContactForAddress', () {
    final ethContact = AddressBookContact(
      id: 'eth',
      label: 'Mike',
      network: AddressBookNetwork.ethereum,
      address: _evmA,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    final baseContact = AddressBookContact(
      id: 'base',
      label: 'Base Mike',
      network: AddressBookNetwork.base,
      address: _evmB,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    final solContact = AddressBookContact(
      id: 'sol',
      label: 'Sol',
      network: AddressBookNetwork.solana,
      address: _solana,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    test('EVM networks accept contacts from any EVM chain', () {
      final compatible = payCompatibleContacts([
        ethContact,
        baseContact,
        solContact,
      ], AddressBookNetwork.ethereum);
      expect(compatible, [ethContact, baseContact]);
    });

    test('matches addresses case-insensitively', () {
      expect(payContactsForAddress([ethContact], _evmA.toLowerCase()), [
        ethContact,
      ]);
      expect(payContactsForAddress([ethContact], _evmB), isEmpty);
    });

    test('keeps contact matching case-sensitive outside EVM and NEAR', () {
      expect(
        payContactsForAddress([solContact], _solana.replaceFirst('N', 'n')),
        isEmpty,
      );
    });
  });
}
