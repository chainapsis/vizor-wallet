import '../../../providers/account_models.dart';

const kPaymentLinkBatchMinCount = 2;
const kPaymentLinkBatchMaxCount = 50;
const kPaymentLinkKeystoneBatchMaxCount = 30;
const kPaymentLinkLedgerBatchMaxCount = 30;

int paymentLinkBatchMaxCount(HardwareSignerKind? signer) => switch (signer) {
  HardwareSignerKind.keystone => kPaymentLinkKeystoneBatchMaxCount,
  HardwareSignerKind.ledger => kPaymentLinkLedgerBatchMaxCount,
  null => kPaymentLinkBatchMaxCount,
};
