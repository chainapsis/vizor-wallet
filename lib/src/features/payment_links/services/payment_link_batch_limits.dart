import '../../../providers/account_models.dart';
import '../../ledger/ledger_capability.dart';

const kPaymentLinkBatchMinCount = 2;
const kPaymentLinkBatchMaxCount = 50;
const kPaymentLinkKeystoneBatchMaxCount = 30;

int paymentLinkBatchMaxCount(HardwareSignerKind? signer) => switch (signer) {
  HardwareSignerKind.keystone => kPaymentLinkKeystoneBatchMaxCount,
  HardwareSignerKind.ledger => kLedgerMaxExternalShieldedOutputs,
  null => kPaymentLinkBatchMaxCount,
};
