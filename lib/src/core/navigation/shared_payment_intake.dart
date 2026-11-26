/// Resolves one complete shared address, payment URI, or Vizor Gift Card URL.
/// Text and QR images use the same rules. Only surrounding whitespace is
/// removed; prose, wrappers, captions, and multiple values are never searched
/// or repaired. URL values must percent-encode whitespace and non-ASCII text.
/// Gift Card URLs remain in their own host-first lane and are never logged.
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

  /// A complete payment URI contains raw whitespace or unencoded characters.
  malformedPayment,

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
    malformedPayment => l10n.paymentUriMalformed,
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
          [final code] => resolveSharedText(code),
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

/// Accepts the entire payload or rejects it. Never extract a payable prefix:
/// trimming an unencoded label could otherwise drop an amount or a required
/// parameter. The existing payment lane validates the complete ZIP-321 URI.
SharedPaymentOutcome resolveSharedText(String text) {
  final raw = text.trim();
  if (!_completePayload.hasMatch(raw)) {
    return raw.toLowerCase().startsWith('zcash:')
        ? SharedPaymentNotice.malformedPayment
        : SharedPaymentNotice.noPayment;
  }
  switch (classifyIncomingLink(raw)) {
    case IncomingPaymentRequestLink(:final raw):
      return SharedPaymentRequest(raw);
    case IncomingGiftCardLink():
      return SharedGiftCard(raw);
    case IncomingVizorHomeLink() || IncomingLinkUnknown():
      return _addressPattern.hasMatch(raw)
          ? SharedPaymentRequest('zcash:$raw')
          : SharedPaymentNotice.noPayment;
  }
}

final _completePayload = RegExp(r'^[!-~]+$');
final _addressPattern = RegExp(
  '^$zcashAddressShape'
  r'$',
);
