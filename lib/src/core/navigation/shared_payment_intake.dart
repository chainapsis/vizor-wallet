/// Turns content shared from another app into the one link the incoming-link
/// pipeline already serves, or into the notice that says why it cannot.
///
/// Shared text is whatever the sender selected: a bare address, a `zcash:`
/// link, a Vizor Gift Card link, or a whole message with one of those inside
/// it. The links in it are tried first. Failing those, the first
/// address-shaped word is handed on as `zcash:<address>`, so the
/// payment-request lane presents it exactly as it presents a tapped link that
/// names no amount: a card for the address, with the composer collecting the
/// rest. The card's own precheck says whether the address is real, and for
/// which network; checking it here would only repeat that, and would turn a
/// mainnet address shared into a testnet wallet into "no address here".
///
/// Nothing here parses a link. A `zcash:` candidate is handed to the lane
/// unparsed, so a broken one still gets the lane's own rejection sentence,
/// and an `https://` candidate goes through `classifyIncomingLink`, which
/// tests the Vizor host before anything else looks at it. A Gift Card link's
/// fragment carries a mnemonic, and shared text is the one place such a link
/// arrives surrounded by other text, so no part of the text is logged here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/shared_payment_service.dart';
import '../l10n/l10n.dart';
import '../zcash/address_shape.dart';
import 'incoming_link_dispatch.dart';

/// The raw values of the QR codes in the image at [path].
typedef SharedImageQrCodes = Future<List<String>> Function(String path);

/// What a share turned out to be: a link for the lane of its kind, or the
/// notice that says why there is none.
sealed class SharedPaymentOutcome {
  const SharedPaymentOutcome();
}

/// A ZIP-321 request for the payment-request lane, as a tapped `zcash:` link
/// would be. [raw] is unparsed: a broken one gets the lane's own rejection
/// sentence there.
final class SharedPaymentRequest extends SharedPaymentOutcome {
  const SharedPaymentRequest(this.raw);

  final String raw;
}

/// A Gift Card link on the Vizor origin, for the Gift Card intake.
final class SharedGiftCard extends SharedPaymentOutcome {
  const SharedGiftCard(this.link);

  final String link;
}

/// Nothing to dispatch, and why. The outcome carries the code; the toast
/// resolves it with the locale of the moment it is shown.
enum SharedPaymentNotice implements SharedPaymentOutcome {
  /// Shared text holds nothing the app can pay or claim.
  noPayment,

  /// A shared image holds no QR code at all.
  imageNoCode,

  /// A shared image holds more than one QR code: using one of them would be
  /// a guess about which the sender meant.
  imageSeveralCodes,

  /// The image could not be read: not an image, or the runner could not open
  /// what was shared.
  imageUnreadable;

  String text(AppLocalizations l10n) => switch (this) {
    noPayment => l10n.sharedPaymentNoPayment,
    imageNoCode => l10n.sharedPaymentImageNoCode,
    imageSeveralCodes => l10n.sharedPaymentImageSeveralCodes,
    imageUnreadable => l10n.sharedPaymentImageUnreadable,
  };
}

/// Resolves a [SharedPayload] with the QR reader it was given, so the decision
/// table can be exercised without the camera plugin.
class SharedPaymentIntake {
  const SharedPaymentIntake({required this.readQrCodes});

  final SharedImageQrCodes readQrCodes;

  /// Lets go of [payload] unresolved: the copy the runner made for an image
  /// is deleted, as resolving it would have.
  void discard(SharedPayload payload) {
    if (payload case SharedImage(:final path)) _deleteCopy(path);
  }

  Future<SharedPaymentOutcome> resolve(SharedPayload payload) async {
    switch (payload) {
      case SharedText(:final text):
        return resolveSharedText(text);
      case SharedUnreadableImage():
        return SharedPaymentNotice.imageUnreadable;
      case SharedImage(:final path):
        return switch (await _qrCodesIn(path)) {
          null => SharedPaymentNotice.imageUnreadable,
          [] => SharedPaymentNotice.imageNoCode,
          [final code] => resolveSharedCode(code),
          _ => SharedPaymentNotice.imageSeveralCodes,
        };
    }
  }

  /// Reads the codes, then deletes the file whatever happened: it is a copy
  /// the runner made for this one read. Null when the reader failed.
  Future<List<String>?> _qrCodesIn(String path) async {
    try {
      return await readQrCodes(path);
    } catch (error) {
      // The path is this app's own cache file; nothing shared is echoed.
      debugPrint('SharedPaymentIntake: image read failed: $error');
      return null;
    } finally {
      _deleteCopy(path);
    }
  }

  /// Nothing waits on the delete, and a file that is already gone is not an
  /// error.
  static void _deleteCopy(String path) {
    unawaited(File(path).delete().then<void>((_) {}, onError: (_) {}));
  }
}

/// The first thing in [text] the app serves: a `zcash:` link as written, a
/// Gift Card link on the Vizor origin as written, or `zcash:<address>` for
/// the first address-shaped word.
///
/// Text that is nothing but a link, which is what a QR code holds and what
/// a copied link pastes as, is handed on untouched: a request can legally end
/// in `!` or `)`, and there is no prose around it to have put them there.
SharedPaymentOutcome resolveSharedText(String text) {
  for (final link in sharedPaymentLinks(text)) {
    final target = classifyIncomingLink(link);
    if (target case IncomingPaymentRequestLink(:final raw)) {
      return SharedPaymentRequest(raw);
    }
    if (target case IncomingGiftCardLink()) return SharedGiftCard(link);
  }
  final address = sharedPaymentAddress(text);
  return address == null
      ? SharedPaymentNotice.noPayment
      : SharedPaymentRequest('zcash:$address');
}

/// The text of a QR code from a shared image. A code holds one link and no
/// prose, so a `zcash:` link is handed on as written, whatever characters it
/// holds: one that is not a valid request is rejected whole by the lane,
/// rather than cut at a character the text rules would end it on. The
/// camera scanner hands it on the same way.
SharedPaymentOutcome resolveSharedCode(String code) {
  final trimmed = code.trim();
  if (trimmed.toLowerCase().startsWith('zcash:')) {
    if (classifyIncomingLink(trimmed) case IncomingPaymentRequestLink(
      :final raw,
    )) {
      return SharedPaymentRequest(raw);
    }
  }
  return resolveSharedText(code);
}

/// Every `zcash:` or `https://` link in [text], in text order, once each. A
/// link runs through printable ASCII, which is all a `zcash:` request or a
/// link on the Vizor origin is made of, so a typographic quote or a sentence
/// in Chinese ends it on its own. It then loses the ASCII prose wrapped
/// around its end, see [_unwrapLink], unless it is the whole text. A
/// `zcash:` link cut off inside a word is carried on, see [_uncutLink].
List<String> sharedPaymentLinks(String text) {
  final trimmed = text.trim();
  final matches = _linkPattern.allMatches(trimmed).toList();
  if (matches case [
    final only,
  ] when only.start == 0 && only.end == trimmed.length) {
    return [trimmed];
  }
  return {
    for (final match in matches)
      _uncutLink(trimmed, match) ?? _unwrapLink(trimmed, match),
  }.toList();
}

/// The `zcash:` link in [match] carried on past where its ASCII stopped, when
/// it stopped inside a word and the request goes on after it; otherwise null,
/// to keep the ASCII form.
///
/// ZIP-321 percent-encodes a label, but a hand-written request can carry one
/// raw: `?label=咖啡&amount=1`. Cut at the first non-ASCII letter, that is a
/// smaller request that still parses, with its amount and memo gone. Carried
/// on whole, it reaches the lane, which rejects it with its own sentence. A
/// link whose cut leaves no parameter after it is prose run up against the
/// link (`amount=1付款`) and keeps its ASCII form.
String? _uncutLink(String text, RegExpMatch match) {
  if (_wordChar.matchAsPrefix(text, match.end) == null) return null;
  final longer = _uncutLinkPattern.matchAsPrefix(text, match.start);
  if (longer == null) return null;
  final link = _unwrapLink(text, longer);
  final cut = match.end - match.start;
  if (link.length <= cut) return null;
  return _laterParameter.hasMatch(link.substring(cut)) ? link : null;
}

/// The first word in [text] shaped like a Zcash address, or null.
///
/// The canonical shape, bounded on both sides by a character outside the
/// address alphabet: `\b` would count a Markdown `_` as part of the word and
/// miss `_u1…_`. An address inside a link is found too (an explorer URL
/// ending in one), because the link itself classifies as nothing the app
/// serves.
String? sharedPaymentAddress(String text) =>
    _addressPattern.firstMatch(text)?.group(0);

/// A `zcash:` or `https://` link through the printable ASCII that follows it.
final _linkPattern = RegExp(r'(?:zcash:|https://)[!-~]+', caseSensitive: false);

/// A `zcash:` link through the ASCII, letters, digits and marks that follow
/// it, in any script, up to the next link; see [_uncutLink]. Stopping there
/// keeps a request run up against the next link its own, and keeps text of
/// many such links linear.
final _uncutLinkPattern = RegExp(
  r'zcash:(?:(?!zcash:|https://)[!-~\p{L}\p{N}\p{M}])+',
  caseSensitive: false,
  unicode: true,
);

/// A letter, digit or mark in any script.
final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

/// A ZIP-321 parameter after the first: `&amount=`, `&memo.1=`.
final _laterParameter = RegExp(r'&[A-Za-z][A-Za-z0-9.-]*=');

final _addressPattern = RegExp(
  '(?<![0-9A-Za-z])$zcashAddressShape(?![0-9A-Za-z])',
);

/// The link in [match] without the prose wrapped around its end.
///
/// A link the sender wrapped, in quotes, brackets or Markdown emphasis, is
/// kept whole inside the wrapper: the wrapper says where the link ends, and
/// a `!`, `)` or `.` inside it is the link's own, legal in a ZIP-321 value.
/// The wrapper is the twin of what sits right before the link, a
/// typographic one just after the match (`“…”`, `「…」`) or an ASCII one at
/// its end (`(…)`, `"…"`, `**…**`, where a run is matched whole), possibly
/// behind sentence punctuation the sender put after the wrapper.
///
/// Outside a wrapper, what prose puts after a link is cut: sentence
/// punctuation, a closing bracket the link never opened, or a quote it holds
/// an odd number of. Nothing else is. An apostrophe and parentheses are
/// legal inside a ZIP-321 query value, so stopping a link at the first one
/// would silently drop every parameter after `label=Bob's`, and `_` is a
/// base64url character, so a memo can legitimately end in one: an emphasis
/// mark is only ever cut as the twin of one before the link. What is trimmed
/// can only ever end a `label` or `message`, never an address, an amount or
/// a memo, and a link at the end of a sentence is far more common than a
/// label that ends in one.
String _unwrapLink(String text, Match match) {
  final link = match.group(0)!;
  final opener = match.start > 0 ? text[match.start - 1] : '';
  final after = match.end < text.length ? text[match.end] : '';
  if (_typographicOpenerOf[after] == opener) return link;
  // The ASCII twin of the opener, and how long a run of openers there is.
  final closer = _closerOf[opener];
  var openers = 0;
  while (closer != null && match.start - 1 - openers >= 0) {
    if (text[match.start - 1 - openers] != opener) break;
    openers++;
  }
  // Counted once; trimming keeps the counts current. Recounting per trimmed
  // character would let a link followed by thousands of brackets stall the
  // UI isolate.
  final counts = <String, int>{};
  for (var i = 0; i < link.length; i++) {
    final char = link[i];
    if (_counted.contains(char)) counts[char] = (counts[char] ?? 0) + 1;
  }
  int count(String char) => counts[char] ?? 0;
  var end = link.length;
  while (end > 0) {
    final last = link[end - 1];
    if (last == closer) {
      // The wrapper: the run of closers that matches the run of openers, and
      // nothing inside it is touched.
      var run = 0;
      while (run < openers &&
          end - 1 - run > 0 &&
          link[end - 1 - run] == closer) {
        run++;
      }
      return link.substring(0, end - run);
    }
    final wraps = switch (last) {
      '.' || ',' || '!' || '?' || ';' || ':' => true,
      ')' || ']' || '>' => count(_openerOf[last]!) < count(last),
      '"' || "'" => count(last).isOdd,
      _ => false,
    };
    if (!wraps) break;
    if (counts.containsKey(last)) counts[last] = count(last) - 1;
    end--;
  }
  return link.substring(0, end);
}

/// Each ASCII closer and its opener; a quote or an emphasis mark is its own.
const _openerOf = {
  ')': '(', ']': '[', '>': '<', //
  '"': '"', "'": "'", '*': '*', '_': '_',
};

/// Each ASCII opener and its closer.
final _closerOf = {for (final pair in _openerOf.entries) pair.value: pair.key};

/// Typographic closers and their openers; these never enter the match.
const _typographicOpenerOf = {
  '”': '“', '’': '‘', '»': '«', //
  '）': '（', '」': '「', '』': '『', '】': '【', '〉': '〈', '》': '《',
};

final _counted = {..._openerOf.keys, ..._openerOf.values};
