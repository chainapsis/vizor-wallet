import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_route_table.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';

void main() {
  group('delegate mode routes', () {
    test('desktop and mobile register the same paths', () {
      final desktop = delegateModeDesktopRoutes(guard: (child) => child);
      final mobile = delegateModeMobileRoutes(guard: (child) => child);
      expect(desktop.map((r) => r.path), mobile.map((r) => r.path));
      expect(desktop.map((r) => r.path).toSet(), {
        kDelegateModePath,
        kDelegateKeyImportPath,
        kDelegateRegistrationPath,
        kDelegateBallotPath,
        kDelegateRetirePath,
      });
    });

    test('none collides with a delegator route', () {
      final delegator = proxyDelegationDesktopRoutes(
        guard: (child) => child,
      ).map((r) => r.path).toSet();
      final delegate = delegateModeDesktopRoutes(
        guard: (child) => child,
      ).map((r) => r.path).toSet();
      expect(delegator.intersection(delegate), isEmpty);
    });

    test('the ballot builder matches its pattern', () {
      final location = delegateBallotRoute('r 1');
      final regex = RegExp(
        '^${kDelegateBallotPath.replaceAll(RegExp(r':\w+'), r'[^/]+')}\$',
      );
      expect(regex.hasMatch(location), isTrue);
      expect(location, '/voting/delegate-mode/rounds/r%201');
    });
  });
}
