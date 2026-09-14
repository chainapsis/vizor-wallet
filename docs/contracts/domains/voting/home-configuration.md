# Voting discovery configuration

Use when changing discovery build defines and bundled source configuration.

The [discovery client](../../../../lib/src/services/voting/voting_discovery_client.dart)
owns endpoint defines and response validation; [Home routing](../../../../lib/src/providers/voting/voting_home_entry_provider.dart)
selects the network/source scope. Verify with
[`voting_discovery_client_test.dart`](../../../../test/services/voting/voting_discovery_client_test.dart).

`VIZOR_VOTING_DISCOVERY_URL` replaces the **entire** discovery endpoint URL.
Its default is `https://functions.vizor.cash/v1/voting/discovery/prod`.
Testnet uses the independent `VIZOR_VOTING_DISCOVERY_STAGE_URL` define, defaulting
to `https://functions.vizor.cash/v1/voting/discovery/stage`.

```sh
fvm flutter run --dart-define=VIZOR_FORM_FACTOR=mobile \
  --dart-define=VIZOR_VOTING_DISCOVERY_URL=https://example.com/v1/voting/discovery/prod
```

The endpoint must use HTTPS (HTTP loopback is accepted for development). This
setting does not change voting config or vote-server URLs. The request uses the
shared network transport's Tor/direct routing policy, with a five-second timeout.
No account identifier or eligibility is sent. Custom voting sources and mismatched
network/source pairs retain direct discovery; an endpoint override does not opt
them in. Prod and stage hints are scoped by both wallet network and config source.
