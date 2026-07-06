const kVizorWalletLinkBackendBaseUrlEnvKey = 'VIZOR_WALLET_LINK_BACKEND_URL';
const kVizorWalletLinkDefaultBackendBaseUrl = 'http://localhost:3000';
const kVizorWalletLinkBackendBaseUrl = String.fromEnvironment(
  kVizorWalletLinkBackendBaseUrlEnvKey,
  defaultValue: kVizorWalletLinkDefaultBackendBaseUrl,
);

const kWalletLinkPackagePath = '/api/wallet-link/v1/packages';
final kWalletLinkPackageIdRegex = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

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

Uri walletLinkPackageStatusUri(Uri baseUri, {required String packageId}) {
  final packageUri = walletLinkPackagesUri(baseUri, packageId: packageId);
  return packageUri.replace(path: '${packageUri.path}/status');
}

Uri walletLinkPackageCompleteUri(Uri baseUri, {required String packageId}) {
  final packageUri = walletLinkPackagesUri(baseUri, packageId: packageId);
  return packageUri.replace(path: '${packageUri.path}/complete');
}
