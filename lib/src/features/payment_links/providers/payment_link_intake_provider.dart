import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';

enum PaymentLinkIntakeResult { accepted, ignored, rejected }

/// The queue of Gift Card links that arrived but have not been opened yet.
///
/// **Deliberately not the same store as `paymentUriPrefillProvider`**, even
/// though both hold links delivered by the same native channel. A Gift Card is
/// a bearer claim on funds that are *not* in this wallet: losing one loses the
/// money, so up to [kPaymentLinkIntakeQueueCapacity] of them queue instead of
/// displacing each other, they never expire, and they survive a wallet reset —
/// the claim is still good on whatever wallet the user sets up next. A ZIP-321
/// request is the opposite on all three counts (one at a time, a 10-minute
/// TTL, dropped on reset) because it spends *this* wallet's money.

const kPaymentLinkIntakeQueueCapacity = 16;

class PaymentLinkIntakeState {
  const PaymentLinkIntakeState({
    this.pendingLinks = const [],
    this.errorMessage,
  });

  final List<VizorPaymentLink> pendingLinks;
  final String? errorMessage;

  VizorPaymentLink? get pendingLink =>
      pendingLinks.isEmpty ? null : pendingLinks.first;
}

/// An opened preview keeps its intake slot until it is prepared or abandoned.
/// Unlock can therefore return an accepted Card without evicting another one.
class PaymentLinkPreviewReservation {
  PaymentLinkPreviewReservation._(this.link, this._finish);

  final VizorPaymentLink link;
  final void Function(bool restore) _finish;

  void release() => _finish(false);

  void restoreAfterRouteDisposal() {
    scheduleMicrotask(() => _finish(true));
  }
}

class PaymentLinkIntakeNotifier extends Notifier<PaymentLinkIntakeState> {
  final _previewReservations = <PaymentLinkPreviewReservation>{};
  @override
  PaymentLinkIntakeState build() => const PaymentLinkIntakeState();

  PaymentLinkIntakeResult receive(String rawUri) {
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null || !VizorPaymentLink.matchesEndpoint(uri)) {
      return PaymentLinkIntakeResult.ignored;
    }

    try {
      final link = VizorPaymentLink.parse(rawUri);
      final pendingLinks = state.pendingLinks;
      // Account and birthday identify a reusable claim wallet, not a duplicate
      // user intent. Only an identical versioned payload can be coalesced.
      final duplicate =
          pendingLinks.any(
            (pending) => pending.hasSameCanonicalPayload(link),
          ) ||
          _previewReservations.any(
            (preview) => preview.link.hasSameCanonicalPayload(link),
          );
      if (duplicate) {
        state = PaymentLinkIntakeState(pendingLinks: pendingLinks);
        return PaymentLinkIntakeResult.accepted;
      }
      if (pendingLinks.length + _previewReservations.length >=
          kPaymentLinkIntakeQueueCapacity) {
        state = PaymentLinkIntakeState(
          pendingLinks: pendingLinks,
          errorMessage: 'Too many payment links are waiting to open.',
        );
        return PaymentLinkIntakeResult.rejected;
      }
      state = PaymentLinkIntakeState(pendingLinks: [...pendingLinks, link]);
      return PaymentLinkIntakeResult.accepted;
    } on FormatException {
      state = PaymentLinkIntakeState(
        pendingLinks: state.pendingLinks,
        errorMessage: 'Payment link could not be opened.',
      );
      return PaymentLinkIntakeResult.rejected;
    }
  }

  /// Keeps the Card chosen before wallet setup at the front of the queue.
  /// Other arriving links retain their relative order.
  PaymentLinkIntakeResult prioritize(VizorPaymentLink link) {
    final remaining = [
      for (final pending in state.pendingLinks)
        if (!pending.hasSameCanonicalPayload(link)) pending,
    ];
    if (remaining.length + _previewReservations.length >=
        kPaymentLinkIntakeQueueCapacity) {
      state = PaymentLinkIntakeState(
        pendingLinks: state.pendingLinks,
        errorMessage: 'Too many payment links are waiting to open.',
      );
      return PaymentLinkIntakeResult.rejected;
    }
    state = PaymentLinkIntakeState(pendingLinks: [link, ...remaining]);
    return PaymentLinkIntakeResult.accepted;
  }

  /// Unlock can remove the preview while Navigator is building. Restore its
  /// unprepared Card after route teardown, while this intake is still alive.
  void restoreInterruptedPreview(VizorPaymentLink link) {
    scheduleMicrotask(() {
      if (ref.mounted) prioritize(link);
    });
  }

  PaymentLinkPreviewReservation? takePendingForPreview() {
    final link = state.pendingLink;
    if (link == null) return null;
    late final PaymentLinkPreviewReservation reservation;
    reservation = PaymentLinkPreviewReservation._(link, (restore) {
      if (!_previewReservations.remove(reservation) || !ref.mounted) return;
      if (restore) prioritize(link);
    });
    _previewReservations.add(reservation);
    takePending();
    return reservation;
  }

  VizorPaymentLink? takePending() {
    final link = state.pendingLink;
    if (link == null) return null;
    state = PaymentLinkIntakeState(
      pendingLinks: state.pendingLinks.sublist(1),
      errorMessage: state.errorMessage,
    );
    return link;
  }

  /// Drops every queued copy of [link] once another flow owns it.
  void discard(VizorPaymentLink link) {
    state = PaymentLinkIntakeState(
      pendingLinks: [
        for (final pending in state.pendingLinks)
          if (!pending.hasSameCanonicalPayload(link)) pending,
      ],
      errorMessage: state.errorMessage,
    );
  }

  void clearError() {
    state = PaymentLinkIntakeState(pendingLinks: state.pendingLinks);
  }
}

final paymentLinkIntakeProvider =
    NotifierProvider<PaymentLinkIntakeNotifier, PaymentLinkIntakeState>(
      PaymentLinkIntakeNotifier.new,
    );
