import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_version_config.dart';

const _feedTimeout = Duration(seconds: 8);

final linuxUpdateProvider = FutureProvider<LinuxUpdateInfo?>((ref) async {
  if (!kVizorUpdateCheckEnabled ||
      kVizorReleaseBuildNumber <= 0 ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.linux) {
    return null;
  }

  final repository = _normalizedRepository(kVizorReleaseRepository);
  if (repository == null) return null;

  final flavor = _normalizedFlavor(kVizorReleaseFlavor);
  final arch = _linuxReleaseArch();
  final feedUri = Uri.parse(
    'https://github.com/$repository/releases/latest/download/'
    '${_feedAssetName(flavor)}',
  );

  final client = HttpClient()..connectionTimeout = _feedTimeout;
  try {
    final request = await client.getUrl(feedUri).timeout(_feedTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close().timeout(_feedTimeout);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) return null;

    final body = await utf8.decodeStream(response).timeout(_feedTimeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    return LinuxUpdateInfo.fromJson(
      decoded,
      currentBuildNumber: kVizorReleaseBuildNumber,
      expectedFlavor: flavor,
      expectedArch: arch,
    );
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
});

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

String _linuxReleaseArch() {
  if (kVizorReleaseArch.isNotEmpty) return kVizorReleaseArch;
  return switch (Abi.current()) {
    Abi.linuxX64 => 'x86_64',
    Abi.linuxArm64 => 'aarch64',
    _ => Abi.current().toString(),
  };
}
