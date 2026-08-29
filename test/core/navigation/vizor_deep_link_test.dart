import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';

void main() {
  group('VizorDeepLink', () {
    test(
      'uses the configured base URL and defines the production default',
      () {
        const configuredBaseUrl = String.fromEnvironment(
          kVizorDeeplinkBaseUrlEnvKey,
          defaultValue: kDefaultVizorDeeplinkBaseUrl,
        );

        expect(kDefaultVizorDeeplinkBaseUrl, 'https://link.vizor.cash');
        expect(VizorDeepLink.baseUrl, configuredBaseUrl);
        expect(VizorDeepLink.host, Uri.parse(configuredBaseUrl).host);
      },
    );

    test('routes only the supported paths on the trusted HTTPS origin', () {
      expect(
        VizorDeepLink.routeFor(Uri.parse('https://${VizorDeepLink.host}/')),
        VizorDeepLinkRoute.home,
      );
      expect(
        VizorDeepLink.routeFor(
          Uri.parse(
            'https://${VizorDeepLink.host}'
            '${VizorDeepLink.paymentLinkPath}#v1=opaque',
          ),
        ),
        VizorDeepLinkRoute.paymentLink,
      );
      expect(
        VizorDeepLink.routeFor(
          Uri.parse('https://${VizorDeepLink.host}/unsupported'),
        ),
        isNull,
      );
    });

    test('rejects untrusted or ambiguous origins', () {
      expect(
        VizorDeepLink.routeFor(Uri.parse('http://${VizorDeepLink.host}/')),
        isNull,
      );
      expect(VizorDeepLink.routeFor(Uri.parse('https://example.com/')), isNull);
      expect(
        VizorDeepLink.routeFor(
          Uri.parse('https://user@${VizorDeepLink.host}/'),
        ),
        isNull,
      );
      expect(
        VizorDeepLink.routeFor(
          Uri.parse('https://${VizorDeepLink.host}:8443/'),
        ),
        isNull,
      );
    });

    test('keeps root routing free of query and fragment data', () {
      expect(
        VizorDeepLink.routeFor(
          Uri.parse('https://${VizorDeepLink.host}/?source=test'),
        ),
        isNull,
      );
      expect(
        VizorDeepLink.routeFor(
          Uri.parse('https://${VizorDeepLink.host}/#unexpected'),
        ),
        isNull,
      );
    });
  });
}
