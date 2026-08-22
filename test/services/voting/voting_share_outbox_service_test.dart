import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_share_outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.zcash.wallet/background_voting');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  VotingShareOutboxService service({bool supported = true}) {
    return VotingShareOutboxService(channel: channel, supported: supported);
  }

  final share = VotingShareOutboxShare(
    bundleIndex: 1,
    proposalId: 7,
    shareIndex: 0,
    shareIdHex: 'aa11',
    submitAtSeconds: BigInt.zero,
    createdAtSeconds: BigInt.from(100),
    recoveryBodyJson: '{"share":true}',
    sentToUrls: const ['https://helper.example'],
  );

  test('unsupported platform never touches the channel', () async {
    final outbox = service(supported: false);
    expect(
      await outbox.stageShareRound(
        network: 'main',
        accountUuid: 'account-1',
        roundId: 'round',
        voteEndSeconds: BigInt.from(100),
        helperUrls: const ['https://helper.example'],
        prune: true,
        shares: [share],
      ),
      isNull,
    );
    expect(await outbox.listShareReceipts(), isEmpty);
    expect(await outbox.revokeAll(), isTrue);
    expect(calls, isEmpty);
  });

  test('stage sends the round manifest and share payloads', () async {
    handler = (call) => <Object?, Object?>{'1:7:0': 'digest-1'};
    final digests = await service().stageShareRound(
      network: 'main',
      accountUuid: 'account-1',
      roundId: 'round-1',
      voteEndSeconds: BigInt.from(1234),
      helperUrls: const ['https://helper.example'],
      prune: true,
      shares: [share],
    );

    expect(digests, {'1:7:0': 'digest-1'});
    final call = calls.single;
    expect(call.method, 'stageShareRound');
    final args = (call.arguments as Map).cast<String, Object?>();
    expect(args['network'], 'main');
    expect(args['accountUuid'], 'account-1');
    expect(args['roundId'], 'round-1');
    expect(args['voteEndSeconds'], 1234);
    expect(args['prune'], true);
    final shares = (args['shares']! as List).cast<Map>();
    expect(shares.single['shareIdHex'], 'aa11');
    expect(shares.single['recoveryBodyJson'], '{"share":true}');
  });

  test('channel failures degrade to a no-op result', () async {
    handler = (call) => throw PlatformException(code: 'boom');
    final outbox = service();

    expect(
      await outbox.stageShareRound(
        network: 'main',
        accountUuid: 'account-1',
        roundId: 'round-1',
        voteEndSeconds: BigInt.from(1),
        helperUrls: const [],
        prune: true,
        shares: const [],
      ),
      isNull,
    );
    expect(
      await outbox.armShareRound(roundKey: 'k', expectedDigests: const {}),
      isFalse,
    );
    expect(await outbox.listShareReceipts(), isEmpty);
    expect(await outbox.ackShareReceipts(const ['r1']), isFalse);
  });

  test('receipts parse and malformed rows are dropped', () async {
    handler = (call) => <Object?>[
      {
        'receiptId': 'main:account-1:round-1:1:7:0:confirmed',
        'network': 'main',
        'accountUuid': 'account-1',
        'roundId': 'round-1',
        'bundleIndex': 1,
        'proposalId': 7,
        'shareIndex': 0,
        'outcome': 'confirmed',
        'url': 'https://helper.example',
      },
      {'receiptId': 'missing-fields'},
    ];

    final receipts = await service().listShareReceipts();
    expect(receipts, hasLength(1));
    expect(receipts.single.outcome, 'confirmed');
    expect(receipts.single.url, 'https://helper.example');
  });

  test('empty ack list is a successful no-op', () async {
    expect(await service().ackShareReceipts(const []), isTrue);
    expect(calls, isEmpty);
  });
}
