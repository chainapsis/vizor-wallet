import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_tab_history.dart';

void main() {
  Future<WidgetRef> pumpRef(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('falls back to /home when there is no previous tab', (
    tester,
  ) async {
    final ref = await pumpRef(tester);
    expect(resolveMobileBackPath(ref, currentPath: '/activity'), '/home');
  });

  testWidgets('returns the previous tab when it differs from the current one', (
    tester,
  ) async {
    final ref = await pumpRef(tester);
    ref.read(mobilePreviousTabPathProvider.notifier).record('/settings');
    expect(resolveMobileBackPath(ref, currentPath: '/activity'), '/settings');
  });

  testWidgets(
    'falls back to /home when the previous tab is the current route',
    (tester) async {
      // Reachable via Home->Activity->Settings then Settings Back go(/activity):
      // the record still holds the current tab, which would make Back a no-op.
      final ref = await pumpRef(tester);
      ref.read(mobilePreviousTabPathProvider.notifier).record('/activity');
      expect(resolveMobileBackPath(ref, currentPath: '/activity'), '/home');
    },
  );
}
