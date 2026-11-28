import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

/// The round and account every provider here is read for.
const _key = VotingSessionKey(roundId: 'round-1', accountUuid: 'account-1');

/// A provider body that fails the test if anything builds it.
Never _untouchable(String name) =>
    throw TestFailure('$name was built with the flag off');

void main() {
  test('the shipped build has the flag off', () {
    expect(kVizorProxyDelegationEnabled, isFalse);
  });

  test('with the flag off the delegator entry points read nothing of the '
      'client library, the job or the registry', () async {
    final container = ProviderContainer(
      overrides: [
        proxyDelegationFeatureEnabledProvider.overrideWithValue(false),
        proxyDelegationRepositoryProvider.overrideWith(
          (_, _) => _untouchable('the repository'),
        ),
        proxyRegistryClientProvider.overrideWith(
          (_) => _untouchable('the registry client'),
        ),
        proxyJobProgressReaderProvider.overrideWith(
          (_) => _untouchable('the job progress reader'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(proxyEntryKindProvider(_key).future),
      ProxyEntryKind.hidden,
    );
    expect(container.read(proxyBallotDelegationProvider(_key)), isNull);
  });
}
