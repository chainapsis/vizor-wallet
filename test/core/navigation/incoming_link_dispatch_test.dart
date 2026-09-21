import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/incoming_link_dispatch.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';

// One native channel carries two products, so the classifier is the only place
// that decides which parser a link is allowed to reach. The order it asks its
// questions in is a privacy property, not a style choice: a Gift Card link's
// fragment carries a 24-word mnemonic, and the ZIP-321 parser puts fragments
// of what it rejected into a log line.
void main() {
  final host = VizorDeepLink.host;

  group('host is tested before scheme', () {
    test('a Gift Card link on the Vizor origin is a gift card', () {
      final target = classifyIncomingLink(
        'https://$host/payment-links/open#v1=abcdef',
      );
      expect(target, isA<IncomingGiftCardLink>());
    });

    test('an unrecognised path on the Vizor origin is unknown, not a payment '
        'request', () {
      // The fragment is the mnemonic-bearing part. Falling through to the
      // scheme check would be harmless here (the scheme is https), but falling
      // through to the ZIP-321 parser — which is what a scheme-first
      // classifier that treats "not a gift card" as "try the other one" would
      // do — is how it ends up in a log line.
      final target = classifyIncomingLink(
        'https://$host/not-a-route#v1=abcdef',
      );
      expect(target, isA<IncomingLinkUnknown>());
    });

    test('the bare Vizor origin opens home', () {
      expect(
        classifyIncomingLink('https://$host/'),
        isA<IncomingVizorHomeLink>(),
      );
      expect(
        classifyIncomingLink('https://$host'),
        isA<IncomingVizorHomeLink>(),
      );
    });

    test('another host is unknown', () {
      expect(
        classifyIncomingLink('https://evil.example/payment-links/open#v1=x'),
        isA<IncomingLinkUnknown>(),
      );
    });
  });

  group('zcash scheme', () {
    test('a plain request is a payment request', () {
      final target = classifyIncomingLink('zcash:u1recipient?amount=1');
      expect(target, isA<IncomingPaymentRequestLink>());
      expect(
        (target as IncomingPaymentRequestLink).raw,
        'zcash:u1recipient?amount=1',
      );
    });

    test('host-like text after the scheme is still a payment request', () {
      // `zcash://link.vizor.cash/...` parses with a *host* equal to the Gift
      // Card origin's host. Only the scheme separates it, so this pins that
      // the host test cannot swallow a `zcash:` link.
      for (final raw in [
        'zcash://$host/payment-links/open?amount=1',
        'zcash://$host',
        'ZCASH:u1recipient?amount=1',
      ]) {
        expect(
          classifyIncomingLink(raw),
          isA<IncomingPaymentRequestLink>(),
          reason: raw,
        );
      }
    });

    test('surrounding whitespace is trimmed before classifying', () {
      final target = classifyIncomingLink('  zcash:u1recipient?amount=1\n');
      expect(target, isA<IncomingPaymentRequestLink>());
      expect(
        (target as IncomingPaymentRequestLink).raw,
        'zcash:u1recipient?amount=1',
      );
    });

    test('a malformed request still reaches the payment-request lane', () {
      // It is the only lane that can tell the payer their link is broken;
      // dropping it here would make a bad link do nothing at all.
      expect(
        classifyIncomingLink('zcash:u1recipient?amount=not-a-number'),
        isA<IncomingPaymentRequestLink>(),
      );
    });
  });

  group('everything else is unknown', () {
    test('other schemes and junk', () {
      for (final raw in [
        'vizor://payment-links/open',
        'http://$host/payment-links/open',
        'mailto:someone@example.com',
        '',
        'not a uri at all',
      ]) {
        expect(
          classifyIncomingLink(raw),
          isA<IncomingLinkUnknown>(),
          reason: raw,
        );
      }
    });
  });
}
