import 'package:flutter_riverpod/flutter_riverpod.dart';

const _migrationDelayedBroadcastInterval = Duration(seconds: 60);
const _migrationExpectedTransferCountBuffer = Duration(seconds: 45);

class MigrationExpectedTransferCount {
  const MigrationExpectedTransferCount({
    required this.count,
    required this.firstTxid,
    required this.startedAt,
  });

  final int count;
  final String firstTxid;
  final DateTime startedAt;

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
  @override
  Map<String, MigrationExpectedTransferCount> build() => const {};

  void setCount(String accountUuid, int count, {required String firstTxid}) {
    state = {
      ...state,
      accountUuid: MigrationExpectedTransferCount(
        count: count,
        firstTxid: firstTxid,
        startedAt: DateTime.now(),
      ),
    };
  }

  void clearCount(String accountUuid) {
    if (!state.containsKey(accountUuid)) return;
    state = {...state}..remove(accountUuid);
  }
}

final migrationExpectedTransferCountProvider =
    NotifierProvider<
      MigrationExpectedTransferCountNotifier,
      Map<String, MigrationExpectedTransferCount>
    >(MigrationExpectedTransferCountNotifier.new);
