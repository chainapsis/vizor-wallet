import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/keystone/services/keystone_batch_signing.dart';
import 'package:zcash_wallet/src/rust/api/keystone.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart';

void main() {
  final rustApi = _BatchRustApiFake();

  setUpAll(() => RustLib.initMock(api: rustApi));
  tearDownAll(RustLib.dispose);
  setUp(rustApi.reset);

  test('builds a one-message batch from the signer-redacted PCZT', () async {
    final request = await buildKeystoneBatchSigningRequest(
      requestId: 'send-1',
      pczts: const [
        KeystoneBatchPcztSource(id: 'transaction-1', pcztBytes: [1]),
      ],
    );

    expect(request.requestId, 'send-1');
    expect(request.messageIds, const ['transaction-1']);
    expect(request.expectedSignatureCounts, const [2]);
    expect(request.urParts, const ['UR:ZCASH-SIGN-BATCH/TEST']);
    expect(rustApi.encodedMessages.single.pcztBytes, const [4, 5, 6]);
    expect(rustApi.encodedMessages.single.expectedSignatureCount, 2);
  });

  test('returns only the compact signature blob for each message', () async {
    final request = await buildKeystoneBatchSigningRequest(
      requestId: 'send-1',
      pczts: const [
        KeystoneBatchPcztSource(id: 'transaction-1', pcztBytes: [1]),
      ],
    );

    final signatures = await request.decodeResponse(const [9]);

    expect(signatures, const [
      <int>[2, 7],
    ]);
    expect(rustApi.encodedSignatureCounts, const [2]);
  });

  test('rejects a response with the wrong signature count', () async {
    rustApi.returnedSignatureCount = 1;
    final request = await buildKeystoneBatchSigningRequest(
      requestId: 'send-1',
      pczts: const [
        KeystoneBatchPcztSource(id: 'transaction-1', pcztBytes: [1]),
      ],
    );

    await expectLater(
      request.decodeResponse(const [9]),
      throwsA(isA<StateError>()),
    );
    expect(rustApi.encodedSignatureCounts, isEmpty);
  });

  test('maps the transaction signature limit to actionable copy', () {
    expect(
      keystoneBatchSigningFriendlyError(
        StateError(
          'Keystone batch signing supports at most 96 spend signatures per '
          'transaction; this transaction requires 97',
        ),
      ),
      'This transaction uses too many inputs for Keystone batch signing. '
      'Try a smaller amount.',
    );
  });

  test('uses the caller subject for batch preparation errors', () {
    expect(
      keystoneBatchSigningFriendlyError(
        StateError(
          'Keystone batch signing does not support transparent transaction '
          'inputs',
        ),
        subject: 'deposit',
      ),
      'This deposit uses inputs that Keystone batch signing cannot sign.',
    );
    expect(keystoneBatchSigningFriendlyError(StateError('unrelated')), isNull);
  });
}

class _BatchRustApiFake implements RustLibApi {
  final encodedMessages = <ZcashBatchMessageInput>[];
  final encodedSignatureCounts = <int>[];
  int returnedSignatureCount = 2;

  void reset() {
    encodedMessages.clear();
    encodedSignatureCounts.clear();
    returnedSignatureCount = 2;
  }

  @override
  Future<KeystoneBatchPczt> crateApiSyncPreparePcztForKeystoneBatch({
    required List<int> pcztBytes,
  }) async {
    return KeystoneBatchPczt(
      redactedPczt: Uint8List.fromList([4, 5, 6]),
      expectedSignatureCount: 2,
    );
  }

  @override
  Future<List<String>> crateApiKeystoneEncodeZcashSignBatchUrParts({
    required String requestId,
    required List<ZcashBatchMessageInput> messages,
    required BigInt maxFragmentLen,
  }) async {
    encodedMessages.addAll(messages);
    return const ['UR:ZCASH-SIGN-BATCH/TEST'];
  }

  @override
  Future<KeystoneSigResult> crateApiKeystoneDecodeZcashBatchSignResponse({
    required List<int> cbor,
    required String expectedRequestId,
    required List<String> messageIds,
  }) async {
    return KeystoneSigResult(
      firmwareVersion: Uint8List.fromList([1, 0, 0]),
      requestId: Uint8List.fromList(expectedRequestId.codeUnits),
      results: [
        KeystoneMsgSig(
          messageId: Uint8List.fromList(messageIds.single.codeUnits),
          sigs: [
            for (var index = 0; index < returnedSignatureCount; index++)
              KeystoneActionSig(
                pool: 0,
                actionIndex: index,
                sig: Uint8List(64),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Future<Uint8List> crateApiKeystoneEncodeKeystoneActionSigs({
    required List<KeystoneActionSig> sigs,
  }) async {
    encodedSignatureCounts.add(sigs.length);
    return Uint8List.fromList([sigs.length, 7]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
