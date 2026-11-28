import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/proxy/composite_delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_key_store.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_mode_home_screen.dart';

import 'support/delegate_mode_fakes.dart';
import 'support/proxy_rust_fake.dart';

/// A provider body that fails the test if anything builds it.
Never _untouchable(String name) =>
    throw TestFailure('$name was built with the flag off');

void main() {
  useProxyRustFake();

  testWidgets('with the flag off delegate mode builds no repository, key '
      'store or verifier client, and shows no entry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyDelegationFeatureEnabledProvider.overrideWithValue(false),
          delegateModeRepositoryProvider.overrideWith(
            (_) => _untouchable('the delegate-mode repository'),
          ),
          delegateKeyStoreProvider.overrideWith(
            (_) => _untouchable('the delegate key store'),
          ),
          delegateVerifierClientProvider.overrideWith(
            (_) => _untouchable('the verifier client'),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: const Scaffold(body: DelegateModeEntryLink()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('delegate_mode_entry')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('with the flag on the repository is zcash_voting\'s, over the '
      'secure-storage key store', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(delegateModeRepositoryProvider),
      isA<CompositeDelegateModeRepository>(),
    );
    expect(
      container.read(delegateKeyStoreProvider),
      isA<SecureStoreDelegateKeyStore>(),
    );
  });

  test('reads never ask the re-auth or read the key', () async {
    final mode = RealDelegateMode(now: DateTime(2026, 10, 7, 12))
      ..registeredKey(1);
    await mode.repository.status();
    await mode.repository.rounds();
    expect(mode.keys.reads, 0);
    expect(mode.reauths, 0);
  });
}
