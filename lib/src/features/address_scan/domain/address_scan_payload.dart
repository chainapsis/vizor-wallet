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
    if (_hasRepeatedAddressKey(raw, uri)) return null;
    // `Uri.queryParameters` decodes every name and value, so a hostile escape
    // (`%FF`) throws out of the read. Recovery fails closed instead: refusing
    // hands the raw payload back, which downstream validation rejects.
    final query = _tryQueryParameters(uri);
    if (query == null) return null;
    final queryAddress = query['address']?.trim();
    if (queryAddress != null && queryAddress.isNotEmpty) return queryAddress;
    final path = _tryDecodeComponent(uri.path).trim();
    if (path.isNotEmpty) return path;
    // `zcash://<address>` is not valid ZIP-321 (the parser rejects `//`), but
    // it is a shape scanners produce. Recover the authority from the raw
    // string: `uri.host` is lowercased, which corrupts the mixed case of a
    // transparent or TEX address.
    return _zcashAuthorityFromRaw(raw) ?? _indexedZcashAddressFromUri(uri);
  }
}

final _indexedAddressKeyPattern = RegExp(r'^address\.([1-9][0-9]{0,3})$');

/// Whether the payload names an `address` or `address.N` slot more than once.
///
/// The query is read off the raw string rather than `Uri.queryParameters`,
/// which has already collapsed the repeats this looks for — but the names are
/// compared *decoded*, the way `Uri.queryParameters` will read them: ZIP-321
/// forbids percent-encoded names, so `%61ddress` is refused by the parser and
/// lands here, where it must count as a second `address`, not a stranger. A
/// name that cannot be decoded is compared as written; it cannot alias
/// `address`.
///
/// Two shapes beyond the plain repeat count as ambiguous:
///
///  * The *positional* address (`zcash:<addr>…`, or the `zcash://<addr>`
///    authority scanners produce) is the address of paramindex 0 — the same
///    slot a bare `address=` names. `zcash:u1REAL?address=u1ATTACKER` is
///    therefore a repeat, and recovering the query value would hand the scan
///    the appended address instead of the one the payload plainly reads as.
///  * A percent-encoded address key beside *any* other address key. The
///    encoded name can never be a legitimate paramindex-0 payment, so
///    `%61ddress` next to `address.1` has no single recipient either.
bool _hasRepeatedAddressKey(String raw, Uri uri) {
  final seen = <String>{};
  final positional = uri.path.trim().isNotEmpty
      ? uri.path
      : _zcashAuthorityFromRaw(raw);
  if (positional != null && positional.trim().isNotEmpty) {
    seen.add('address');
  }

  final queryStart = raw.indexOf('?');
  if (queryStart == -1) return false;
  var query = raw.substring(queryStart + 1);
  final fragmentStart = query.indexOf('#');
  if (fragmentStart != -1) query = query.substring(0, fragmentStart);

  var sawEncodedAddressKey = false;
  for (final param in query.split('&')) {
    if (param.isEmpty) continue;
    final separator = param.indexOf('=');
    final rawName = separator == -1 ? param : param.substring(0, separator);
    final name = _decodedQueryName(rawName);
    if (name != 'address' && !_indexedAddressKeyPattern.hasMatch(name)) {
      continue;
    }
    if (!seen.add(name)) return true;
    if (rawName != name) sawEncodedAddressKey = true;
  }
  return sawEncodedAddressKey && seen.length > 1;
}

String _decodedQueryName(String rawName) {
  try {
    return Uri.decodeQueryComponent(rawName);
  } on ArgumentError {
    return rawName;
  } on FormatException {
    return rawName;
  }
}

/// [uri]'s decoded query, or null when a percent-escape in a name or a value
/// cannot be decoded. `Uri.queryParameters` throws in that case, and a scanned
/// payload must never turn into an exception escaping the scan callback.
Map<String, String>? _tryQueryParameters(Uri uri) {
  try {
    return uri.queryParameters;
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
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
  final query = _tryQueryParameters(uri);
  if (query == null) return null;

  int? lowestIndex;
  String? lowestAddress;
  for (final entry in query.entries) {
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
