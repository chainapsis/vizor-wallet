import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voting/voting_config_loader.dart';

/// Mirrors passed over while obtaining the active voting config.
///
/// Separate from `votingConfigRefreshFailureProvider` on purpose: that channel
/// means "the load failed", while this one records mirrors rejected on loads
/// that *succeeded*. A hash-pin mismatch on the canonical trust anchor is
/// exactly that case — the fallback origin serves the pinned bytes, the load
/// returns normally, and without this the strongest tamper signal the wallet
/// has would leave no provider-visible trace at all.
///
/// Replaced only when a current load generation successfully commits, so a
/// failed refresh or stale concurrent load cannot change the evidence attached
/// to the config still in use.
class VotingConfigMirrorIntegrityNotifier
    extends Notifier<List<VotingConfigMirrorFailure>> {
  @override
  List<VotingConfigMirrorFailure> build() => const [];

  void replace(List<VotingConfigMirrorFailure> failures) {
    state = List.unmodifiable(failures);
  }
}

final votingConfigMirrorIntegrityProvider =
    NotifierProvider<
      VotingConfigMirrorIntegrityNotifier,
      List<VotingConfigMirrorFailure>
    >(VotingConfigMirrorIntegrityNotifier.new);

/// Whether the load that produced the active config had a mirror serve bytes
/// that failed authentication.
///
/// True means an origin answered and Rust rejected what it served — a hash-pin
/// mismatch, a bad signature, an unsupported version. Distinct from a mirror
/// that was merely unreachable, which carries no integrity claim.
final votingConfigSawMirrorIntegrityFailureProvider = Provider<bool>((ref) {
  return ref
      .watch(votingConfigMirrorIntegrityProvider)
      .any((failure) => failure.isIntegrityFailure);
});
