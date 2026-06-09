import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';

const _migrationDelayedBroadcastInterval = Duration(seconds: 60);
const _migrationExpectedTransferCountBuffer = Duration(seconds: 45);
const _migrationExpectedTransferCountFile =
    'migration_expected_transfer_counts_v1.json';
const migrationProgressTransactionHistoryLimit = 1000;

class MigrationExpectedTransferCount {
  const MigrationExpectedTransferCount({
    required this.count,
    required this.firstTxid,
    required this.startedAt,
  });

  final int count;
  final String firstTxid;
  final DateTime startedAt;

  Map<String, Object?> toJson() {
    return {
      'count': count,
      'firstTxid': firstTxid,
      'startedAt': startedAt.toIso8601String(),
    };
  }

  static MigrationExpectedTransferCount? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final count = value['count'];
    final firstTxid = value['firstTxid'];
    final startedAt = value['startedAt'];
    if (count is! int || count <= 0) return null;
    if (firstTxid is! String || firstTxid.trim().isEmpty) return null;
    if (startedAt is! String) return null;
    final parsedStartedAt = DateTime.tryParse(startedAt);
    if (parsedStartedAt == null) return null;
    return MigrationExpectedTransferCount(
      count: count,
      firstTxid: firstTxid.toLowerCase(),
      startedAt: parsedStartedAt,
    );
  }

  bool isExpired(DateTime now) {
    return now.difference(startedAt) > _ttl;
  }

  Duration get _ttl {
    final delayedTransferCount = count > 1 ? count - 1 : 1;
    return Duration(
      seconds:
          (_migrationDelayedBroadcastInterval.inSeconds *
              delayedTransferCount) +
          _migrationExpectedTransferCountBuffer.inSeconds,
    );
  }
}

class MigrationExpectedTransferCountNotifier
    extends Notifier<Map<String, MigrationExpectedTransferCount>> {
  bool _disposed = false;

  @override
  Map<String, MigrationExpectedTransferCount> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(_restore());
    return const {};
  }

  void setCount(String accountUuid, int count, {required String firstTxid}) {
    state = {
      ...state,
      accountUuid: MigrationExpectedTransferCount(
        count: count,
        firstTxid: firstTxid,
        startedAt: DateTime.now(),
      ),
    };
    unawaited(_persist(state));
  }

  void clearCount(String accountUuid) {
    if (!state.containsKey(accountUuid)) return;
    state = {...state}..remove(accountUuid);
    unawaited(_persist(state));
  }

  Future<void> _restore() async {
    final restored = await _readPersistedCounts();
    if (_disposed || restored.isEmpty) return;
    final now = DateTime.now();
    final freshRestored = Map.fromEntries(
      restored.entries.where((entry) => !entry.value.isExpired(now)),
    );
    if (freshRestored.isEmpty) {
      unawaited(_persist(const {}));
      return;
    }
    state = {...freshRestored, ...state};
  }

  Future<Map<String, MigrationExpectedTransferCount>>
  _readPersistedCounts() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return const {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return const {};
      final accounts = decoded['accounts'];
      if (accounts is! Map<String, dynamic>) return const {};

      final restored = <String, MigrationExpectedTransferCount>{};
      for (final entry in accounts.entries) {
        final accountUuid = entry.key.trim();
        final count = MigrationExpectedTransferCount.fromJson(entry.value);
        if (accountUuid.isNotEmpty && count != null) {
          restored[accountUuid] = count;
        }
      }
      return restored;
    } on FormatException {
      return const {};
    } on FileSystemException {
      return const {};
    }
  }

  Future<void> _persist(
    Map<String, MigrationExpectedTransferCount> counts,
  ) async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      final now = DateTime.now();
      final accounts = <String, Object?>{
        for (final entry in counts.entries)
          if (!entry.value.isExpired(now)) entry.key: entry.value.toJson(),
      };
      await file.writeAsString(jsonEncode({'accounts': accounts}));
    } on FileSystemException {
      // Progress hints are best effort. The wallet DB remains the source of truth.
    }
  }

  Future<File> _storeFile() async {
    final directory = await getWalletSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '$_migrationExpectedTransferCountFile',
    );
  }
}

final migrationExpectedTransferCountProvider =
    NotifierProvider<
      MigrationExpectedTransferCountNotifier,
      Map<String, MigrationExpectedTransferCount>
    >(MigrationExpectedTransferCountNotifier.new);
