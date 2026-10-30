/// User copy for a wallet whose transparent funds this build cannot use.
const transparentLedgerNeedsNewerBuildMessage =
    'This wallet needs a newer version of Vizor to use its transparent funds.';

/// Whether [raw] is the wallet library's refusal to operate on transparent
/// funds under a stricter or newer policy than this build supports.
///
/// Matches the phrase of the library's `TransparentLedgerIncompatible` error;
/// the Rust guard test pins it. (A weaker handle on a wallet that durably
/// requires private recovery no longer fails: the library resolves it under
/// that policy, so shielding reports the opt-out as unfinished instead.)
bool isTransparentLedgerNeedsNewerBuildError(String raw) => raw
    .toLowerCase()
    .contains("this build cannot operate on this wallet's transparent funds");

/// User copy for transparent funds that private recovery does not yet cover.
const transparentRecoveryIncompleteMessage =
    'Transparent funds are unavailable until private recovery completes.';

/// Whether [raw] is the wallet library's refusal to use transparent funds
/// because the wallet's private transparent ledger holds no current authority
/// for them.
///
/// Matches the phrase of the library's `TransparentAuthorityUnavailable`
/// error, which reaches the app as text; the Rust guard test pins it. Vizor's
/// own shielding refusal arrives coded instead.
bool isTransparentRecoveryIncompleteError(String raw) =>
    raw.toLowerCase().contains('transparent funds are unavailable');

/// User copy for a wallet that still requires private recovery while Private
/// queries is off: turning it off did not finish lowering the wallet's policy.
const privateQueriesOptOutUnfinishedMessage =
    "Turning off Private queries didn't finish. Turn it off again in "
    'Settings to use transparent funds.';
