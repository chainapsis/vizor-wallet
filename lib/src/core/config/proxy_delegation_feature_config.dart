import 'package:flutter_riverpod/flutter_riverpod.dart';

const kVizorProxyDelegationEnabledEnvKey = 'VIZOR_PROXY_DELEGATION_ENABLED';

/// Dormant build switch for proxy delegation, mirroring zcash_voting's
/// `PROXY_DELEGATION_ENABLED`.
///
/// Off unless a build passes `--dart-define=VIZOR_PROXY_DELEGATION_ENABLED=true`.
/// While off, no delegation route is registered and no entry point, warning
/// or results note is built, so the shipped app is unchanged. The screens
/// behind it run on zcash_voting's client API, whose own
/// `PROXY_DELEGATION_ENABLED` keeps every round unsupported until it is set.
const kVizorProxyDelegationEnabled = bool.fromEnvironment(
  kVizorProxyDelegationEnabledEnvKey,
  defaultValue: false,
);

/// Runtime view of [kVizorProxyDelegationEnabled], so widget tests can turn
/// the delegator screens on without a custom build.
final proxyDelegationFeatureEnabledProvider = Provider<bool>(
  (_) => kVizorProxyDelegationEnabled,
);
