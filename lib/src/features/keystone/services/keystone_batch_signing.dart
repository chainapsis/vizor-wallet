import 'dart:typed_data';

import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;

const _keystoneQrFragmentLength = 140;

/// Maps shared Keystone batch preparation failures to actionable UI copy.
String? keystoneBatchSigningFriendlyError(
  Object error, {
  String subject = 'transaction',
}) {
  final lower = error.toString().toLowerCase();
  if (lower.contains('keystone batch signing supports at most')) {
    return 'This $subject uses too many inputs for Keystone batch signing. '
        'Try a smaller amount.';
  }
  if (lower.contains('batch signing does not support')) {
    return 'This $subject uses inputs that Keystone batch signing cannot sign.';
  }
  return null;
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
