import '../../rust/third_party/zcash_voting/wire.dart';

/// A typed failure from the Rust voting bridge.
///
/// Every voting FRB call reports SDK failures as a `VotingErrorView`; the
/// bridge wrapper rethrows them as this exception so Dart classifies them by
/// `kind` and payload instead of matching message text. `toString` returns
/// the message so logs and generic error surfaces stay readable.
class VotingRustException implements Exception {
  const VotingRustException(this.view);

  final VotingErrorView view;

  VotingErrorKindView get kind => view.kind;

  bool get retryable => view.retryable;

  String get message => view.message;

  int? get bundleIndex => view.bundleIndex;

  BigInt? get snapshotHeight => view.snapshotHeight;

  BigInt? get requiredWeightZatoshi => view.requiredWeightZatoshi;

  /// The account cannot vote in this round: no spendable notes at the
  /// snapshot, or too little eligible weight.
  bool get isEligibilityFailure =>
      kind == VotingErrorKindView.insufficientEligibility ||
      kind == VotingErrorKindView.noSpendableNotes;

  @override
  String toString() => message;
}

/// Implemented by wrapper exceptions that aggregate bridge failures, so error
/// classification survives the wrapping.
///
/// A per-bundle batch failure is still an SDK failure; without this, message
/// formatting and eligibility checks would only see the wrapper's own text.
abstract interface class VotingRustExceptionSource {
  /// The failure that best represents this wrapper, or null when none of its
  /// causes came from the bridge.
  VotingRustException? get votingRustException;
}

/// The bridge failure behind [error], looking through batch wrappers.
VotingRustException? votingRustExceptionOf(Object error) {
  if (error is VotingRustException) return error;
  if (error is VotingRustExceptionSource) return error.votingRustException;
  return null;
}
