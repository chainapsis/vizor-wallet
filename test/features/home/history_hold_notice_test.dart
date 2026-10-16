import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/history_hold_notice.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test('names the held amount', () {
    final sync = SyncState(historyHoldBalance: BigInt.from(35_000_000));

    expect(
      historyHoldNoticeMessage(sync, privacyModeEnabled: false),
      '0.35 ZEC is on hold until sync finishes, because it may have been '
      'spent in history not checked yet.',
    );
  });

  test('masks the amount in privacy mode', () {
    final sync = SyncState(historyHoldBalance: BigInt.from(35_000_000));

    final message = historyHoldNoticeMessage(sync, privacyModeEnabled: true);
    expect(message, isNotNull);
    expect(message, isNot(contains('0.35')));
  });

  test('says nothing when nothing is held', () {
    expect(
      historyHoldNoticeMessage(SyncState(), privacyModeEnabled: false),
      isNull,
    );
  });

  test('leaves a failed sync to its own notice', () {
    final sync = SyncState(
      historyHoldBalance: BigInt.from(35_000_000),
      failure: const SyncFailure(
        kind: SyncFailureKind.network,
        rawMessage: 'network failed',
        userMessage: 'Network connection lost.',
      ),
    );

    expect(historyHoldNoticeMessage(sync, privacyModeEnabled: false), isNull);
  });
}
