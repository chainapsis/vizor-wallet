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
    if (!matchesOrigin(uri)) return null;

    return switch (uri.path) {
      '' ||
      '/' when !uri.hasQuery && uri.fragment.isEmpty => VizorDeepLinkRoute.home,
      paymentLinkPath => VizorDeepLinkRoute.paymentLink,
      _ => null,
    };
  }

  /// Whether [uri] is on the trusted Vizor deeplink origin, whatever its path.
  ///
  /// Public because `classifyIncomingLink` has to answer "is this the Gift
  /// Card host?" *before* anything else looks at the link: a Gift Card link's
  /// fragment carries a mnemonic, so an unrecognised path on this host must
  /// stop here rather than fall through to the ZIP-321 parser or a log line.
  static bool matchesOrigin(Uri uri) {
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
