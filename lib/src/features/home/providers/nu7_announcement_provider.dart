import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/block_spacing_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';

String nu7AnnouncementSeenStorageKey(String network) =>
    'zcash_nu7_announcement_seen_$network';

/// Remembers that the NU7 announcement was shown on a network. The upgrade is
/// a network event, so one dismissal covers every account.
abstract class Nu7AnnouncementStore {
  Future<bool> isSeen(String network);

  Future<void> markSeen(String network);
}

class SharedPreferencesNu7AnnouncementStore implements Nu7AnnouncementStore {
  const SharedPreferencesNu7AnnouncementStore();

  @override
  Future<bool> isSeen(String network) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(nu7AnnouncementSeenStorageKey(network)) ?? false;
  }

  @override
  Future<void> markSeen(String network) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(nu7AnnouncementSeenStorageKey(network), true);
  }
}

final nu7AnnouncementStoreProvider = Provider<Nu7AnnouncementStore>(
  (_) => const SharedPreferencesNu7AnnouncementStore(),
);

/// Whether the announcement animates its logo; tests turn it off so frames
/// settle.
final nu7AnnouncementMotionEnabledProvider = Provider<bool>((_) => true);

class Nu7AnnouncementState {
  const Nu7AnnouncementState.hidden() : network = null;

  const Nu7AnnouncementState.visible({required String this.network});

  final String? network;

  bool get visible => network != null;
}

/// Visible once the wallet's tip reaches NU7 activation, until dismissed.
final nu7AnnouncementProvider = FutureProvider<Nu7AnnouncementState>((
  ref,
) async {
  final activation = ref.watch(
    blockSpacingProvider.select((spacing) => spacing.nu7ActivationHeight),
  );
  if (activation == null) return const Nu7AnnouncementState.hidden();

  final tipHeight = ref.watch(
    syncProvider.select((sync) {
      final state = sync.value;
      return state == null
          ? 0
          : math.max(state.chainTipHeight, state.scannedHeight);
    }),
  );
  if (tipHeight < activation) return const Nu7AnnouncementState.hidden();

  // A wallet that began after activation has nothing to compare against. An
  // account created this session has no birthday until relaunch.
  final walletPredatesNu7 = ref.watch(
    accountProvider.select(
      (state) =>
          state.value?.accounts.any((account) {
            final birthday = account.birthdayHeight;
            return birthday != null && birthday < activation;
          }) ??
          false,
    ),
  );
  if (!walletPredatesNu7) return const Nu7AnnouncementState.hidden();

  final network = ref.watch(
    rpcEndpointFailoverProvider.select((state) => state.current.networkName),
  );
  if (await ref.watch(nu7AnnouncementStoreProvider).isSeen(network)) {
    return const Nu7AnnouncementState.hidden();
  }
  return Nu7AnnouncementState.visible(network: network);
});
