@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_interaction_listener.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';

void main() {
  testWidgets('records mobile pointer interactions without consuming them', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var taps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SyncKeepAwakeInteractionListener(
              child: Center(
                child: GestureDetector(
                  key: const ValueKey('target'),
                  onTap: () => taps += 1,
                  child: const SizedBox.square(
                    dimension: 120,
                    child: Center(child: Text('Tap target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final initialRevision = container
        .read(syncKeepAwakeInteractionProvider)
        .revision;

    await tester.tap(find.byKey(const ValueKey('target')));
    await tester.pump();

    expect(taps, 1);
    expect(
      container.read(syncKeepAwakeInteractionProvider).revision,
      greaterThan(initialRevision),
    );

    final afterTapRevision = container
        .read(syncKeepAwakeInteractionProvider)
        .revision;

    await tester.drag(find.byKey(const ValueKey('target')), const Offset(8, 0));
    await tester.pump();

    expect(
      container.read(syncKeepAwakeInteractionProvider).revision,
      greaterThan(afterTapRevision),
    );
  });
}
