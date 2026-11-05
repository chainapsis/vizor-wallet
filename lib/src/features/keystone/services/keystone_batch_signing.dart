import 'dart:typed_data';

import '../../../core/l10n/l10n.dart' show AppLocalizations;
import '../../../core/zcash/wallet_error_code.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;

const _keystoneQrFragmentLength = 140;

/// What a friendly batch-signing error is about.
enum KeystoneBatchSubject { transaction, deposit }

/// Maps shared Keystone batch preparation failures to actionable UI copy.
String? keystoneBatchSigningFriendlyError(
  AppLocalizations l10n,
  Object error, {
  KeystoneBatchSubject subject = KeystoneBatchSubject.transaction,
}) {
  final deposit = subject == KeystoneBatchSubject.deposit;
  switch (walletErrorCode(error)) {
    case rust_sync.ApiWalletErrorCode.keystoneBatchSignatureLimit:
      return deposit
          ? l10n.keystoneBatchTooManyInputsDeposit
          : l10n.keystoneBatchTooManyInputsTx;
    case rust_sync.ApiWalletErrorCode.keystoneBatchUnsupportedInput:
      return deposit
          ? l10n.keystoneBatchCannotSignDeposit
          : l10n.keystoneBatchCannotSignTx;
    default:
      return null;
  }
}

class KeystoneBatchPcztSource {
  const KeystoneBatchPcztSource({required this.id, required this.pcztBytes});

  final String id;
  final List<int> pcztBytes;
}

class KeystonePreparedBatchMessage {
  const KeystonePreparedBatchMessage({
    required this.id,
    required this.redactedPczt,
    required this.expectedSignatureCount,
  });

  final String id;
  final List<int> redactedPczt;
  final int expectedSignatureCount;
}

List<rust_keystone_wallet.ZcashBatchMessageInput> keystoneBatchMessageInputs(
  List<KeystonePreparedBatchMessage> messages,
) => [
  for (final message in messages)
    rust_keystone_wallet.ZcashBatchMessageInput(
      id: message.id,
      pcztBytes: Uint8List.fromList(message.redactedPczt),
      expectedSignatureCount: message.expectedSignatureCount,
    ),
];

class KeystoneBatchSigningRequest {
  const KeystoneBatchSigningRequest({
    required this.requestId,
    required this.messageIds,
    required this.expectedSignatureCounts,
    required this.urParts,
  }) : assert(messageIds.length == expectedSignatureCounts.length);

  final String requestId;
  final List<String> messageIds;
  final List<int> expectedSignatureCounts;
  final List<String> urParts;

  Future<rust_keystone.KeystoneSigResult> decodeTypedResponse(
    List<int> responseCbor,
  ) async {
    final decoded = await rust_keystone.decodeZcashBatchSignResponse(
      cbor: responseCbor,
      expectedRequestId: requestId,
      messageIds: messageIds,
    );
    if (decoded.results.length != messageIds.length ||
        expectedSignatureCounts.length != messageIds.length) {
      throw StateError(
        'Keystone returned a different number of signatures than requested.',
      );
    }
    for (var index = 0; index < decoded.results.length; index++) {
      final result = decoded.results[index];
      if (result.sigs.length != expectedSignatureCounts[index]) {
        throw StateError(
          'Keystone returned an unexpected number of signatures for '
          '${messageIds[index]}.',
        );
      }
    }
    return decoded;
  }

  Future<List<List<int>>> decodeResponse(List<int> responseCbor) async {
    final decoded = await decodeTypedResponse(responseCbor);
    final signatures = <List<int>>[];
    for (final result in decoded.results) {
      signatures.add(
        await rust_keystone.encodeKeystoneActionSigs(sigs: result.sigs),
      );
    }
    return signatures;
  }
}

Future<KeystoneBatchSigningRequest> buildKeystoneBatchSigningRequest({
  required String requestId,
  required List<KeystoneBatchPcztSource> pczts,
  int maxFragmentLength = _keystoneQrFragmentLength,
}) async {
  if (requestId.isEmpty) {
    throw ArgumentError.value(requestId, 'requestId', 'must not be empty');
  }
  if (pczts.isEmpty) {
    throw ArgumentError.value(pczts, 'pczts', 'must not be empty');
  }

  final messages = <KeystonePreparedBatchMessage>[];
  for (final source in pczts) {
    final prepared = await rust_sync.preparePcztForKeystoneBatch(
      pcztBytes: source.pcztBytes,
    );
    messages.add(
      KeystonePreparedBatchMessage(
        id: source.id,
        redactedPczt: prepared.redactedPczt,
        expectedSignatureCount: prepared.expectedSignatureCount,
      ),
    );
  }

  return buildPreparedKeystoneBatchSigningRequest(
    requestId: requestId,
    messages: messages,
    maxFragmentLength: maxFragmentLength,
  );
}

Future<KeystoneBatchSigningRequest> buildPreparedKeystoneBatchSigningRequest({
  required String requestId,
  required List<KeystonePreparedBatchMessage> messages,
  int maxFragmentLength = _keystoneQrFragmentLength,
}) async {
  if (requestId.isEmpty) {
    throw ArgumentError.value(requestId, 'requestId', 'must not be empty');
  }
  if (messages.isEmpty) {
    throw ArgumentError.value(messages, 'messages', 'must not be empty');
  }
  if (maxFragmentLength <= 0) {
    throw ArgumentError.value(
      maxFragmentLength,
      'maxFragmentLength',
      'must be positive',
    );
  }
  if (messages.any(
    (message) => message.id.isEmpty || message.expectedSignatureCount <= 0,
  )) {
    throw ArgumentError.value(
      messages,
      'messages',
      'must have non-empty IDs and positive signature counts',
    );
  }

  final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
    requestId: requestId,
    messages: keystoneBatchMessageInputs(messages),
    maxFragmentLen: BigInt.from(maxFragmentLength),
  );
  return KeystoneBatchSigningRequest(
    requestId: requestId,
    messageIds: [for (final message in messages) message.id],
    expectedSignatureCounts: [
      for (final message in messages) message.expectedSignatureCount,
    ],
    urParts: urParts,
  );
}
