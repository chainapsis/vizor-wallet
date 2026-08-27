import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/private_state_sync_control.dart';
import 'package:zcash_wallet/src/providers/private_state_sync_provider.dart';

void main() {
  testWidgets('desktop private sync control defaults off and persists opt-in', (
    tester,
  ) async {
    final store = _RecordingStore();
    await tester.pumpWidget(_harness(store, const PrivateStateSyncControl()));

    expect(find.text('Off'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings_private_state_sync_row')),
    );
    await tester.pump();

    expect(store.values, [true]);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('desktop control renders a save failure without an async error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const _FailingStore(), const PrivateStateSyncControl()),
    );

    await tester.tap(
      find.byKey(const ValueKey('settings_private_state_sync_row')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('settings_private_state_sync_error')),
      findsOneWidget,
    );
    expect(find.text('Off'), findsOneWidget);
  });
}

Widget _harness(PrivateStateSyncSettingsStore store, Widget child) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      privateStateSyncSettingsStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(
      builder: (_, materialChild) =>
          AppTheme(data: AppThemeData.light, child: materialChild!),
      home: Scaffold(
        body: Center(child: SizedBox(width: 420, child: child)),
      ),
    ),
  );
}

class _RecordingStore implements PrivateStateSyncSettingsStore {
  final values = <bool>[];

  @override
  Future<void> writeEnabled(bool enabled) async => values.add(enabled);
}

class _FailingStore implements PrivateStateSyncSettingsStore {
  const _FailingStore();

  @override
  Future<void> writeEnabled(bool enabled) => throw StateError('write failed');
}
