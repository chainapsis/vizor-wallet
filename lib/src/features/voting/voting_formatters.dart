String formatVotingPower(BigInt zatoshi) {
  const zatoshiPerZec = 100000000;
  final whole = zatoshi ~/ BigInt.from(zatoshiPerZec);
  final fraction = (zatoshi % BigInt.from(zatoshiPerZec))
      .toInt()
      .toString()
      .padLeft(8, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole ZEC' : '$whole.$fraction ZEC';
}
