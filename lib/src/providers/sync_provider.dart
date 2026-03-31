import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../generated/service.pbgrpc.dart' as grpc;
import '../generated/service.pb.dart' as pb;
import '../rust/api/sync.dart' as rust_sync;
import '../services/background_sync_service.dart' as bg_sync;
import '../services/live_activity_service.dart';

const _batchSize = 1000;
const _saplingActivationHeight = 419200; // mainnet

class SyncState {
  final bool isSyncing;
  final bool isBackgroundMode;
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
    this.isBackgroundMode = false,
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
  bool _backgroundMode = false;

  @override
  Future<SyncState> build() async {
    ref.onDispose(() {
      _cancelled = true;
      if (_backgroundMode) bg_sync.stopBackgroundSync();
    });

    // Listen for stop signal from foreground service notification button
    FlutterForegroundTask.receivePort?.listen((message) {
      if (message == 'stop_sync') {
        log('SyncNotifier: received stop_sync from notification');
        stopSync();
      }
    });

    return SyncState();
  }

  Future<void> startSync() async {
    _cancelled = false;
    _backgroundMode = false;
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
    if (_backgroundMode) {
      bg_sync.stopBackgroundSync();
      LiveActivityService.instance.stopSyncActivity();
      _backgroundMode = false;
    }
  }

  /// Switch to background sync mode (starts platform foreground service / BG task).
  Future<void> enableBackgroundSync() async {
    if (_backgroundMode) return;
    _backgroundMode = true;
    await bg_sync.startBackgroundSync();
    await LiveActivityService.instance.startSyncActivity();
    log('SyncNotifier: background sync enabled');
    // Update state to reflect background mode
    final current = state.value;
    if (current != null) {
      state = AsyncData(SyncState(
        isSyncing: current.isSyncing,
        isBackgroundMode: true,
        percentage: current.percentage,
        scannedHeight: current.scannedHeight,
        chainTipHeight: current.chainTipHeight,
        transparentBalance: current.transparentBalance,
        saplingBalance: current.saplingBalance,
        orchardBalance: current.orchardBalance,
        totalBalance: current.totalBalance,
      ));
    }
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
        // At Sapling activation height, no tree state exists yet — use empty state
        final pb.TreeState treeState;
        if (start <= _saplingActivationHeight) {
          log('Sync: using empty tree state for Sapling activation height');
          treeState = pb.TreeState(
            network: network.name,
            height: Int64(start - 1),
            hash: '',
            time: 0,
            saplingTree: '',
            orchardTree: '',
          );
        } else {
          treeState = await stub.getTreeState(
            pb.BlockID(height: Int64(start - 1)),
          );
        }

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

        // 6b. Enhancement loop — fetch full TX data for discovered notes
        await _runEnhancement(stub, dbPath, network);

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
          isBackgroundMode: _backgroundMode,
          percentage: pct,
          scannedHeight: scanned,
          chainTipHeight: tip,
          transparentBalance: balance.transparent,
          saplingBalance: balance.sapling,
          orchardBalance: balance.orchard,
          totalBalance: balance.total,
        ));

        // Update background notification + Dynamic Island if in background mode
        if (_backgroundMode) {
          await LiveActivityService.instance.updateProgress(
            percentage: pct,
            scannedHeight: scanned,
            chainTipHeight: tip,
          );
          bg_sync.updateBackgroundSyncProgress(
            percentage: pct,
            scannedHeight: scanned,
            chainTipHeight: tip,
          );
        }
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

      // Stop background service and Live Activity when sync completes
      if (_backgroundMode) {
        await bg_sync.stopBackgroundSync();
        await LiveActivityService.instance.stopSyncActivity();
        _backgroundMode = false;
        log('SyncNotifier: background sync completed, service stopped');
      }
    } finally {
      await channel.shutdown();
    }
  }

  Future<void> _downloadSubtreeRoots(
    grpc.CompactTxStreamerClient stub,
    String dbPath,
    ZcashNetwork network,
  ) async {
    // Get already-stored indices to skip re-downloading
    final indices = await rust_sync.getNextSubtreeIndices(
      dbPath: dbPath,
      network: network.name,
    );
    final saplingStart = indices.nextSapling.toInt();
    final orchardStart = indices.nextOrchard.toInt();
    log('Sync: subtree indices — sapling starts at $saplingStart, orchard starts at $orchardStart');

    // Sapling
    final saplingRoots = <rust_sync.SubtreeRoot>[];
    await for (final root in stub.getSubtreeRoots(pb.GetSubtreeRootsArg(
      startIndex: saplingStart,
      shieldedProtocol: pb.ShieldedProtocol.sapling,
      maxEntries: 0,
    ))) {
      saplingRoots.add(rust_sync.SubtreeRoot(
        completingBlockHeight: BigInt.from(root.completingBlockHeight.toInt()),
        rootHash: Uint8List.fromList(root.rootHash),
      ));
    }
    log('Sync: got ${saplingRoots.length} new Sapling subtree roots');

    // Orchard
    final orchardRoots = <rust_sync.SubtreeRoot>[];
    await for (final root in stub.getSubtreeRoots(pb.GetSubtreeRootsArg(
      startIndex: orchardStart,
      shieldedProtocol: pb.ShieldedProtocol.orchard,
      maxEntries: 0,
    ))) {
      orchardRoots.add(rust_sync.SubtreeRoot(
        completingBlockHeight: BigInt.from(root.completingBlockHeight.toInt()),
        rootHash: Uint8List.fromList(root.rootHash),
      ));
    }
    log('Sync: got ${orchardRoots.length} new Orchard subtree roots');

    if (saplingRoots.isNotEmpty || orchardRoots.isNotEmpty) {
      await rust_sync.putSubtreeRoots(
        dbPath: dbPath,
        network: network.name,
        saplingStartIndex: BigInt.from(saplingStart),
        saplingRoots: saplingRoots,
        orchardStartIndex: BigInt.from(orchardStart),
        orchardRoots: orchardRoots,
      );
    } else {
      log('Sync: all subtree roots already stored, skipping');
    }
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

  Future<void> _runEnhancement(
    grpc.CompactTxStreamerClient stub,
    String dbPath,
    ZcashNetwork network,
  ) async {
    var iteration = 0;
    while (true) {
      iteration++;
      final requests = await rust_sync.getTransactionDataRequests(
        dbPath: dbPath,
        network: network.name,
      );
      log('Enhancement: iteration=$iteration, requests=${requests.length}');
      if (requests.isEmpty) break;

      // Check if all remaining requests are address_txids with no endHeight (not actionable yet)
      final actionable = requests.where((r) {
        if (r.requestType == 'address_txids') {
          return r.blockRangeEnd != null;
        }
        return true;
      }).toList();

      if (actionable.isEmpty) {
        log('Enhancement: ${requests.length} requests remaining but none actionable (no endHeight), moving on');
        break;
      }

      // Log all requests in first iteration
      if (iteration <= 2) {
        for (final r in requests) {
          log('Enhancement:   type=${r.requestType}, txid=${r.txid}, addr=${r.address}');
        }
      }

      // Safety: break after too many iterations
      if (iteration > 5) {
        log('Enhancement: breaking after $iteration iterations (safety limit)');
        break;
      }

      for (final req in requests) {
        try {
          if (req.requestType == 'get_status' && req.txid != null) {
            final txidBytes = _txidHexToBytes(req.txid!);
            try {
              final response = await stub.getTransaction(
                pb.TxFilter(hash: txidBytes),
              );
              final height = response.height.toInt();
              log('Enhancement: get_status TX ${req.txid!.substring(0, 16)}... height=$height');
              await rust_sync.setTransactionStatus(
                dbPath: dbPath,
                network: network.name,
                txidHex: req.txid!,
                status: height > 0 ? height : -1,
              );
              log('Enhancement: set_transaction_status succeeded for ${req.txid!.substring(0, 16)}...');
            } on GrpcError catch (e) {
              log('Enhancement: get_status gRPC error code=${e.code} for ${req.txid!.substring(0, 16)}...');
              try {
                await rust_sync.setTransactionStatus(
                  dbPath: dbPath,
                  network: network.name,
                  txidHex: req.txid!,
                  status: -2,
                );
                log('Enhancement: set_transaction_status(-2) succeeded for ${req.txid!.substring(0, 16)}...');
              } catch (setErr) {
                log('Enhancement: set_transaction_status(-2) FAILED: $setErr');
              }
            }
          } else if (req.requestType == 'enhancement' && req.txid != null) {
            final txidBytes = _txidHexToBytes(req.txid!);
            try {
              final response = await stub.getTransaction(
                pb.TxFilter(hash: txidBytes),
              );
              log('Enhancement: got TX data, size=${response.data.length}, height=${response.height}');
              if (response.data.isNotEmpty) {
                final height = response.height.toInt();
                await rust_sync.decryptAndStoreTransaction(
                  dbPath: dbPath,
                  network: network.name,
                  txBytes: Uint8List.fromList(response.data),
                  minedHeight: height > 0 ? BigInt.from(height) : null,
                );
                log('Enhancement: decryptAndStore succeeded for ${req.txid!.substring(0, 16)}...');
              }
            } on GrpcError catch (e) {
              log('Enhancement: enhancement gRPC error code=${e.code} for ${req.txid!.substring(0, 16)}...');
              try {
                await rust_sync.setTransactionStatus(
                  dbPath: dbPath,
                  network: network.name,
                  txidHex: req.txid!,
                  status: -2,
                );
                log('Enhancement: set_transaction_status(-2) succeeded for ${req.txid!.substring(0, 16)}...');
              } catch (setErr) {
                log('Enhancement: set_transaction_status(-2) FAILED: $setErr');
              }
            }
          } else if (req.requestType == 'address_txids' && req.address != null) {
            final startHeight = req.blockRangeStart?.toInt() ?? 0;
            final endHeight = req.blockRangeEnd?.toInt();

            if (endHeight == null) {
              log('Enhancement: address_txids for ${req.address!.substring(0, 10)}... has no endHeight, skipping');
              continue;
            }

            log('Enhancement: fetching txids for ${req.address!.substring(0, 10)}... range=$startHeight..$endHeight');
            try {
              final txStream = stub.getTaddressTxids(pb.TransparentAddressBlockFilter(
                address: req.address!,
                range: pb.BlockRange(
                  start: pb.BlockID(height: Int64(startHeight)),
                  end: pb.BlockID(height: Int64(endHeight - 1)),
                ),
              ));

              var txCount = 0;
              await for (final rawTx in txStream) {
                txCount++;
                if (rawTx.data.isNotEmpty) {
                  final height = rawTx.height.toInt();
                  await rust_sync.decryptAndStoreTransaction(
                    dbPath: dbPath,
                    network: network.name,
                    txBytes: Uint8List.fromList(rawTx.data),
                    minedHeight: height > 0 ? BigInt.from(height) : null,
                  );
                }
              }
              log('Enhancement: found $txCount txs for ${req.address!.substring(0, 10)}...');
            } on GrpcError catch (e) {
              log('Enhancement: address_txids gRPC error code=${e.code} for ${req.address!.substring(0, 10)}...');
            }
          }
        } catch (e) {
          log('Enhancement: unexpected error: $e');
          break;
        }
      }
    }
  }

  /// Convert hex string to bytes.
  /// TxId from Rust is Display-formatted (byte-reversed hex),
  /// but lightwalletd TxFilter.hash expects original byte order.
  /// So we reverse after hex decode.
  List<int> _txidHexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result.reversed.toList();
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
