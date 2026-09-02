import '../../../core/zcash/zip321_payment_request.dart';

String? normalizeAddressScanPayload(String? input) {
  final trimmed = input?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty) return trimmed;

  final scheme = uri.scheme.toLowerCase();
  return switch (scheme) {
    'zcash' => _zcashAddressFromUri(trimmed, uri) ?? trimmed,
    'ethereum' || 'eth' => _ethereumAddressFromUri(uri) ?? trimmed,
    'near' ||
    'bitcoin' ||
    'litecoin' ||
    'dogecoin' ||
    'solana' ||
    'tron' => _genericAddressFromUri(uri) ?? trimmed,
    _ => trimmed,
  };
}

String? _zcashAddressFromUri(String raw, Uri uri) {
  try {
    return Zip321PaymentRequest.parse(raw).primaryPayment.address.trim();
  } on Zip321ParseException {
    // A scan only needs the recipient, so a ZIP-321 request we refuse for an
    // unrelated reason (an unsupported memo, say) must still surrender its
    // address.
    //
    // But a request the parser refused *because it is ambiguous* has no single
    // recipient to recover. `zcash:?address.1=u1REAL&address.1=u1ATTACKER` is
    // the shape that matters: `Uri.queryParameters` keeps the last value, so
    // recovering here would hand the scan the attacker's address. Refuse
    // instead, and let the caller surface the failure.
    if (_hasRepeatedAddressKey(raw)) return null;
    final queryAddress = uri.queryParameters['address']?.trim();
    if (queryAddress != null && queryAddress.isNotEmpty) return queryAddress;
    final path = Uri.decodeComponent(uri.path).trim();
    if (path.isNotEmpty) return path;
    // `zcash://<address>` is not valid ZIP-321 (the parser rejects `//`), but
    // it is a shape scanners produce. Recover the authority from the raw
    // string: `uri.host` is lowercased, which corrupts the mixed case of a
    // transparent or TEX address.
    return _zcashAuthorityFromRaw(raw) ?? _indexedZcashAddressFromUri(uri);
  }
}

final _indexedAddressKeyPattern = RegExp(r'^address\.([1-9][0-9]{0,3})$');

/// Whether the raw query repeats an `address` or `address.N` key.
///
/// Read off the raw string rather than `Uri.queryParameters`, which has
/// already collapsed the repeats this looks for — but compare the names
/// *decoded*, the way `Uri.queryParameters` will read them: ZIP-321 forbids
/// percent-encoded names, so `%61ddress` is refused by the parser and lands
/// here, where it must count as a second `address`, not a stranger. A name
/// that cannot be decoded is compared as written; it cannot alias `address`.
bool _hasRepeatedAddressKey(String raw) {
  final queryStart = raw.indexOf('?');
  if (queryStart == -1) return false;
  var query = raw.substring(queryStart + 1);
  final fragmentStart = query.indexOf('#');
  if (fragmentStart != -1) query = query.substring(0, fragmentStart);

  final seen = <String>{};
  for (final param in query.split('&')) {
    if (param.isEmpty) continue;
    final separator = param.indexOf('=');
    final rawName = separator == -1 ? param : param.substring(0, separator);
    final name = _decodedQueryName(rawName);
    if (name != 'address' && !_indexedAddressKeyPattern.hasMatch(name)) {
      continue;
    }
    if (!seen.add(name)) return true;
  }
  return false;
}

String _decodedQueryName(String rawName) {
  try {
    return Uri.decodeQueryComponent(rawName);
  } on ArgumentError {
    return rawName;
  }
}

/// The authority of a `zcash://<authority>...` string, exactly as written.
String? _zcashAuthorityFromRaw(String raw) {
  const prefix = 'zcash://';
  if (raw.length <= prefix.length) return null;
  if (raw.substring(0, prefix.length).toLowerCase() != prefix) return null;

  final rest = raw.substring(prefix.length);
  var end = rest.length;
  for (final index in [
    rest.indexOf('?'),
    rest.indexOf('/'),
    rest.indexOf('#'),
  ]) {
    if (index != -1 && index < end) end = index;
  }
  final authority = rest.substring(0, end);
  if (authority.isEmpty) return null;
  final decoded = _tryDecodeComponent(authority).trim();
  return decoded.isEmpty ? null : decoded;
}

String _tryDecodeComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}

String? _indexedZcashAddressFromUri(Uri uri) {
  int? lowestIndex;
  String? lowestAddress;
  for (final entry in uri.queryParameters.entries) {
    final match = _indexedAddressKeyPattern.firstMatch(entry.key);
    if (match == null) continue;
    final address = entry.value.trim();
    if (address.isEmpty) continue;
    final index = int.parse(match.group(1)!);
    if (lowestIndex == null || index < lowestIndex) {
      lowestIndex = index;
      lowestAddress = address;
    }
  }
  return lowestAddress;
}

String? _ethereumAddressFromUri(Uri uri) {
  final queryAddress = uri.queryParameters['address']?.trim();
  if (queryAddress != null && queryAddress.isNotEmpty) return queryAddress;

  var path = Uri.decodeComponent(uri.path).trim();
  if (path.startsWith('pay-')) {
    path = path.substring(4);
  }
  if (path.isEmpty) return _genericAddressFromUri(uri);

  final stop = _firstPositiveIndex([
    path.indexOf('@'),
    path.indexOf('/'),
    path.indexOf('?'),
  ]);
  final address = stop == null ? path : path.substring(0, stop);
  return address.trim().isEmpty ? null : address.trim();
}

String? _genericAddressFromUri(Uri uri) {
  final queryAddress = uri.queryParameters['address']?.trim();
  if (queryAddress != null && queryAddress.isNotEmpty) return queryAddress;

  final path = Uri.decodeComponent(uri.path).trim();
  if (path.isNotEmpty) return path;

  final host = Uri.decodeComponent(uri.host).trim();
  if (host.isNotEmpty) return host;
  return null;
}

int? _firstPositiveIndex(Iterable<int> values) {
  final positives = values.where((value) => value > 0).toList()..sort();
  return positives.isEmpty ? null : positives.first;
}
