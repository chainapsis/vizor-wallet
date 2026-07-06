const kVizorWalletLinkBackendBaseUrlEnvKey = 'VIZOR_WALLET_LINK_BACKEND_URL';
const kVizorWalletLinkDefaultBackendBaseUrl = 'http://localhost:3000';
const kVizorWalletLinkBackendBaseUrl = String.fromEnvironment(
  kVizorWalletLinkBackendBaseUrlEnvKey,
  defaultValue: kVizorWalletLinkDefaultBackendBaseUrl,
);

const kWalletLinkPackagePath = '/api/wallet-link/v1/packages';

Uri walletLinkBackendBaseUri({
  String baseUrl = kVizorWalletLinkBackendBaseUrl,
}) {
  return Uri.parse(baseUrl);
}

Uri walletLinkPackagesUri(Uri baseUri, {String? packageId}) {
  final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
  final packagePath = packageId == null
      ? kWalletLinkPackagePath
      : '$kWalletLinkPackagePath/${Uri.encodeComponent(packageId)}';
  return baseUri.replace(path: '$basePath$packagePath', query: null);
}
