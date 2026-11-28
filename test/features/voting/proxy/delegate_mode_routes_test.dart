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
  });
}
