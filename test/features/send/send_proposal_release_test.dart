import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final api = _ReleaseApi();
  late _ReleaseSyncNotifier sync;

  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.gate = null;
    api.failures = 0;
    api.calls = 0;
    sync = _ReleaseSyncNotifier();
  });

  Future<bool> release() => discardSendProposal(
    proposalId: BigInt.one,
    sendFlowId: 'send-1',
    logContext: 'ReleaseTest',
    syncNotifier: sync,
    accountUuid: 'account-1',
  );

  test(
    'release waits for unlock and then the owning account refresh',
    () async {
      api.gate = Completer<void>();
      sync.gate = Completer<void>();
      var completed = false;
      final result = release().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(sync.accounts, isEmpty);
      expect(completed, isFalse);

      api.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sync.accounts, ['account-1']);
      expect(completed, isFalse);

      sync.gate!.complete();
      expect(await result, isTrue);
    },
  );

  test('an unconfirmed unlock never refreshes or enables retry', () async {
    api.failures = 3;
    expect(await release(), isFalse);
    expect(api.calls, 3);
    expect(sync.accounts, isEmpty);
  });

  test('a transient unlock failure refreshes only after success', () async {
    api.failures = 1;
    expect(await release(), isTrue);
    expect(api.calls, 2);
    expect(sync.accounts, ['account-1']);
  });

  test(
    'a refresh failure stays retryable after the proposal was released',
    () async {
      sync.fail = true;
      expect(await release(), isFalse);
      sync.fail = false;
      expect(await release(), isTrue);
      expect(api.calls, 2);
      expect(sync.accounts, ['account-1', 'account-1']);
    },
  );
}

class _ReleaseSyncNotifier extends SyncNotifier {
  final accounts = <String>[];
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {
    accounts.add(accountUuid);
    if (gate != null) await gate!.future;
    if (fail) throw StateError('balance unavailable');
  }
}

class _ReleaseApi implements RustLibApi {
  Completer<void>? gate;
  int failures = 0;
  int calls = 0;

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (failures > 0) {
      failures--;
      throw StateError('unlock unavailable');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
