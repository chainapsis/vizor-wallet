import '../../../providers/account_models.dart';

class LedgerAccountImportContext {
  const LedgerAccountImportContext({
    required this.sourceAccount,
    required this.knownAccounts,
    required this.usedIndexes,
    required this.suggestedIndex,
  });

  final AccountInfo sourceAccount;
  final List<AccountInfo> knownAccounts;
  final Set<int> usedIndexes;
  final int suggestedIndex;

  bool usesIndex(int index) => usedIndexes.contains(index);
}

LedgerAccountImportContext? resolveLedgerAccountImportContext({
  required List<AccountInfo> accounts,
  required String? sourceAccountUuid,
}) {
  if (sourceAccountUuid == null) return null;
  AccountInfo? source;
  for (final account in accounts) {
    if (account.uuid == sourceAccountUuid) {
      source = account;
      break;
    }
  }
  if (source == null || !source.isLedger) return null;

  final fingerprint = source.ledgerWalletFingerprint;
  final knownAccounts = fingerprint == null
      ? <AccountInfo>[source]
      : accounts
            .where(
              (account) =>
                  account.isLedger &&
                  account.ledgerWalletFingerprint == fingerprint,
            )
            .toList(growable: false);
  knownAccounts.sort((left, right) {
    final indexOrder = (left.zip32AccountIndex ?? 0x7fffffff).compareTo(
      right.zip32AccountIndex ?? 0x7fffffff,
    );
    return indexOrder != 0 ? indexOrder : left.order.compareTo(right.order);
  });
  final usedIndexes = knownAccounts
      .map((account) => account.zip32AccountIndex)
      .whereType<int>()
      .toSet();
  var suggestedIndex = 0;
  while (usedIndexes.contains(suggestedIndex)) {
    suggestedIndex++;
  }

  return LedgerAccountImportContext(
    sourceAccount: source,
    knownAccounts: List.unmodifiable(knownAccounts),
    usedIndexes: Set.unmodifiable(usedIndexes),
    suggestedIndex: suggestedIndex,
  );
}
