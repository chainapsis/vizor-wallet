import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/core/navigation/incoming_link_entry_policy.dart';

void main() {
  for (final kind in IncomingLinkKind.values) {
    test(
      '$kind protects a route-less signing surface and names the deferral',
      () {
        final decision = decideIncomingLinkEntry(
          kind: kind,
          location: '/home',
          paymentRequestBlocked: true,
        );
        expect(
          decision.action,
          kind == IncomingLinkKind.home
              ? IncomingLinkEntryAction.ignore
              : IncomingLinkEntryAction.wait,
        );
        expect(decision.notice, isNotNull);
        expect(
          decideIncomingLinkEntry(kind: kind, location: '/home').action,
          IncomingLinkEntryAction.open,
        );
      },
    );
  }
  for (final location in [
    '/send',
    '/send/keystone-sign',
    '/home/shield',
    '/home/ledger-shield',
    '/home/keystone-shield',
    '/voting/poll/1/status',
    '/payment-links/scan',
  ]) {
    test('home protects $location', () {
      expect(
        decideIncomingLinkEntry(
          kind: IncomingLinkKind.home,
          location: location,
          paymentRequestBlocked: location == '/payment-links/scan',
        ).action,
        IncomingLinkEntryAction.ignore,
      );
    });
  }
  test('a payment card can still overlay an ordinary send form', () {
    expect(
      decideIncomingLinkEntry(
        kind: IncomingLinkKind.paymentRequest,
        location: '/send',
      ).action,
      IncomingLinkEntryAction.open,
    );
  });
  test('home does not displace a payment card', () {
    expect(
      decideIncomingLinkEntry(
        kind: IncomingLinkKind.home,
        location: '/settings',
        paymentRequestPresented: true,
      ).action,
      IncomingLinkEntryAction.ignore,
    );
  });
  test('locked links defer to the unlock flow without exposing notices', () {
    for (final kind in IncomingLinkKind.values) {
      expect(
        decideIncomingLinkEntry(
          kind: kind,
          location: '/unlock',
          locked: true,
        ).notice,
        isNull,
      );
    }
  });

  test('every notice resolves to distinct text in each locale', () {
    for (final code in ['en', 'ko', 'zh']) {
      final l10n = lookupAppLocalizations(Locale(code));
      final texts = [
        for (final n in IncomingLinkNotice.values) n.text(l10n),
        for (final n in PaymentUriNotice.values) n.text(l10n),
      ];
      expect(texts.every((t) => t.isNotEmpty), isTrue, reason: code);
      expect(
        texts.toSet().length,
        texts.length - 1, // PaymentUriNotice.busy reuses paymentBusy
        reason: code,
      );
    }
  });
}
