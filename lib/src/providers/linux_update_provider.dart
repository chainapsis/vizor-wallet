import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_version_config.dart';
import '../core/network/network_http_client.dart';
import 'network_privacy_provider.dart';

const kLinuxUpdateFeedTimeout = Duration(seconds: 30);

typedef LinuxUpdateHttpClientFactory = NetworkHttpClient Function();

typedef LinuxUpdateCheck = Future<LinuxUpdateInfo?> Function();

/// Whether this build can check the Linux release feed at all.
final linuxUpdateSupportedProvider = Provider<bool>(
  (ref) =>
      kVizorUpdateCheckEnabled &&
      kVizorReleaseBuildNumber > 0 &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux,
);

/// Whether the process-wide route already matches the user's privacy setting.
///
/// A check started while Tor is bootstrapping or failed cannot reach the feed
/// and must not fall back to clearnet, so it is skipped until the route
/// settles. The native-updater availability flag is deliberately not part of
/// this gate: Linux has no native updater to pause, and the release feed is a
/// plain request over whichever route is active.
final linuxUpdateRouteReadyProvider = Provider<bool>((ref) {
  return ref.watch(
    networkPrivacyProvider.select(
      (state) => switch (state.status) {
        NetworkPrivacyConnectionStatus.off => !state.torEnabled,
        NetworkPrivacyConnectionStatus.connected => state.torEnabled,
        _ => false,
      },
    ),
  );
});

/// Seam for the feed request so the route gating can be exercised without a
/// network stack.
final linuxUpdateCheckProvider = Provider<LinuxUpdateCheck>(
  (ref) =>
      () => fetchLinuxUpdate(
        clientFactory: NetworkHttpClient.new,
        repository: kVizorReleaseRepository,
        flavor: kVizorReleaseFlavor,
        arch: _linuxReleaseArch(),
        currentBuildNumber: kVizorReleaseBuildNumber,
        feedBaseUrl: kVizorUpdateFeedBaseUrl,
      ),
);

final linuxUpdateProvider = FutureProvider<LinuxUpdateInfo?>((ref) async {
  if (!ref.watch(linuxUpdateSupportedProvider)) return null;
  // Watched, not read: the one-shot check would otherwise be lost for the rest
  // of the session when it lands while the route is unusable.
  if (!ref.watch(linuxUpdateRouteReadyProvider)) return null;

  return ref.read(linuxUpdateCheckProvider)();
});

/// Checks the Linux release feed through the process-wide network route.
///
/// Keeping the request separate from the platform/build gate lets tests prove
/// that Tor routing, feed validation, and timeout behavior work on any host.
Future<LinuxUpdateInfo?> fetchLinuxUpdate({
  required LinuxUpdateHttpClientFactory clientFactory,
  required String repository,
  required String flavor,
  required String arch,
  required int currentBuildNumber,
  String feedBaseUrl = '',
  Duration timeout = kLinuxUpdateFeedTimeout,
}) async {
  final normalizedRepository = _normalizedRepository(repository);
  if (normalizedRepository == null) return null;

  final normalizedFlavor = _normalizedFlavor(flavor);
  final normalizedFeedBase = _normalizedFeedBaseUrl(
    feedBaseUrl,
    repository: normalizedRepository,
  );
  if (feedBaseUrl.trim().isNotEmpty && normalizedFeedBase == null) return null;
  final feedUri =
      (normalizedFeedBase ??
              Uri.parse(
                'https://github.com/$normalizedRepository/releases/latest/download/',
              ))
          .resolve(_feedAssetName(normalizedFlavor));

  final client = clientFactory();
  try {
    final response = await client.request(
      'GET',
      feedUri,
      headers: const {HttpHeaders.acceptHeader: 'application/json'},
      timeout: timeout,
    );
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) return null;

    final body = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    return LinuxUpdateInfo.fromJson(
      decoded,
      currentBuildNumber: currentBuildNumber,
      expectedFlavor: normalizedFlavor,
      expectedArch: arch,
    );
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

class LinuxUpdateInfo {
  const LinuxUpdateInfo({
    required this.version,
    required this.assetVersion,
    required this.buildNumber,
    required this.releaseTag,
    required this.releaseUrl,
    required this.appImageUrl,
    required this.sha256Url,
    required this.signatureUrl,
    required this.zsyncUrl,
  });

  final String version;
  final String assetVersion;
  final int buildNumber;
  final String releaseTag;
  final String releaseUrl;
  final String appImageUrl;
  final String sha256Url;
  final String signatureUrl;
  final String? zsyncUrl;

  static LinuxUpdateInfo? fromJson(
    Map<String, dynamic> json, {
    required int currentBuildNumber,
    required String expectedFlavor,
    required String expectedArch,
  }) {
    final schemaVersion = json['schemaVersion'];
    final platform = json['platform'];
    final flavor = json['flavor'];
    final buildNumber = json['buildNumber'];
    final assets = json['assets'];
    if (schemaVersion != 1 ||
        platform != 'linux' ||
        flavor != expectedFlavor ||
        buildNumber is! int ||
        buildNumber <= currentBuildNumber ||
        assets is! Map<String, dynamic>) {
      return null;
    }

    final asset = assets[expectedArch];
    if (asset is! Map<String, dynamic>) return null;

    final version = json['version'];
    final assetVersion = json['assetVersion'];
    final releaseTag = json['releaseTag'];
    final releaseUrl = json['releaseUrl'];
    final appImageUrl = asset['appImage'];
    final sha256Url = asset['sha256'];
    final signatureUrl = asset['signature'];
    final zsyncUrl = asset['zsync'];
    if (version is! String ||
        assetVersion is! String ||
        releaseTag is! String ||
        releaseUrl is! String ||
        appImageUrl is! String ||
        sha256Url is! String ||
        signatureUrl is! String ||
        (zsyncUrl != null && zsyncUrl is! String)) {
      return null;
    }

    return LinuxUpdateInfo(
      version: version,
      assetVersion: assetVersion,
      buildNumber: buildNumber,
      releaseTag: releaseTag,
      releaseUrl: releaseUrl,
      appImageUrl: appImageUrl,
      sha256Url: sha256Url,
      signatureUrl: signatureUrl,
      zsyncUrl: zsyncUrl,
    );
  }
}

String _feedAssetName(String flavor) {
  return flavor == 'testnet'
      ? 'linux-update-testnet.json'
      : 'linux-update.json';
}

String _normalizedFlavor(String flavor) {
  return flavor == 'testnet' ? 'testnet' : 'mainnet';
}

String? _normalizedRepository(String repository) {
  final trimmed = repository.trim();
  if (trimmed.isEmpty) return 'chainapsis/vizor-wallet';
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

Uri? _normalizedFeedBaseUrl(String raw, {required String repository}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != 6 ||
      '${segments[0]}/${segments[1]}' != repository ||
      segments[2] != 'releases' ||
      segments[3] != 'download' ||
      segments[4] != 'release' ||
      !RegExp(r'^v\d+\.\d+\.\d+-rc\.\d+$').hasMatch(segments[5])) {
    return null;
  }
  return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
}

String _linuxReleaseArch() {
  if (kVizorReleaseArch.isNotEmpty) return kVizorReleaseArch;
  return switch (Abi.current()) {
    Abi.linuxX64 => 'x86_64',
    Abi.linuxArm64 => 'aarch64',
    _ => Abi.current().toString(),
  };
}
