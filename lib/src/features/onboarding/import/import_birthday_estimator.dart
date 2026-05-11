import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../generated/compact_formats.pb.dart' as compact;
import '../../../generated/service.pbgrpc.dart' as service;

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

class ImportBirthdayEstimator {
  ImportBirthdayEstimator._();

  static final CallOptions _rpcOptions = CallOptions(
    timeout: const Duration(seconds: 10),
  );

  static Future<ImportBirthdayMetadata> loadMetadata({
    required RpcEndpointConfig endpoint,
  }) async {
    return _withClient(endpoint.normalizedLightwalletdUrl, (client) async {
      final info = await client.getLightdInfo(
        service.Empty(),
        options: _rpcOptions,
      );
      final saplingHeight = info.saplingActivationHeight.toInt();
      final tipBlockId = await client.getLatestBlock(
        service.ChainSpec(),
        options: _rpcOptions,
      );
      final tipHeight = tipBlockId.height.toInt();
      final saplingBlock = await _getBlockAtHeight(client, saplingHeight);
      final tipBlock = await _getBlockAtHeight(client, tipHeight);

      return ImportBirthdayMetadata(
        saplingActivationHeight: saplingHeight,
        saplingActivationDate: _blockTimeToLocalDate(saplingBlock),
        tipHeight: tipHeight,
        tipDate: _blockTimeToLocalDate(tipBlock),
      );
    });
  }

  static Future<int> estimateBirthdayHeight({
    required RpcEndpointConfig endpoint,
    required DateTime selectedDate,
  }) async {
    return _withClient(endpoint.normalizedLightwalletdUrl, (client) async {
      final info = await client.getLightdInfo(
        service.Empty(),
        options: _rpcOptions,
      );
      final saplingHeight = info.saplingActivationHeight.toInt();
      final tipBlockId = await client.getLatestBlock(
        service.ChainSpec(),
        options: _rpcOptions,
      );
      final tipHeight = tipBlockId.height.toInt();

      final cache = <int, int>{};

      Future<int> blockTimestampAt(int height) async {
        final cached = cache[height];
        if (cached != null) return cached;
        final block = await _getBlockAtHeight(client, height);
        cache[height] = block.time;
        return block.time;
      }

      final normalizedSelectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final searchDate = normalizedSelectedDate.subtract(
        const Duration(days: 15),
      );
      final targetEpoch = searchDate.toUtc().millisecondsSinceEpoch ~/ 1000;

      final saplingEpoch = await blockTimestampAt(saplingHeight);
      if (targetEpoch <= saplingEpoch) {
        return saplingHeight;
      }

      final tipEpoch = await blockTimestampAt(tipHeight);
      if (targetEpoch >= tipEpoch) {
        return tipHeight;
      }

      var low = saplingHeight;
      var high = tipHeight;
      while (low < high) {
        final mid = low + ((high - low) ~/ 2);
        final midEpoch = await blockTimestampAt(mid);
        if (midEpoch < targetEpoch) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }

      return low;
    });
  }

  static Future<T> _withClient<T>(
    String lightwalletdUrl,
    Future<T> Function(service.CompactTxStreamerClient client) action,
  ) async {
    final uri = Uri.parse(lightwalletdUrl);
    final credentials = uri.scheme == 'https'
        ? const ChannelCredentials.secure()
        : const ChannelCredentials.insecure();
    final channel = ClientChannel(
      uri.host,
      port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
      options: ChannelOptions(
        credentials: credentials,
        connectionTimeout: const Duration(seconds: 10),
      ),
    );
    final client = service.CompactTxStreamerClient(channel);
    try {
      return await action(client);
    } finally {
      await channel.shutdown();
    }
  }

  static Future<compact.CompactBlock> _getBlockAtHeight(
    service.CompactTxStreamerClient client,
    int height,
  ) {
    return client.getBlock(
      service.BlockID(height: Int64(height)),
      options: _rpcOptions,
    );
  }

  static DateTime _blockTimeToLocalDate(compact.CompactBlock block) {
    return DateTime.fromMillisecondsSinceEpoch(
      block.time * 1000,
      isUtc: true,
    ).toLocal();
  }
}
