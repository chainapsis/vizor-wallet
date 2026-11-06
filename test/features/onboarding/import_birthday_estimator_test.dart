import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

typedef _LoadMetadataWithEndpoint =
    Future<ImportBirthdayMetadata> Function({
      required RpcEndpointConfig endpoint,
    });

typedef _EstimateBirthdayWithEndpoint =
    Future<int> Function({
      required RpcEndpointConfig endpoint,
      required DateTime selectedDate,
    });

void main() {
  final api = _BirthdayApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(api.urls.clear);

  test('keeps the 7-day birthday safety margin', () {
    expect(
      importBirthdaySearchDate(DateTime(2026, 8, 7, 18, 30)),
      DateTime(2026, 7, 31),
    );
  });

  test('estimator APIs accept the configured RPC endpoint', () {
    final _LoadMetadataWithEndpoint loadMetadata =
        ImportBirthdayEstimator.loadMetadata;
    final _EstimateBirthdayWithEndpoint estimateBirthdayHeight =
        ImportBirthdayEstimator.estimateBirthdayHeight;

    expect(loadMetadata, isNotNull);
    expect(estimateBirthdayHeight, isNotNull);
  });

  test(
    'known mainnet tip estimates locally while routing is unavailable',
    () async {
      final height = await ImportBirthdayEstimator.estimateBirthdayHeight(
        endpoint: defaultRpcEndpointConfig('main'),
        selectedDate: DateTime(2026, 8, 7),
        metadata: ImportBirthdayMetadata(
          saplingActivationHeight: 419200,
          saplingActivationDate: DateTime(2018, 10, 28),
          tipHeight: 3_500_000,
          tipDate: DateTime(2026, 8, 8),
        ),
        runWithEndpoint: (_) async =>
            throw StateError('Network privacy blocked endpoint selection.'),
      );

      expect(height, 123456);
      expect(api.knownTip, BigInt.from(3_500_000));
      expect(api.mainnetFastPath, isTrue);
    },
  );

  test(
    'an estimate without tip metadata resolves its network endpoint',
    () async {
      const selected = RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: 'https://selected.example:443',
      );
      var resolutions = 0;
      final height = await ImportBirthdayEstimator.estimateBirthdayHeight(
        endpoint: defaultRpcEndpointConfig('main'),
        selectedDate: DateTime(2026, 8, 7),
        runWithEndpoint: (action) {
          resolutions++;
          return action(selected);
        },
      );

      expect(height, 123456);
      expect(resolutions, 1);
      expect(api.urls, ['https://selected.example:443']);
      expect(api.knownTip, isNull);
    },
  );
}

class _BirthdayApi extends RustLibApi {
  final urls = <String>[];
  BigInt? knownTip;
  bool? mainnetFastPath;

  @override
  Future<BigInt> crateApiNetworkPrivacyEstimateImportBirthdayHeight({
    required String lightwalletdUrl,
    required frb.PlatformInt64 targetEpochSeconds,
    required bool useMainnetFastPath,
    BigInt? tipHeight,
    int? tipTime,
  }) async {
    urls.add(lightwalletdUrl);
    knownTip = tipHeight;
    mainnetFastPath = useMainnetFastPath;
    return BigInt.from(123456);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
