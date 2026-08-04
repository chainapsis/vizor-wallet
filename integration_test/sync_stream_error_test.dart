import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  test(
    'startFullSync forwards terminal Rust errors through its stream',
    () async {
      addTearDown(() {
        rust_sync.setSyncMode(mode: 0);
      });

      final stream = rust_sync.startFullSync(
        dbPath: 'unused',
        lightwalletdUrl: 'http://127.0.0.1:1',
        network: 'invalid-test-network',
        mode: 1,
        managedSubmissionRouting: false,
      );

      await expectLater(
        stream,
        emitsInOrder([
          emitsError(
            isA<Object>().having(
              (error) => error.toString(),
              'message',
              contains('Unknown network: invalid-test-network'),
            ),
          ),
          emitsDone,
        ]),
      );
      expect(rust_sync.isSyncRunning(), isFalse);
    },
  );
}
