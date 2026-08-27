@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/private_state_sync_control.dart';
import 'package:zcash_wallet/src/providers/private_state_sync_provider.dart';

void main() {
  testWidgets('mobile private sync card defaults off and persists opt-in', (
    tester,
  ) async {
    final store = _RecordingStore();
    await tester.pumpWidget(_harness(store));

    final row = find.byKey(
      const ValueKey('mobile_settings_private_state_sync_row'),
    );
    expect(tester.getSemantics(row).value, 'Off');

    await tester.tap(row);
    await tester.pump();

    expect(store.values, [true]);
    expect(tester.getSemantics(row).value, 'On');
  });
}

Widget _harness(PrivateStateSyncSettingsStore store) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      privateStateSyncSettingsStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: const Scaffold(
        body: Center(
          child: SizedBox(width: 390, child: MobilePrivateStateSyncCard()),
        ),
      ),
    ),
  );
}

class _RecordingStore implements PrivateStateSyncSettingsStore {
  final values = <bool>[];

  @override
  Future<void> writeEnabled(bool enabled) async => values.add(enabled);
}
