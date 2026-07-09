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
  SwapDirection direction = SwapDirection.zecToExternal,
  DateTime? createdAt,
  DateTime? completedAt,
}) {
  return SwapIntent(
    id: id,
    pair: 'ZEC -> USDC',
    sellAmount: '1 ZEC',
    receiveEstimate: '10 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: '',
    direction: direction,
    oneClickRecipient: recipient,
    createdAt: createdAt,
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
        );

        expect(recents.map((r) => r.address), [_evmB, _evmA]);
      },
    );

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
      );

      expect(recents, hasLength(1));
      expect(recents.single.lastUsedAt, DateTime(2026, 7, 7));
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
        limit: 5,
      );

      expect(recents, hasLength(5));
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
      expect(
        payContactForAddress(
          [ethContact],
          AddressBookNetwork.ethereum,
          _evmA.toLowerCase(),
        ),
        ethContact,
      );
      expect(
        payContactForAddress([ethContact], AddressBookNetwork.ethereum, _evmB),
        isNull,
      );
    });
  });
}
