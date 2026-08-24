const kPrivateStateBaseUrlEnvKey = 'VIZOR_PRIVATE_STATE_BASE_URL';
const kPrivateStateAllowInsecureHttpEnvKey =
    'VIZOR_PRIVATE_STATE_ALLOW_INSECURE_HTTP';

const kPrivateStateBaseUrl = String.fromEnvironment(
  kPrivateStateBaseUrlEnvKey,
  defaultValue: 'https://functions.vizor.cash/api/private-state/v1',
);
const kPrivateStateAllowInsecureHttp = bool.fromEnvironment(
  kPrivateStateAllowInsecureHttpEnvKey,
);

Uri privateStateBaseUriForBuild() {
  return parsePrivateStateBaseUri(
    kPrivateStateBaseUrl,
    allowInsecureHttp: kPrivateStateAllowInsecureHttp,
  );
}

Uri parsePrivateStateBaseUri(String raw, {required bool allowInsecureHttp}) {
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
      '$kPrivateStateBaseUrlEnvKey must be an absolute HTTPS URL without '
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
