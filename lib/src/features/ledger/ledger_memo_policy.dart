const ledgerMemoNewlineError = 'Ledger memos cannot contain line breaks.';

String? ledgerMemoError(String? memo) =>
    memo != null && (memo.contains('\n') || memo.contains('\r'))
    ? ledgerMemoNewlineError
    : null;
