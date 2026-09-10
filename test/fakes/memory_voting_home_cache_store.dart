import 'dart:async';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';

class MemoryVotingHomeCacheStore implements VotingHomeCacheStore {
  String? value;
  Completer<void>? writeGate;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    await writeGate?.future;
    this.value = value;
  }
}
