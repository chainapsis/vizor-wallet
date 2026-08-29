enum VizorDeepLinkRoute { home, paymentLink }

const kVizorDeeplinkBaseUrlEnvKey = 'VIZOR_DEEPLINK_BASE_URL';
const kDefaultVizorDeeplinkBaseUrl = 'https://link.vizor.cash';

/// The trusted HTTPS boundary and exact in-app route allowlist for Vizor links.
abstract final class VizorDeepLink {
  static const baseUrl = String.fromEnvironment(
    kVizorDeeplinkBaseUrlEnvKey,
    defaultValue: kDefaultVizorDeeplinkBaseUrl,
  );
  static const paymentLinkPath = '/payment-links/open';
  static final Uri _origin = _parseOrigin(baseUrl);

  static String get scheme => _origin.scheme;
  static String get host => _origin.host;

  static VizorDeepLinkRoute? routeFor(Uri uri) {
    if (!_matchesOrigin(uri)) return null;

    return switch (uri.path) {
      '' ||
      '/' when !uri.hasQuery && uri.fragment.isEmpty => VizorDeepLinkRoute.home,
      paymentLinkPath => VizorDeepLinkRoute.paymentLink,
      _ => null,
    };
  }

  static bool _matchesOrigin(Uri uri) {
    return uri.scheme.toLowerCase() == scheme &&
        uri.host.toLowerCase() == host &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
  }

  static Uri _parseOrigin(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(
        value,
        kVizorDeeplinkBaseUrlEnvKey,
        'Must be an HTTPS origin without a path, query, fragment, or port.',
      );
    }
    return Uri(scheme: 'https', host: uri.host.toLowerCase());
  }
}
