import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const previewSwapIntents = <SwapIntent>[
  SwapIntent(
    id: 'swap-8f29',
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '2.4000 ZEC',
    receiveEstimate: '168.42 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.processing,
    nextAction: 'Swap is processing',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapStep(
        label: 'One-time transparent address prepared',
        state: SwapStepState.done,
        evidence: '0 previous uses',
      ),
      SwapStep(
        label: 'Deposit observed',
        state: SwapStepState.done,
        evidence: 'Height 2,860,411',
      ),
      SwapStep(
        label: 'Destination transaction submitted',
        state: SwapStepState.done,
        evidence: 'USDC tx pending finality',
      ),
      SwapStep(
        label: 'Swap processing',
        state: SwapStepState.active,
        evidence: 'Provider is preparing delivery',
      ),
      SwapStep(
        label: 'Receipt sealed',
        state: SwapStepState.pending,
        evidence: 'Waiting on provider completion',
      ),
    ],
    exposure: [
      SwapDetailField(
        label: 'Deposit address',
        value: 'one-time transparent address',
      ),
      SwapDetailField(label: 'Address reuse', value: '0 previous uses'),
      SwapDetailField(
        label: 'Third-party data',
        value: 'solver sees deposit tx and route',
      ),
      SwapDetailField(
        label: 'Network disclosure',
        value: 'direct connection; Tor not enabled',
      ),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-8f29'),
      SwapDetailField(label: 'Pair', value: 'ZEC -> USDC'),
      SwapDetailField(label: 'Quote', value: 'locked at 10:42'),
      SwapDetailField(label: 'Shared fields', value: 'txid + status only'),
    ],
  ),
  SwapIntent(
    id: 'swap-6c44',
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '210.52 USDC',
    receiveEstimate: '3.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingExternalDeposit,
    nextAction: 'Send USDC to the one-time deposit address',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapStep(
        label: 'One-time USDC address prepared',
        state: SwapStepState.active,
        evidence: 'Do not reuse this address',
      ),
      SwapStep(
        label: 'External deposit observed',
        state: SwapStepState.pending,
        evidence: 'Waiting for source-chain confirmation',
      ),
      SwapStep(
        label: 'Shielded receive pending',
        state: SwapStepState.pending,
        evidence: 'Destination is the active ZEC account',
      ),
    ],
    exposure: [
      SwapDetailField(label: 'Deposit address', value: 'one-time USDC address'),
      SwapDetailField(
        label: 'ZEC destination',
        value: 'active shielded account',
      ),
      SwapDetailField(
        label: 'Third-party data',
        value: 'solver sees USDC deposit and ZEC route',
      ),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-6c44'),
      SwapDetailField(label: 'Pair', value: 'USDC -> ZEC'),
      SwapDetailField(label: 'Quote', value: 'locked at 10:48'),
      SwapDetailField(label: 'Shared fields', value: 'txid + status only'),
    ],
  ),
  SwapIntent(
    id: 'swap-underpaid',
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '100.00 USDC',
    receiveEstimate: '1.4250 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.incompleteDeposit,
    nextAction: 'Top up the missing deposit or wait for refund',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapStep(
        label: 'One-time USDC address prepared',
        state: SwapStepState.done,
        evidence: '0 previous uses',
      ),
      SwapStep(
        label: 'Incomplete deposit',
        state: SwapStepState.warning,
        evidence: 'Deposit is below the quoted amount',
      ),
      SwapStep(
        label: 'Resolution pending',
        state: SwapStepState.active,
        evidence: 'Top up or wait for refund',
      ),
    ],
    exposure: [
      SwapDetailField(label: 'Deposit address', value: 'one-time USDC address'),
      SwapDetailField(label: 'Visible issue', value: 'underpaid deposit'),
      SwapDetailField(
        label: 'Refund path',
        value: 'USDC refunds return to entered address',
      ),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-underpaid'),
      SwapDetailField(label: 'Pair', value: 'USDC -> ZEC'),
      SwapDetailField(label: 'Deposit', value: '0xunderpaid-usdc-deposit'),
      SwapDetailField(label: 'Memo', value: 'memo-underpaid'),
      SwapDetailField(label: 'Status', value: 'incomplete deposit'),
      SwapDetailField(label: 'Resolution', value: 'top up or refund'),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: '0xunderpaid-usdc-deposit',
    depositMemo: 'memo-underpaid',
    oneClickRefundTo: '0xusdc-refund-underpaid',
  ),
  SwapIntent(
    id: 'swap-refund',
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '0.9000 ZEC',
    receiveEstimate: '63.16 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.refunded,
    nextAction: 'Refunded to source address',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote refund',
      ),
      SwapStep(
        label: 'Deposit observed',
        state: SwapStepState.done,
        evidence: 'Height 2,860,205',
      ),
      SwapStep(
        label: 'Refund tx submitted',
        state: SwapStepState.warning,
        evidence: 'Refunded to source address',
      ),
    ],
    exposure: [
      SwapDetailField(label: 'Refund path', value: 'wallet unified address'),
      SwapDetailField(label: 'Third-party data', value: 'refund status'),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-refund'),
      SwapDetailField(label: 'Pair', value: 'ZEC -> USDC'),
      SwapDetailField(label: 'Refund tx submitted', value: 'refund-zec-tx'),
      SwapDetailField(label: 'Outcome', value: 'Refunded to source address'),
    ],
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1refund-zec-deposit',
    oneClickRecipient: '0xusdc-recipient-refund',
    oneClickRefundTo: 'u1wallet-refund-source',
  ),
  SwapIntent(
    id: 'swap-failed',
    title: 'NEAR to ZEC',
    pair: 'NEAR -> ZEC',
    sellAmount: '14.00 NEAR',
    receiveEstimate: '0.2778 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.failed,
    nextAction: 'Swap route failed',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote failed',
      ),
      SwapStep(
        label: 'Swap route failed',
        state: SwapStepState.warning,
        evidence: 'No funds moved',
      ),
    ],
    exposure: [
      SwapDetailField(
        label: 'Source-chain visibility',
        value: 'deposit not observed',
      ),
      SwapDetailField(label: 'Third-party data', value: 'failed quote id'),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-failed'),
      SwapDetailField(label: 'Pair', value: 'NEAR -> ZEC'),
      SwapDetailField(label: 'Swap route failed', value: 'No funds moved'),
      SwapDetailField(label: 'Outcome', value: 'failed'),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.near,
    depositAddress: 'near-failed-deposit.near',
    oneClickRefundTo: 'rowan.near',
  ),
  SwapIntent(
    id: 'swap-2a11',
    title: 'ZEC to NEAR',
    pair: 'ZEC -> NEAR',
    sellAmount: '0.7500 ZEC',
    receiveEstimate: '37.8 NEAR',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: 'Copy redacted receipt',
    steps: [
      SwapStep(
        label: 'Quote locked',
        state: SwapStepState.done,
        evidence: 'Quote 2a11',
      ),
      SwapStep(
        label: 'Deposit observed',
        state: SwapStepState.done,
        evidence: 'Height 2,860,009',
      ),
      SwapStep(
        label: 'Destination transaction submitted',
        state: SwapStepState.done,
        evidence: 'NEAR tx final',
      ),
      SwapStep(
        label: 'Delivery completed',
        state: SwapStepState.done,
        evidence: 'Provider route final',
      ),
    ],
    exposure: [
      SwapDetailField(
        label: 'Deposit address',
        value: 'one-time transparent address',
      ),
      SwapDetailField(label: 'Transparent window', value: 'closed'),
      SwapDetailField(label: 'Shareable receipt', value: 'redacted'),
    ],
    receipt: [
      SwapDetailField(label: 'Swap id', value: 'swap-2a11'),
      SwapDetailField(label: 'Pair', value: 'ZEC -> NEAR'),
      SwapDetailField(label: 'Status', value: 'complete'),
    ],
  ),
];
