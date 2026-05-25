import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/widgets/address_name_field.dart';
import 'package:zcash_wallet/src/providers/address_labels_provider.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart';

import '../../helpers/in_memory_secure_storage.dart';

const _accountUuid = 'test-account-uuid';
const _address = 'u1testaddress0000000000000000000000000000000000000000000000000000000000';

/// Builds the widget under test inside a ProviderScope with an in-memory
/// store override so no real platform channels are touched.
Widget _harness({
  required InMemorySecureStorage storage,
  String? accountUuid,
  String? address,
}) {
  final store = AppSecureStore.testing(storage: storage);
  return ProviderScope(
    overrides: [appSecureStoreProvider.overrideWithValue(store)],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: AddressNameField(
                key: ValueKey(address ?? _address),
                accountUuid: accountUuid ?? _accountUuid,
                address: address ?? _address,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddressNameField', () {
    testWidgets('pre-fills with existing label when one is stored', (
      tester,
    ) async {
      final storage = InMemorySecureStorage();
      // Pre-seed the store directly via a fresh container.
      {
        final store = AppSecureStore.testing(storage: storage);
        final container = ProviderContainer(
          overrides: [appSecureStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        await container
            .read(addressLabelsProvider.notifier)
            .setLabel(
              accountUuid: _accountUuid,
              address: _address,
              label: 'Donations',
            );
      }

      await tester.pumpWidget(_harness(storage: storage));
      // Let addressLabelsProvider.build() fire its async load.
      await tester.pump();
      await tester.pump(Duration.zero);

      // The field should show the pre-seeded label.
      expect(find.widgetWithText(TextField, 'Donations'), findsOneWidget);
    });

    testWidgets('editing and submitting persists the label', (tester) async {
      final storage = InMemorySecureStorage();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSecureStoreProvider.overrideWithValue(
              AppSecureStore.testing(storage: storage),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context, listen: false);
              return MaterialApp(
                home: AppTheme(
                  data: AppThemeData.light,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 400,
                        child: AddressNameField(
                          accountUuid: _accountUuid,
                          address: _address,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Tap to focus, type a label, then submit.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Mining Reward');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final label = container
          .read(addressLabelsProvider)
          .labelFor(_accountUuid, _address);
      expect(label, 'Mining Reward');
    });

    testWidgets('clearing the field and submitting removes the label', (
      tester,
    ) async {
      final storage = InMemorySecureStorage();
      // Pre-seed label.
      {
        final store = AppSecureStore.testing(storage: storage);
        final container = ProviderContainer(
          overrides: [appSecureStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        await container
            .read(addressLabelsProvider.notifier)
            .setLabel(
              accountUuid: _accountUuid,
              address: _address,
              label: 'Old Label',
            );
      }

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSecureStoreProvider.overrideWithValue(
              AppSecureStore.testing(storage: storage),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context, listen: false);
              return MaterialApp(
                home: AppTheme(
                  data: AppThemeData.light,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 400,
                        child: AddressNameField(
                          accountUuid: _accountUuid,
                          address: _address,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);

      // Clear the field and submit.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final label = container
          .read(addressLabelsProvider)
          .labelFor(_accountUuid, _address);
      expect(label, isNull);
    });
  });
}
