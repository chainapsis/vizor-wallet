String swapMinimumReceiveTooltip(String receiveSymbol) =>
    "The lowest amount of $receiveSymbol you'll get after slippage. "
    'You may get more, never less.';

const swapGenericMinimumReceiveTooltip =
    "The lowest amount you'll get after slippage. "
    'You may get more, never less.';

const swapPriceProtectionTooltip =
    'How much of the received amount your slippage tolerance protects. '
    'The swap is refunded if the rate moves past this.';

const swapFeeTooltip =
    "Covers our fee and the route providers' costs to process this swap. "
    'Already included in the rate above.';

const swapTotalFeesTooltip = swapFeeTooltip;

const swapStatusDetailTooltip =
    'Details are based on the latest swap record and provider status.';
