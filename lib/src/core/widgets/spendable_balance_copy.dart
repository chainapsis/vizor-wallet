/// Copy shared by the desktop Max tooltip and the mobile spendable-balance
/// sheet, so both surfaces explain the same rules with the same words.
const kSpendableBalanceInfoTitle =
    'Your spendable balance may be lower than your total balance.';

const kSpendableBalanceInfoBody =
    'Funds need confirmations before they can be spent: 3 for change from '
    'your own wallet, 6 for funds received from others. Shielded notes also '
    "need to be fully scanned. They'll become available shortly.";

/// Ledger accounts have a second ceiling on Max: the device can only sign a
/// bounded number of notes per transaction.
const kSpendableBalanceLedgerNote =
    'On a Ledger account, Max is also limited to what the device can sign in '
    'one transaction. Send the rest in another transfer.';
