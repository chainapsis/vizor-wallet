/// User copy for a wallet whose transparent funds this build cannot use.
const transparentLedgerNeedsNewerBuildMessage =
    'This wallet needs a newer version of Vizor to use its transparent funds.';

/// Whether [raw] is the wallet library's refusal to operate on transparent
/// funds under a stricter or newer policy than this build supports.
///
/// Matches the phrase the library's `TransparentLedgerPolicyConflict` and
/// `TransparentLedgerIncompatible` errors share; the Rust guard test pins it.
bool isTransparentLedgerNeedsNewerBuildError(String raw) => raw
    .toLowerCase()
    .contains("this build cannot operate on this wallet's transparent funds");

/// User copy for transparent funds that private recovery does not yet cover.
const transparentRecoveryIncompleteMessage =
    'Transparent funds are unavailable until private recovery completes.';

/// Whether [raw] is a refusal to use transparent funds because the wallet's
/// private transparent ledger holds no current authority for them.
///
/// Matches the phrase the library's `TransparentAuthorityUnavailable` error
/// and Vizor's shielding refusal share; the Rust guard test pins it.
bool isTransparentRecoveryIncompleteError(String raw) =>
    raw.toLowerCase().contains('transparent funds are unavailable');

/// User copy for a wallet that durably requires private transparent recovery
/// in a build that does not run it.
const transparentRecoveryNotSelectedMessage =
    'Private transparent recovery is not available in this build. Turn off '
    'Private queries to use transparent funds. If it is already off, '
    'turn it on and then off.';

/// Whether [raw] is a refusal to use transparent funds because the wallet
/// requires private recovery and this build does not run it, so no recovery
/// will complete. Check it before [isTransparentRecoveryIncompleteError].
///
/// Matches Vizor's shielding refusal; the Rust status test pins the phrase.
bool isTransparentRecoveryNotSelectedError(String raw) =>
    raw.toLowerCase().contains('turn off private queries');
