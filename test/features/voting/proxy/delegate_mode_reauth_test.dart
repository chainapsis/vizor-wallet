import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_fakes.dart';

/// Pumps a page whose button opens the production gate for [purpose];
/// returns the results it resolves with.
Future<(List<bool>, FakeDelegateSecurity)> _pumpGate(
  WidgetTester tester,
  DelegateReauthPurpose purpose,
) async {
  final security = FakeDelegateSecurity(password: 'correct horse');
  final results = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSecurityProvider.overrideWith(() => security)],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async => results.add(
                await ref.read(delegateReauthProvider)(context, purpose),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (results, security);
}

/// The password field inside the gate.
Finder get _password => find.descendant(
  of: find.byKey(const ValueKey('delegate_reauth_card')),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('desktop asks for the wallet password with the purpose', (
    tester,
  ) async {
    final (results, security) = await _pumpGate(
      tester,
      DelegateReauthPurpose.signBallot,
    );
    expect(
      find.text(DelegateReauthPurpose.signBallot.subtitle(testL10n)),
      findsOne,
    );
    await tester.enterText(_password, 'wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(testL10n.passwordIncorrect), findsOne);
    expect(results, isEmpty);

    await tester.enterText(_password, 'correct horse');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(security.attempts, ['wrong', 'correct horse']);
    expect(find.byKey(const ValueKey('delegate_reauth_card')), findsNothing);
  });

  testWidgets('cancel resolves false without checking anything', (
    tester,
  ) async {
    final (results, security) = await _pumpGate(
      tester,
      DelegateReauthPurpose.retire,
    );
    expect(
      find.text(DelegateReauthPurpose.retire.subtitle(testL10n)),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('delegate_reauth_cancel')));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(security.attempts, isEmpty);
  });
}
