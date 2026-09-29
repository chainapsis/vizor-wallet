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
