import 'dart:typed_data';

import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;

const keystoneBatchSignatureUrType = 'zcash-batch-sig-result';
const keystoneBatchQrFragmentLength = 140;
const keystoneSendBatchMessageId = 'zec-send';

/// Encodes one wallet-owned PCZT as a compact, one-message Keystone batch.
Future<List<String>> encodeKeystoneBatchPcztUrParts({
  required List<int> pcztBytes,
  required String requestId,
  required String messageId,
}) async {
  final batchPczt = await rust_keystone.prepareKeystoneBatchPczt(
    pcztBytes: pcztBytes,
  );
  return rust_keystone.encodeZcashSignBatchUrParts(
    requestId: requestId,
    messages: [
      rust_keystone_wallet.ZcashBatchMessageInput(
        id: messageId,
        pcztBytes: batchPczt.redactedPczt,
        expectedSignatureCount: batchPczt.expectedSignatureCount,
      ),
    ],
    maxFragmentLen: BigInt.from(keystoneBatchQrFragmentLength),
  );
}

/// Validates and applies a one-message Keystone batch-signing response.
Future<Uint8List> decodeAndApplyKeystoneBatchPcztSignatures({
  required List<int> pcztBytes,
  required List<int> responseCbor,
  required String requestId,
  required String messageId,
}) async {
  final decoded = await rust_keystone.decodeZcashBatchSignResponse(
    cbor: responseCbor,
    expectedRequestId: requestId,
    messageIds: [messageId],
  );
  return rust_keystone.applyKeystoneBatchPcztSignatures(
    pcztBytes: pcztBytes,
    signatures: decoded.results.single.sigs,
  );
}
