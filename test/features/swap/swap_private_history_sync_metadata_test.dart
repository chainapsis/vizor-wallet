import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not rewrite byte-identical archive metadata', () async {
    final storage = _CountingStorage();
    final store = AppSecureStoreFinalizedActivityArchiveMetadataStore(
      AppSecureStore.testing(storage: storage),
    );
    final snapshot = Uint8List.fromList([1, 2, 3]);

    await store.save(
      accountUuid: 'account-a',
      kind: SwapPrivateHistoryKind.swap,
      metadata: FinalizedActivityArchiveMetadata(
        lastSlot: 1,
        hiddenRecordIds: const {'hidden'},
        lastSnapshot: snapshot,
      ),
    );
    await store.save(
      accountUuid: 'account-a',
      kind: SwapPrivateHistoryKind.swap,
      metadata: FinalizedActivityArchiveMetadata(
        lastSlot: 1,
        hiddenRecordIds: const {'hidden'},
        lastSnapshot: Uint8List.fromList(snapshot),
      ),
    );

    expect(storage.writeCount, 1);
  });
}

class _CountingStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};
  int writeCount = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeCount++;
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
