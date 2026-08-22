import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_outbox_provider.dart';
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

  Map<String, Object?> receiptRow({
    required String receiptId,
    required String outcome,
    String? url,
  }) => {
    'receiptId': receiptId,
    'network': 'main',
    'accountUuid': 'account-1',
    'roundId': 'round-1',
    'bundleIndex': 2,
    'proposalId': 9,
    'shareIndex': 1,
    'outcome': outcome,
    if (url != null) 'url': url,
  };

  test('applies receipts to the sidecar and acks only applied ones', () async {
    handler = (call) => switch (call.method) {
      'listShareReceipts' => <Object?>[
        receiptRow(receiptId: 'r-confirmed', outcome: 'confirmed'),
        receiptRow(
          receiptId: 'r-resubmitted',
          outcome: 'resubmitted',
          url: 'https://helper.example',
        ),
        receiptRow(receiptId: 'r-expired', outcome: 'expired'),
        receiptRow(receiptId: 'r-unknown', outcome: 'future-outcome'),
      ],
      'ackShareReceipts' => true,
      _ => null,
    };

    final rust = _RecordingRustApi();
    final recoveryApi = _RecordingRecoveryApi();
    final container = ProviderContainer(
      overrides: [
        votingShareOutboxProvider.overrideWithValue(
          VotingShareOutboxService(channel: channel, supported: true),
        ),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingRustApiProvider.overrideWithValue(rust),
        votingRecoveryServiceProvider.overrideWithValue(
          VotingRecoveryService(api: recoveryApi),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingShareOutboxReconcilerProvider).reconcile();

    expect(rust.confirmed, ['account-1|round-1|2|9|1']);
    expect(recoveryApi.sentServers, [
      'account-1|round-1|2|9|1|https://helper.example',
    ]);
    final ack = calls.singleWhere((call) => call.method == 'ackShareReceipts');
    expect(
      ((ack.arguments as Map)['receiptIds'] as List).cast<String>(),
      // The unknown outcome stays unacked so an updated app can still apply
      // it; expired needs no sidecar write but is acknowledged.
      ['r-confirmed', 'r-resubmitted', 'r-expired'],
    );
  });

  test('a failed sidecar apply keeps that receipt unacked', () async {
    handler = (call) => switch (call.method) {
      'listShareReceipts' => <Object?>[
        receiptRow(receiptId: 'r-confirmed', outcome: 'confirmed'),
        receiptRow(
          receiptId: 'r-resubmitted',
          outcome: 'resubmitted',
          url: 'https://helper.example',
        ),
      ],
      'ackShareReceipts' => true,
      _ => null,
    };

    final rust = _RecordingRustApi(failMarkConfirmed: true);
    final recoveryApi = _RecordingRecoveryApi();
    final container = ProviderContainer(
      overrides: [
        votingShareOutboxProvider.overrideWithValue(
          VotingShareOutboxService(channel: channel, supported: true),
        ),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingRustApiProvider.overrideWithValue(rust),
        votingRecoveryServiceProvider.overrideWithValue(
          VotingRecoveryService(api: recoveryApi),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingShareOutboxReconcilerProvider).reconcile();

    final ack = calls.singleWhere((call) => call.method == 'ackShareReceipts');
    expect(
      ((ack.arguments as Map)['receiptIds'] as List).cast<String>(),
      ['r-resubmitted'],
    );
  });

  test('unsupported service skips the channel entirely', () async {
    final container = ProviderContainer(
      overrides: [
        votingShareOutboxProvider.overrideWithValue(
          VotingShareOutboxService(channel: channel, supported: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingShareOutboxReconcilerProvider).reconcile();

    expect(calls, isEmpty);
  });
}

class _RecordingRustApi implements VotingRustApi {
  _RecordingRustApi({this.failMarkConfirmed = false});

  final bool failMarkConfirmed;
  final confirmed = <String>[];

  @override
  Future<void> markShareConfirmed({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) async {
    if (failMarkConfirmed) throw StateError('sidecar locked');
    confirmed.add('$accountUuid|$roundId|$bundleIndex|$proposalId|$shareIndex');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingRecoveryApi implements VotingRecoveryApi {
  final sentServers = <String>[];

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {
    sentServers.add(
      '$accountUuid|$roundId|$bundleIndex|$proposalId|$shareIndex'
      '|${newUrls.join(',')}',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
