import 'package:flutter_riverpod/flutter_riverpod.dart';

const migrationExpectedTransferCountTtl = Duration(seconds: 90);

class MigrationExpectedTransferCount {
  const MigrationExpectedTransferCount({
    required this.count,
    required this.startedAt,
  });

  final int count;
  final DateTime startedAt;

  bool isExpired(DateTime now) {
    return now.difference(startedAt) > migrationExpectedTransferCountTtl;
  }
}

class MigrationExpectedTransferCountNotifier
    extends Notifier<Map<String, MigrationExpectedTransferCount>> {
  @override
  Map<String, MigrationExpectedTransferCount> build() => const {};

  void setCount(String accountUuid, int count) {
    state = {
      ...state,
      accountUuid: MigrationExpectedTransferCount(
        count: count,
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
