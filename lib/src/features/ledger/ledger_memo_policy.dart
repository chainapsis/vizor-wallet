/// The Ledger Zcash app renders a memo as text only when every byte is
/// printable ASCII; anything else takes its memo-hash path, which the pinned
/// app version does not survive. Keep this in step with the same check in
/// `rust/src/wallet/ledger/parse.rs`, which is the gate that actually blocks
/// signing — this one exists so the user finds out while they can still edit.
///
/// Worded as a current limitation rather than a rule: it goes away once the
/// device app is fixed upstream.
const ledgerMemoUnsupportedError = "Ledger can't sign non-English text yet";

/// Shown where only a few words fit — a phone-width primary button leaves
/// about 323 logical pixels for its label — next to an explicit edit
/// affordance that says what to do.
const ledgerMemoUnsupportedCta = 'Memo not supported';

bool _isPrintableAscii(int codeUnit) => codeUnit >= 0x20 && codeUnit <= 0x7e;

/// Pass the memo the transaction will actually pay, not the raw field text:
/// a memo that is trimmed away, or dropped because the recipient is
/// transparent, never reaches the device.
String? ledgerMemoError(String? memo) =>
    memo != null && !memo.codeUnits.every(_isPrintableAscii)
    ? ledgerMemoUnsupportedError
    : null;
