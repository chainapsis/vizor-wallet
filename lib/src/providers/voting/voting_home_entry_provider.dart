import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account_provider.dart';
import '../app_security_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_restorer_provider.dart';
import 'voting_state.dart';

/// Attention count for the home voting entry: unexpired rounds with pending
/// helper-share work, read from the local voting sidecar only.
///
/// This deliberately never touches the voting config or chain API — the home
/// screen must not trigger (or block on) the network-bound round list load.
/// Best effort: any failure reads as zero. Recomputed on unlock (via the
/// security watch) and on app resume.
final votingHomeAttentionProvider = FutureProvider<int>((ref) async {
  final lifecycleListener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycleListener.dispose);

  if (ref.watch(appSecurityProvider).requiresUnlock) return 0;
  try {
    final accounts = (await ref.watch(accountProvider.future)).accounts;
    if (accounts.isEmpty) return 0;
    final dbPath = await ref.read(votingWalletDbPathProvider).call();
    final pending = await ref
        .read(votingPendingShareRoundLoaderProvider)
        .call(
          dbPath: dbPath,
          accountUuids: [for (final account in accounts) account.uuid],
        );
    final now = DateTime.now().toUtc();
    return pending.where((round) {
      final voteEnd = votingSessionVoteEndTime(round.sessionJson);
      return voteEnd != null && now.isBefore(voteEnd);
    }).length;
  } catch (error, stackTrace) {
    debugPrint(
      '[zcash] Voting: home attention probe failed: $error\n$stackTrace',
    );
    return 0;
  }
});
