import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_mutation_guard.dart';

void main() {
  testWidgets('pauses stale sync work even when there are no accounts', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForAccountMutation(capturedRef, () async {
      events.add('action');
    });

    expect(events, ['pause', 'action', 'resume']);
  });

  testWidgets('can skip resuming after destructive wallet mutation', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForAccountMutation(
      capturedRef,
      () async {
        events.add('action');
      },
      resumeAfterMutation: false,
    );

    expect(events, ['pause', 'action']);
  });
}

class _EmptyAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState();
}

class _StaleSyncNotifier extends SyncNotifier {
  _StaleSyncNotifier(this.events);

  final List<String> events;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => true;

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    events.add('pause');
    return const WalletMutationSyncPause(
      hadActiveSync: true,
      hadPolling: false,
      hadBackgroundSync: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    events.add('resume');
  }
}
