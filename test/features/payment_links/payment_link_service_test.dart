import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  test('funding covers the exact recipient amount and claim fee', () {
    final recipientAmount = BigInt.from(100000000);

    expect(
      paymentLinkFundingAmountZatoshi(recipientAmount),
      BigInt.from(100010000),
    );
    expect(
      () => paymentLinkFundingAmountZatoshi(BigInt.zero),
      throwsArgumentError,
    );
  });

  test('claim exposes only the amount promised by the link', () {
    final recipientAmount = BigInt.from(100000000);

    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(100000000),
      ),
      recipientAmount,
    );
    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(120000000),
      ),
      recipientAmount,
    );
    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(99999999),
      ),
      BigInt.zero,
    );
  });

  test('pending and partial claim broadcasts retain their wallet DB', () {
    expect(
      shouldRetainPaymentLinkClaimWallet(
        paymentLinkClaimBroadcastStatusFromWire('pending_broadcast'),
      ),
      isTrue,
    );
    expect(
      shouldRetainPaymentLinkClaimWallet(
        paymentLinkClaimBroadcastStatusFromWire('partial_broadcast'),
      ),
      isTrue,
    );
    expect(
      shouldRetainPaymentLinkClaimWallet(
        paymentLinkClaimBroadcastStatusFromWire('broadcasted'),
      ),
      isFalse,
    );
    expect(
      () => paymentLinkClaimBroadcastStatusFromWire('unexpected'),
      throwsStateError,
    );
  });

  test('only reuses a complete claim wallet for the expected address', () {
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const [],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1expected', 'u1unexpected'],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1unexpected'],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1expected'],
        expectedAddress: 'u1expected',
      ),
      isFalse,
    );
  });

  test('claim broadcast stops when the wallet locks', () {
    expect(
      () => requireUnlockedPaymentLinkWallet(requiresUnlock: true),
      throwsStateError,
    );
    expect(
      () => requireUnlockedPaymentLinkWallet(requiresUnlock: false),
      returnsNormally,
    );
  });

  test('bounds claim birthdays to a recent chain-tip window', () {
    const currentTip = 3500000;
    expect(
      validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight:
            currentTip - kPaymentLinkMaxClaimLookbackBlocks,
        currentTipHeight: currentTip,
      ),
      currentTip - kPaymentLinkMaxClaimLookbackBlocks,
    );
    expect(
      () => validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight:
            currentTip - kPaymentLinkMaxClaimLookbackBlocks - 1,
        currentTipHeight: currentTip,
      ),
      throwsFormatException,
    );
    expect(
      () => validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight: currentTip + 1,
        currentTipHeight: currentTip,
      ),
      throwsFormatException,
    );
  });

  test('claim wallet directory is deterministic without exposing its secret', () {
    final link = _link();
    final sameLinkName = paymentLinkClaimWalletDirectoryName(link);
    final differentSecretName = paymentLinkClaimWalletDirectoryName(
      VizorPaymentLink(
        network: link.network,
        address: link.address,
        amountZatoshi: link.amountZatoshi,
        mnemonic:
            'legal winner thank year wave sausage worth useful legal winner thank yellow',
        birthdayHeight: link.birthdayHeight,
        label: link.label,
        createdAt: link.createdAt,
      ),
    );

    expect(paymentLinkClaimWalletDirectoryName(link), sameLinkName);
    expect(differentSecretName, isNot(sameLinkName));
    expect(sameLinkName, isNot(contains(link.address)));
    expect(sameLinkName, isNot(contains('abandon')));
  });

  test(
    'hardware funding is rejected before creating a recovery draft',
    () async {
      final storage = _RecordingPaymentLinkRecoveryStorage();
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_HardwareAccountNotifier.new),
          paymentLinkRecoveryStoreProvider.overrideWithValue(
            PaymentLinkRecoveryStore(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      await expectLater(
        container
            .read(paymentLinkServiceProvider)
            .createFundedLink(
              amountZatoshi: BigInt.from(100000),
              sourceAccountUuid: 'hardware-account',
            ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Keystone payment links require the hardware signing flow.',
          ),
        ),
      );
      expect(storage.writeCount, 0);
    },
  );
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'hardware-account',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'hardware-account',
    activeAddress: 'u1hardwareaddress',
  );
}

class _RecordingPaymentLinkRecoveryStorage
    implements PaymentLinkRecoveryStorage {
  int writeCount = 0;

  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    writeCount += 1;
  }
}

VizorPaymentLink _link() {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1paymentlinkaddress',
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
  );
}
