import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../generated/service.pbgrpc.dart' as grpc;
import '../generated/service.pb.dart' as pb;
import '../rust/api/sync.dart' as rust_sync;

const _batchSize = 1000;

class SyncState {
  final bool isSyncing;
  final double percentage;
  final int scannedHeight;
  final int chainTipHeight;
  final BigInt transparentBalance;
  final BigInt saplingBalance;
  final BigInt orchardBalance;
  final BigInt totalBalance;
  final String? error;

  SyncState({
    this.isSyncing = false,
    this.percentage = 0,
    this.scannedHeight = 0,
    this.chainTipHeight = 0,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? totalBalance,
    this.error,
  })  : transparentBalance = transparentBalance ?? BigInt.zero,
        saplingBalance = saplingBalance ?? BigInt.zero,
        orchardBalance = orchardBalance ?? BigInt.zero,
        totalBalance = totalBalance ?? BigInt.zero;
}

class SyncNotifier extends AsyncNotifier<SyncState> {
  bool _cancelled = false;

  @override
  Future<SyncState> build() async {
    ref.onDispose(() => _cancelled = true);
    return SyncState();
  }

  Future<void> startSync() async {
    _cancelled = false;
    state = AsyncData(SyncState(isSyncing: true));

    try {
      await _runSync();
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      state = AsyncData(SyncState(error: e.toString()));
    }
  }

  void stopSync() {
    _cancelled = true;
  }

  Future<void> _runSync() async {
    final network = ZcashNetwork.mainnet;
    final dbPath = await _getDbPath();
    final cachePath = await _getCachePath();

    log('Sync: connecting to ${network.lightwalletdHost}:${network.lightwalletdPort}');

    final channel = ClientChannel(
      network.lightwalletdHost,
      port: network.lightwalletdPort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.secure(),
      ),
    );

    try {
      final stub = grpc.CompactTxStreamerClient(channel);

      // 1. Get chain tip
      log('Sync: getting chain tip');
      final tipBlock = await stub.getLatestBlock(pb.ChainSpec());
      final tipHeight = tipBlock.height;
      log('Sync: chain tip = ${tipHeight.toInt()}');

      await rust_sync.updateChainTip(
        dbPath: dbPath,
        network: network.name,
        height: BigInt.from(tipHeight.toInt()),
      );

      // 2. Download subtree roots
      log('Sync: downloading subtree roots');
      await _downloadSubtreeRoots(stub, dbPath, network);

      // 3. Sync loop
      while (!_cancelled) {
        final ranges = await rust_sync.suggestScanRanges(
          dbPath: dbPath,
          network: network.name,
        );

        if (ranges.isEmpty) {
          log('Sync: fully synced');
          break;
        }

        final range = ranges.first;
        final start = range.start.toInt();
        final end = range.end.toInt();
        final batchEnd = (start + _batchSize).clamp(start, end);

        log('Sync: scanning $start..$batchEnd (of $end), priority=${range.priority}');

        // 4. Download blocks
        await _downloadAndCacheBlocks(stub, cachePath, start, batchEnd - 1);

        // 5. Get tree state before first block
        final treeState = await stub.getTreeState(
          pb.BlockID(height: Int64(start - 1)),
        );

        // 6. Scan blocks
        final result = await rust_sync.scanBlocks(
          dbPath: dbPath,
          cachePath: cachePath,
          network: network.name,
          fromHeight: BigInt.from(start),
          treeStateNetwork: treeState.network,
          treeStateHeight: BigInt.from(treeState.height.toInt()),
          treeStateHash: treeState.hash,
          treeStateTime: treeState.time,
          treeStateSaplingTree: treeState.saplingTree,
          treeStateOrchardTree: treeState.orchardTree,
          limit: BigInt.from(_batchSize),
        );

        log('Sync: scanned ${result.blocksScanned} blocks');

        // 7. Update progress
        final progress = await rust_sync.getSyncStatus(
          dbPath: dbPath,
          network: network.name,
        );
        final balance = await rust_sync.getBalance(
          dbPath: dbPath,
          network: network.name,
        );

        final scanned = progress.scannedHeight.toInt();
        final tip = progress.chainTipHeight.toInt();
        final pct = tip > 0 ? scanned / tip : 0.0;

        state = AsyncData(SyncState(
          isSyncing: true,
          percentage: pct,
          scannedHeight: scanned,
          chainTipHeight: tip,
          transparentBalance: balance.transparent,
          saplingBalance: balance.sapling,
          orchardBalance: balance.orchard,
          totalBalance: balance.total,
        ));
      }

      // Final balance update
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: network.name,
      );
      final progress = await rust_sync.getSyncStatus(
        dbPath: dbPath,
        network: network.name,
      );

      state = AsyncData(SyncState(
        isSyncing: false,
        percentage: 1.0,
        scannedHeight: progress.scannedHeight.toInt(),
        chainTipHeight: progress.chainTipHeight.toInt(),
        transparentBalance: balance.transparent,
        saplingBalance: balance.sapling,
        orchardBalance: balance.orchard,
        totalBalance: balance.total,
      ));
    } finally {
      await channel.shutdown();
    }
  }

  Future<void> _downloadSubtreeRoots(
    grpc.CompactTxStreamerClient stub,
    String dbPath,
    ZcashNetwork network,
  ) async {
    // Sapling
    final saplingRoots = <rust_sync.SubtreeRoot>[];
    await for (final root in stub.getSubtreeRoots(pb.GetSubtreeRootsArg(
      startIndex: 0,
      shieldedProtocol: pb.ShieldedProtocol.sapling,
      maxEntries: 0,
    ))) {
      saplingRoots.add(rust_sync.SubtreeRoot(
        completingBlockHeight: BigInt.from(root.completingBlockHeight.toInt()),
        rootHash: Uint8List.fromList(root.rootHash),
      ));
    }
    log('Sync: got ${saplingRoots.length} Sapling subtree roots');

    // Orchard
    final orchardRoots = <rust_sync.SubtreeRoot>[];
    await for (final root in stub.getSubtreeRoots(pb.GetSubtreeRootsArg(
      startIndex: 0,
      shieldedProtocol: pb.ShieldedProtocol.orchard,
      maxEntries: 0,
    ))) {
      orchardRoots.add(rust_sync.SubtreeRoot(
        completingBlockHeight: BigInt.from(root.completingBlockHeight.toInt()),
        rootHash: Uint8List.fromList(root.rootHash),
      ));
    }
    log('Sync: got ${orchardRoots.length} Orchard subtree roots');

    await rust_sync.putSubtreeRoots(
      dbPath: dbPath,
      network: network.name,
      saplingRoots: saplingRoots,
      orchardRoots: orchardRoots,
    );
  }

  Future<void> _downloadAndCacheBlocks(
    grpc.CompactTxStreamerClient stub,
    String cachePath,
    int start,
    int end,
  ) async {
    final blocksDir = rust_sync.getBlocksDir(cachePath: cachePath);
    await Directory(blocksDir).create(recursive: true);

    final metas = <rust_sync.BlockMetaInfo>[];

    await for (final block in stub.getBlockRange(pb.BlockRange(
      start: pb.BlockID(height: Int64(start)),
      end: pb.BlockID(height: Int64(end)),
    ))) {
      final height = block.height;
      final hash = Uint8List.fromList(block.hash);
      // BlockHash Display in Rust reverses bytes before hex encoding
      final reversedHash = Uint8List.fromList(hash.reversed.toList());
      final hashHex = reversedHash
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Write compact block as protobuf binary
      final data = block.writeToBuffer();
      final filePath = '$blocksDir/${height.toInt()}-$hashHex-compactblock';
      await File(filePath).writeAsBytes(data);

      // Count outputs/actions
      var saplingCount = 0;
      var orchardCount = 0;
      for (final tx in block.vtx) {
        saplingCount += tx.outputs.length;
        orchardCount += tx.actions.length;
      }

      metas.add(rust_sync.BlockMetaInfo(
        height: BigInt.from(height.toInt()),
        hash: hash,
        time: block.time,
        saplingOutputsCount: saplingCount,
        orchardActionsCount: orchardCount,
      ));
    }

    if (metas.isNotEmpty) {
      await rust_sync.writeBlockMetadata(
        cachePath: cachePath,
        blocks: metas,
      );
    }
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
  }

  Future<String> _getCachePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}zcash_cache';
    await Directory(path).create(recursive: true);
    return path;
  }
}

final syncProvider =
    AsyncNotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
