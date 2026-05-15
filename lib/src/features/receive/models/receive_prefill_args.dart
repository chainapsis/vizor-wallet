enum ReceivePrefillAddressType { shielded, transparent }

class ReceivePrefillArgs {
  const ReceivePrefillArgs({
    required this.source,
    required this.title,
    required this.detail,
    this.addressType = ReceivePrefillAddressType.shielded,
  });

  final String source;
  final String title;
  final String detail;
  final ReceivePrefillAddressType addressType;

  String get fingerprint => '$source|$title|$detail|${addressType.name}';
}
