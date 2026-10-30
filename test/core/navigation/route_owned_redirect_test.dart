import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/route_owned_redirect.dart';

void main() {
  testWidgets('coalesces rebuilds and revalidates the latest request', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    var valid = false;
    var key = 'account-a/round-1';
    final navigated = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [RouteOwnedNavigationObserver()],
        home: ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, _, _) => RouteOwnedRedirect(
            requestKey: key,
            isValid: () => valid,
            onNavigate: () => navigated.add(key),
            child: const Text('Waiting'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(navigated, isEmpty);
    valid = true;
    revision.value++;
    await tester.pumpAndSettle();
    revision.value++;
    await tester.pumpAndSettle();
    expect(navigated, ['account-a/round-1']);
    key = 'account-b/round-2';
    revision.value++;
    await tester.pumpAndSettle();
    expect(navigated, ['account-a/round-1', 'account-b/round-2']);
  });

  for (final action in ['resume', 'invalidate', 'dispose', 'replace request']) {
    testWidgets('nested Navigator and root popup: $action', (tester) async {
      final revision = ValueNotifier(0);
      addTearDown(revision.dispose);
      late BuildContext pageContext;
      var valid = false;
      var navigations = 0;
      var requestKey = 'account-a/round-1';
      String? executedKey;
      final root = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          navigatorObservers: [RouteOwnedNavigationObserver()],
          home: Navigator(
            observers: [RouteOwnedNavigationObserver()],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) {
                pageContext = context;
                return Scaffold(
                  body: ValueListenableBuilder<int>(
                    valueListenable: revision,
                    builder: (_, _, _) => RouteOwnedRedirect(
                      requestKey: requestKey,
                      isValid: () => valid,
                      onNavigate: () {
                        executedKey = requestKey;
                        navigations++;
                      },
                      child: const Text('Waiting'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      showDialog<void>(
        context: pageContext,
        builder: (_) => const AlertDialog(content: Text('Covering popup')),
      );
      await tester.pumpAndSettle();
      // The leaf route is current even though a root popup covers it.
      expect(ModalRoute.of(pageContext)!.isCurrent, isTrue);
      valid = true;
      revision.value++;
      await tester.pumpAndSettle();
      expect(navigations, 0);
      if (action == 'replace request') {
        requestKey = 'account-b/round-2';
        revision.value++;
        await tester.pumpAndSettle();
      }
      if (action == 'invalidate') valid = false;
      if (action == 'dispose') {
        root.currentState!.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const Text('Another screen')),
        );
        await tester.pumpAndSettle();
        // This replaced the popup. Remove the underlying owner too.
        root.currentState!.removeRoute(
          ModalRoute.of(ModalRoute.of(pageContext)!.navigator!.context)!,
        );
      } else {
        root.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(navigations, 0);
        await tester.pumpAndSettle();
        expect(
          navigations,
          action == 'resume' || action == 'replace request' ? 1 : 0,
        );
        if (action == 'replace request') {
          expect(executedKey, 'account-b/round-2');
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(
        navigations,
        action == 'resume' || action == 'replace request' ? 1 : 0,
      );
    });
  }
}
