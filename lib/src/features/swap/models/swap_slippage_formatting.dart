String formatSwapSlippage(int bps) {
  return '${formatSwapSlippageValue(bps)}%';
}

String formatSwapSlippageValue(int bps) {
  final value = bps / 100;
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  if (bps % 10 == 0) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}
