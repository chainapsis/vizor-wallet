class SendPrefillArgs {
  const SendPrefillArgs({
    required this.id,
    required this.source,
    required this.address,
    this.amountText,
    this.memoText,
    this.label,
    this.message,
  });

  final String id;
  final String source;
  final String address;
  final String? amountText;
  final String? memoText;
  final String? label;
  final String? message;

  String get fingerprint =>
      '$id|$address|${amountText ?? ''}|${memoText ?? ''}';
}
