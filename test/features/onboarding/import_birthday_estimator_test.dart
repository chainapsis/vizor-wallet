import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';

typedef _LoadMetadataWithEndpoint = Future<ImportBirthdayMetadata> Function({
  required RpcEndpointConfig endpoint,
});

typedef _EstimateBirthdayWithEndpoint = Future<int> Function({
  required RpcEndpointConfig endpoint,
  required DateTime selectedDate,
});

void main() {
  test('estimator APIs accept the configured RPC endpoint', () {
    final _LoadMetadataWithEndpoint loadMetadata =
        ImportBirthdayEstimator.loadMetadata;
    final _EstimateBirthdayWithEndpoint estimateBirthdayHeight =
        ImportBirthdayEstimator.estimateBirthdayHeight;

    expect(loadMetadata, isNotNull);
    expect(estimateBirthdayHeight, isNotNull);
  });
}
