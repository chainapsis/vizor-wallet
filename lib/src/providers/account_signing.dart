import 'account_models.dart';

/// Operations whose signer support is selected before entering a
/// signer-specific protocol.
enum AccountSigningOperation {
  send,
  shield,
  paymentLinkFunding,
  zecOutboundSwap,
  voting,
  ironwoodMigration,
}

/// Signer protocols currently implemented by this layer.
enum AccountSigningBackend { software, keystone }

extension AccountSigningBackendProtocol on AccountSigningBackend {
  bool get usesKeystoneProtocol => switch (this) {
    AccountSigningBackend.software => false,
    AccountSigningBackend.keystone => true,
  };
}

class UnsupportedAccountSignerException implements Exception {
  const UnsupportedAccountSignerException({
    required this.signerKind,
    required this.operation,
  });

  final AccountSignerKind signerKind;
  final AccountSigningOperation operation;

  String get userMessage => switch ((signerKind, operation)) {
    (AccountSignerKind.ledger, AccountSigningOperation.send) =>
      'Ledger signing is not available in this build.',
    (AccountSignerKind.ledger, AccountSigningOperation.shield) =>
      'Ledger shielding is not available in this build.',
    (AccountSignerKind.ledger, AccountSigningOperation.paymentLinkFunding) =>
      'Ledger gift card funding is not available in this build.',
    (AccountSignerKind.ledger, AccountSigningOperation.zecOutboundSwap) =>
      'Ledger swap signing is not available in this build.',
    (AccountSignerKind.ledger, AccountSigningOperation.voting) =>
      'Ledger voting signing is not available in this build.',
    (AccountSignerKind.ledger, AccountSigningOperation.ironwoodMigration) =>
      'Ledger migration signing is not available in this build.',
    _ => '${signerKind.name} signing is not available for ${operation.name}.',
  };

  @override
  String toString() => userMessage;
}

AccountSigningBackend resolveAccountSigningBackend(
  AccountInfo account, {
  required AccountSigningOperation operation,
}) => resolveAccountSignerKind(account.signerKind, operation: operation);

AccountSigningBackend resolveAccountSignerKind(
  AccountSignerKind signerKind, {
  required AccountSigningOperation operation,
}) {
  return switch (signerKind) {
    AccountSignerKind.software => AccountSigningBackend.software,
    AccountSignerKind.keystone => AccountSigningBackend.keystone,
    AccountSignerKind.ledger => throw UnsupportedAccountSignerException(
      signerKind: AccountSignerKind.ledger,
      operation: operation,
    ),
  };
}
