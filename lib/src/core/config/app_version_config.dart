const kVizorReleaseVersionEnvKey = 'VIZOR_RELEASE_VERSION';
const kVizorReleaseVersion = String.fromEnvironment(
  kVizorReleaseVersionEnvKey,
  defaultValue: '0.0.0',
);

const kVizorAboutVersionLabel = 'Version: $kVizorReleaseVersion Public Beta';
