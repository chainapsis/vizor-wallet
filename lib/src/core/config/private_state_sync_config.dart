const kPrivateStateBaseUrlEnvKey = 'VIZOR_PRIVATE_STATE_BASE_URL';
const kPrivateStateAllowInsecureHttpEnvKey =
    'VIZOR_PRIVATE_STATE_ALLOW_INSECURE_HTTP';
const kPrivateStateAudienceEnvKey = 'VIZOR_PRIVATE_STATE_AUDIENCE';

const kPrivateStateBaseUrl = String.fromEnvironment(
  kPrivateStateBaseUrlEnvKey,
  defaultValue: 'https://functions.vizor.cash/api/private-state/v1',
);
const kPrivateStateAllowInsecureHttp = bool.fromEnvironment(
  kPrivateStateAllowInsecureHttpEnvKey,
);
const kPrivateStateAudience = String.fromEnvironment(
  kPrivateStateAudienceEnvKey,
);

Uri privateStateBaseUriForBuild() {
  return parsePrivateStateBaseUri(
    kPrivateStateBaseUrl,
    allowInsecureHttp: kPrivateStateAllowInsecureHttp,
  );
}

String privateStateAudienceForBuild(Uri baseUri) {
  final configured = kPrivateStateAudience.trim();
  if (configured.isEmpty) return baseUri.toString();
  return parsePrivateStateAudience(
    configured,
    allowInsecureHttp: kPrivateStateAllowInsecureHttp,
  );
}

String parsePrivateStateAudience(
  String raw, {
  required bool allowInsecureHttp,
}) {
  return _parsePrivateStateUri(
    raw,
    allowInsecureHttp: allowInsecureHttp,
    environmentKey: kPrivateStateAudienceEnvKey,
  ).toString();
}

Uri parsePrivateStateBaseUri(String raw, {required bool allowInsecureHttp}) {
  return _parsePrivateStateUri(
    raw,
    allowInsecureHttp: allowInsecureHttp,
    environmentKey: kPrivateStateBaseUrlEnvKey,
  );
}

Uri _parsePrivateStateUri(
  String raw, {
  required bool allowInsecureHttp,
  required String environmentKey,
}) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' && !(allowInsecureHttp && uri.scheme == 'http'))) {
    throw StateError(
      '$environmentKey must be an absolute HTTPS URL without '
      'credentials, query, or fragment. Development HTTP additionally '
      'requires --dart-define=$kPrivateStateAllowInsecureHttpEnvKey=true.',
    );
  }

  final normalizedPath = uri.path == '/'
      ? ''
      : uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: normalizedPath);
}
