import '../../../core/config/rpc_endpoint_config.dart';
import '../../../rust/api/network_privacy.dart' as rust_network_privacy;

const _importBirthdaySafetyMargin = Duration(days: 7);

DateTime importBirthdaySearchDate(DateTime selectedDate) => DateTime(
  selectedDate.year,
  selectedDate.month,
  selectedDate.day,
).subtract(_importBirthdaySafetyMargin);

class ImportBirthdayMetadata {
  const ImportBirthdayMetadata({
    required this.saplingActivationHeight,
    required this.saplingActivationDate,
    required this.tipHeight,
    required this.tipDate,
  });

  final int saplingActivationHeight;
  final DateTime saplingActivationDate;
  final int tipHeight;
  final DateTime tipDate;
}

typedef ImportBirthdayEndpointRunner =
    Future<int> Function(
      Future<int> Function(RpcEndpointConfig endpoint) action,
    );

class ImportBirthdayEstimator {
  ImportBirthdayEstimator._();

  static Future<ImportBirthdayMetadata> loadMetadata({
    required RpcEndpointConfig endpoint,
  }) async {
    final metadata = await rust_network_privacy.getImportBirthdayMetadata(
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      useMainnetFastPath: _useMainnetFastPath(endpoint),
    );
    return ImportBirthdayMetadata(
      saplingActivationHeight: metadata.saplingActivationHeight.toInt(),
      saplingActivationDate: _blockTimeToLocalDate(
        metadata.saplingActivationTime,
      ),
      tipHeight: metadata.tipHeight.toInt(),
      tipDate: _blockTimeToLocalDate(metadata.tipTime),
    );
  }

  static Future<int> estimateBirthdayHeight({
    required RpcEndpointConfig endpoint,
    required DateTime selectedDate,
    ImportBirthdayMetadata? metadata,
    ImportBirthdayEndpointRunner? runWithEndpoint,
  }) async {
    final searchDate = importBirthdaySearchDate(selectedDate);
    final targetEpoch = searchDate.toUtc().millisecondsSinceEpoch ~/ 1000;
    Future<int> estimate(RpcEndpointConfig selected) async {
      final height = await rust_network_privacy.estimateImportBirthdayHeight(
        lightwalletdUrl: selected.normalizedLightwalletdUrl,
        targetEpochSeconds: targetEpoch,
        useMainnetFastPath: _useMainnetFastPath(selected),
        tipHeight: metadata == null ? null : BigInt.from(metadata.tipHeight),
        tipTime: metadata == null
            ? null
            : metadata.tipDate.toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      return height.toInt();
    }

    // Mainnet's compiled table plus an observed tip answers locally. Do not
    // make that calculation depend on endpoint discovery or a working route.
    if ((_useMainnetFastPath(endpoint) && metadata != null) ||
        runWithEndpoint == null) {
      return estimate(endpoint);
    }
    return runWithEndpoint(estimate);
  }

  static DateTime _blockTimeToLocalDate(int blockTime) {
    return DateTime.fromMillisecondsSinceEpoch(
      blockTime * 1000,
      isUtc: true,
    ).toLocal();
  }

  static bool _useMainnetFastPath(RpcEndpointConfig endpoint) =>
      endpoint.network == ZcashNetwork.mainnet;
}
