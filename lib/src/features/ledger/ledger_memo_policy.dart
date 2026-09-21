/// The Ledger Zcash app renders a memo as text only when every byte is
/// printable ASCII; anything else takes its memo-hash path, which the pinned
/// app version does not survive. Keep this in step with the same check in
/// `rust/src/wallet/ledger/parse.rs`, which is the gate that actually blocks
/// signing — this one exists so the user finds out while they can still edit.
const ledgerMemoCharsetError =
    'Ledger memos can only use English letters, numbers, and symbols';

bool _isPrintableAscii(int codeUnit) => codeUnit >= 0x20 && codeUnit <= 0x7e;

String? ledgerMemoError(String? memo) =>
    memo != null && !memo.codeUnits.every(_isPrintableAscii)
    ? ledgerMemoCharsetError
    : null;
