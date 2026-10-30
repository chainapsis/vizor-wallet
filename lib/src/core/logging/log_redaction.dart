/// Masks identifier-shaped values before a line reaches a log sink.
///
/// This is a safety net, not a privacy contract. It recognises values only by
/// their shape: addresses, viewing and spending keys, 32-byte hashes, UUIDs,
/// absolute device paths, URL paths and queries, payment URIs and Keystone URs.
/// Amounts, balances, account names, labels, memos, seed words and other free
/// text pass through unchanged and have to be kept out at the call site.
///
/// The rules and their order are mirrored in `rust/src/log_redaction.rs`, and
/// both test suites run `test/fixtures/log_redaction_vectors.json`.
library;

import 'package:flutter/foundation.dart';

/// Redacts [text] in bounded passes, stopping when it no longer changes.
String redactLogText(String text) => _redactWithPassLimit(text, _maxPasses);

String _redactWithPassLimit(String text, int limit) {
  var current = text;
  for (var pass = 0; pass < limit; pass++) {
    if (!_mayContainSensitiveShape(current)) break;
    final next = _redactOnce(current);
    if (next == current) break;
    current = next;
  }
  return current;
}

// A false positive only runs the existing rules; a false negative would leave
// data unmasked. Every rule below must imply one of these cheap conditions.
// Extend this prefilter and the shared vectors when adding a masking rule.
bool _mayContainSensitiveShape(String text) {
  var hexRun = 0;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    // Every path, URL and Keystone UR contains a slash or backslash.
    if (code == 47 || code == 92) return true;
    final lower = code | 32;
    final isHex = (code >= 48 && code <= 57) || (lower >= 97 && lower <= 102);
    if (isHex) {
      if (++hexRun >= 32) return true;
    } else {
      // A UUID begins with eight hex digits followed by a hyphen.
      if (code == 45 && hexRun >= 8) return true;
      hexRun = 0;
    }
    // All supported Bech32 address/key HRPs end in an ASCII letter, then '1'.
    if (code == 49 && i > 0) {
      final previous = text.codeUnitAt(i - 1) | 32;
      if (previous >= 97 && previous <= 122) return true;
    }
    // Transparent addresses also include t2/t3/tm, without a Bech32 separator.
    if (lower == 116 && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1) | 32;
      if (next == 49 || next == 50 || next == 51 || next == 109) return true;
    }
    if (code == 58 &&
        (_endsWithAscii(text, i, 'zcash') || _endsWithAscii(text, i, 'ur'))) {
      return true;
    }
  }
  return false;
}

bool _endsWithAscii(String text, int end, String value) {
  if (end < value.length) return false;
  for (var i = 0; i < value.length; i++) {
    if ((text.codeUnitAt(end - value.length + i) | 32) != value.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

// Track only our own wrappers, without retaining discarded output callbacks
// or any log text. Never infer that a message is safe from its contents.
final _redactingOutputs =
    Expando<({DebugPrintCallback output, int passLimit})>();

/// Wraps [next] so every message is redacted before it is printed. Coalesces
/// our own wrappers into one scan with their combined pass budget, without
/// changing a captured earlier wrapper or bypassing another caller's output.
DebugPrintCallback redactingDebugPrint(DebugPrintCallback next) {
  final earlier = _redactingOutputs[next];
  final output = earlier?.output ?? next;
  final limit = _maxPasses + (earlier?.passLimit ?? 0);
  void wrapped(String? message, {int? wrapWidth}) => output(
    message == null ? null : _redactWithPassLimit(message, limit),
    wrapWidth: wrapWidth,
  );
  final DebugPrintCallback callback = wrapped;
  _redactingOutputs[callback] = (output: output, passLimit: limit);
  return callback;
}

/// Redacts before printing, even before installation or after another caller
/// replaces [debugPrint]. Only bypasses our own wrapper's redundant scan;
/// its downstream output still runs, with the same wrapping and throttling.
void printRedactedLog(String? message, {int? wrapWidth}) {
  final current = debugPrint;
  final target = _redactingOutputs[current];
  // Preserve every coalesced wrapper's passes as well as the caller's, but
  // stop when stable instead of starting redundant scans.
  final limit = _maxPasses + (target?.passLimit ?? 0);
  (target?.output ?? current)(
    message == null ? null : _redactWithPassLimit(message, limit),
    wrapWidth: wrapWidth,
  );
}

/// Prints an uncaught asynchronous error through the redactor instead of the
/// engine's own unhandled-exception report, which would print it verbatim.
bool reportUncaughtError(Object error, StackTrace stack) {
  printRedactedLog('Unhandled Exception: $error\n$stack');
  return true;
}

/// Routes the app's print paths through [redactLogText] in every build mode:
/// direct `debugPrint` calls, framework error dumps (which print through
/// `debugPrint`), and uncaught asynchronous errors.
void installLogRedaction() {
  debugPrint = redactingDebugPrint(debugPrint);
  PlatformDispatcher.instance.onError ??= reportUncaughtError;
}

// A pass only replaces values with tokens, so a second pass finishes any match
// a token made possible. The bound is a backstop, not an expected depth.
const _maxPasses = 4;

// Zakura protocol HRPs (zakura-protocol 3.0.0 constants/{mainnet,testnet,
// regtest}.rs). Ironwood shares the Orchard receiver, so it has no HRP of its
// own. Longer prefixes come first.
const _keyHrps = [
  'secret-extended-key-regtest',
  'secret-extended-key-main',
  'secret-extended-key-test',
  'zxviewregtestsapling',
  'zxviewtestsapling',
  'uviewregtest',
  'uivkregtest',
  'uviewtest',
  'uivktest',
  'zxviews',
  'uview',
  'uivk',
];
const _addressHrps = [
  'zregtestsapling',
  'ztestsapling',
  'texregtest',
  'uregtest',
  'textest',
  'utest',
  'tex',
  'zs',
  'u',
];
const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
// The shortest encoding above is a TEX address: 20 bytes, 38 characters.
const _bech32MinData = 38;
// Base58Check prefixes 0x1cb8/0x1cbd (mainnet), 0x1d25/0x1cba (test/regtest)
// encode as t1/t3 and tm/t2; every transparent address is 35 characters.
const _transparent = r'(?:t1|t3|tm|t2)[1-9A-HJ-NP-Za-km-z]{33}';

// Explicit ASCII classes keep Dart and Rust matching the same characters.
const _space = r'\t\n\v\f\r ';
const _notAlnum = r'[^0-9A-Za-z]';
const _pathStart = r'(^|file://|[^0-9A-Za-z_.~/\\\-])';
const _pathChar = '[^$_space\'"<>|:;,()\\[\\]{}\\\\]';
const _unixRoots =
    'Users|home|root|private|var|tmp|data|storage|sdcard|mnt|media|Volumes|run';

String _bech32(List<String> hrps) {
  final lower = hrps.join('|');
  final upper = hrps.map((hrp) => hrp.toUpperCase()).join('|');
  final upperCharset = _bech32Charset.toUpperCase();
  return '(?:(?:$lower)1[$_bech32Charset]{$_bech32MinData,}'
      '|(?:$upper)1[$upperCharset]{$_bech32MinData,})';
}

final _url = RegExp(
  '\\b([A-Za-z][A-Za-z0-9+.\\-]*://)'
  '(?:[^$_space/?#@\'"<>]*@)?'
  '([^$_space/?#\'"<>]+)'
  '([/?#][^$_space\'"<>]+)?',
);
final _windowsPath = RegExp(
  '$_pathStart([A-Za-z]:[\\\\/][^$_space\'"<>|:;,()\\[\\]{}]*)',
);
final _unixPath = RegExp(
  '$_pathStart(/(?:$_unixRoots)/(?:/Application Support|$_pathChar)*)',
);
final _uuid = RegExp(
  '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _hex = RegExp('(?:0[xX])?[0-9a-fA-F]{32,}');
// Match both opaque payloads together so an embedded URI cannot be replaced
// before its enclosing URI. Group 1 distinguishes payment URIs from URs.
final _opaqueUri = RegExp(
  '\\b(?:([zZ][cC][aA][sS][hH]:)|[uU][rR]:[A-Za-z0-9\\-]+/)'
  '[^$_space\'"<>]+',
);
final _key = RegExp('($_notAlnum|^)${_bech32(_keyHrps)}');
final _address = RegExp(
  '($_notAlnum|^)(?:${_bech32(_addressHrps)}|$_transparent)',
);

String _redactOnce(String text) => text
    // Component replacements introduce '<' tokens that would truncate a URI.
    .replaceAllMapped(
      _opaqueUri,
      (m) => m[1] == null ? '<ur>' : '<payment-uri>',
    )
    .replaceAllMapped(
      _url,
      (m) => '${m[1]}${m[2]}${m[3] == null ? '' : '/<path>'}',
    )
    // Drive paths first, so `C:/Users/...` is not read as a POSIX path.
    .replaceAllMapped(_windowsPath, (m) => '${m[1]}<path>')
    .replaceAllMapped(_unixPath, (m) => '${m[1]}<path>')
    .replaceAll(_uuid, '<uuid>')
    .replaceAllMapped(_hex, (m) {
      final value = m[0]!;
      // The pattern only admits an `x` as the second character of `0x`.
      final prefixed = value[1] == 'x' || value[1] == 'X';
      return value.length - (prefixed ? 2 : 0) == 64 ? '<txid>' : '<hex>';
    })
    .replaceAllMapped(_key, (m) => '${m[1]}<key>')
    .replaceAllMapped(_address, (m) => '${m[1]}<address>');
