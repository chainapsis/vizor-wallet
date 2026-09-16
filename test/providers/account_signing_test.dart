import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/account_signing.dart';

void main() {
  const software = AccountInfo(uuid: 'software', name: 'Software', order: 0);
  const keystone = AccountInfo(
    uuid: 'keystone',
    name: 'Keystone',
    order: 1,
    isHardware: true,
    hardwareSignerKind: HardwareSignerKind.keystone,
  );
  const ledger = AccountInfo(
    uuid: 'ledger',
    name: 'Ledger',
    order: 2,
    isHardware: true,
    hardwareSignerKind: HardwareSignerKind.ledger,
  );

  test('signer identity is independent from operation support', () {
    expect(software.signerKind, AccountSignerKind.software);
    expect(keystone.signerKind, AccountSignerKind.keystone);
    expect(ledger.signerKind, AccountSignerKind.ledger);
  });

  test('policy resolves current software and Keystone backends', () {
    for (final operation in AccountSigningOperation.values) {
      expect(
        resolveAccountSigningBackend(software, operation: operation),
        AccountSigningBackend.software,
      );
      expect(
        resolveAccountSigningBackend(keystone, operation: operation),
        AccountSigningBackend.keystone,
      );
    }
  });

  test('policy rejects Ledger with an operation-specific typed error', () {
    for (final operation in AccountSigningOperation.values) {
      expect(
        () => resolveAccountSigningBackend(ledger, operation: operation),
        throwsA(
          isA<UnsupportedAccountSignerException>()
              .having(
                (error) => error.signerKind,
                'signer',
                AccountSignerKind.ledger,
              )
              .having((error) => error.operation, 'operation', operation)
              .having(
                (error) => error.userMessage,
                'message',
                contains('Ledger'),
              ),
        ),
      );
    }
  });

  test('inconsistent in-memory signer metadata fails closed', () {
    const inconsistent = AccountInfo(
      uuid: 'invalid',
      name: 'Invalid',
      order: 3,
      hardwareSignerKind: HardwareSignerKind.ledger,
    );

    expect(() => inconsistent.signerKind, throwsStateError);
  });
}
