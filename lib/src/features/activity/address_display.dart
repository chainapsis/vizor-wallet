/// Shortens a (long) address for display: first 10 + '...' + last 10 chars.
/// Returns the address unchanged when it is already short.
String truncateAddress(String address) {
  if (address.length <= 20) return address;
  return '${address.substring(0, 10)}...${address.substring(address.length - 10)}';
}
