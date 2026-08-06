const kVizorReleaseVersionEnvKey = 'VIZOR_RELEASE_VERSION';
const kVizorReleaseVersion = String.fromEnvironment(
  kVizorReleaseVersionEnvKey,
  defaultValue: '0.0.0',
);

const kVizorReleaseBuildNumberEnvKey = 'VIZOR_RELEASE_BUILD_NUMBER';
const kVizorReleaseBuildNumber = int.fromEnvironment(
  kVizorReleaseBuildNumberEnvKey,
);

const kVizorReleaseFlavorEnvKey = 'VIZOR_RELEASE_FLAVOR';
const kVizorReleaseFlavor = String.fromEnvironment(
  kVizorReleaseFlavorEnvKey,
  defaultValue: 'mainnet',
);

const kVizorReleaseArchEnvKey = 'VIZOR_RELEASE_ARCH';
const kVizorReleaseArch = String.fromEnvironment(kVizorReleaseArchEnvKey);

const kVizorReleaseRepositoryEnvKey = 'VIZOR_RELEASE_REPOSITORY';
const kVizorReleaseRepository = String.fromEnvironment(
  kVizorReleaseRepositoryEnvKey,
  defaultValue: 'chainapsis/vizor-wallet',
);

const kVizorUpdateCheckEnabledEnvKey = 'VIZOR_UPDATE_CHECK_ENABLED';
const kVizorUpdateCheckEnabled = bool.fromEnvironment(
  kVizorUpdateCheckEnabledEnvKey,
);

const kVizorAboutVersionLabel = 'Version: $kVizorReleaseVersion Public Beta';
