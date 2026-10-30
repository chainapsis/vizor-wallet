import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/account_persona_draft.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/set_password_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  for (final failure in [
    'before account',
    'interrupted',
    'uncertain',
    'cleanup failure',
  ]) {
    testWidgets(
      'final password step recovers $failure without duplicate creation',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final events = <String>[];
        final security = _Security(
          events,
          cleanupFails: failure == 'cleanup failure',
        );
        final accounts = _Accounts(events, failure);
        final args =
            const SetPasswordScreenArgs.create(
              mnemonic: 'draft phrase',
            ).withPersona(
              const AccountPersona(
                name: 'My savings',
                profilePictureId: 'pfp-03',
              ),
            );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => SetPasswordScreen(args: args),
            ),
            GoRoute(
              path: '/home',
              builder: (_, _) => const Text('Home destination'),
            ),
            GoRoute(
              path: '/unlock',
              builder: (_, _) => const Text('Unlock destination'),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
              appSecurityProvider.overrideWith(() => security),
              accountProvider.overrideWith(() => accounts),
              syncProvider.overrideWith(_IdleSync.new),
              appBootstrapRetryProvider.overrideWithValue(() async {
                events.add('reload');
                expect(security.state.requiresUnlock, isTrue);
                router.go('/unlock');
              }),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, child) => AppTheme(
                data: AppThemeData.light,
                child: Material(child: child!),
              ),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey('set_password_password_field')),
          'Password1!',
        );
        await tester.enterText(
          find.byKey(const ValueKey('set_password_confirm_field')),
          'Password1!',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('set_password_submit_button')),
        );
        await tester.pumpAndSettle();
        expect(accounts.calls, 1);
        expect(accounts.name, 'My savings');
        expect(accounts.picture, 'pfp-03');

        if (failure == 'before account') {
          expect(events, ['prepare', 'account', 'rollback']);
          expect(find.text('Retry setup'), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey('set_password_submit_button')),
          );
          await tester.pumpAndSettle();
          expect(accounts.calls, 2);
          expect(events, [
            'prepare',
            'account',
            'rollback',
            'prepare',
            'account',
            'commit',
          ]);
          expect(find.text('Home destination'), findsOneWidget);
        } else {
          expect(events, ['prepare', 'account', 'commit']);
          expect(find.text('Retry setup'), findsOneWidget);
          expect(find.text('Customise Account').hitTestable(), findsNothing);
          // Recovery must work without requiring the user to submit a credential
          // again, and must retain the verifier for the potentially saved account.
          await tester.enterText(
            find.byKey(const ValueKey('set_password_password_field')),
            '',
          );
          await tester.enterText(
            find.byKey(const ValueKey('set_password_confirm_field')),
            '',
          );
          await tester.pump();
          await tester.tap(find.text('Retry setup'));
          await tester.pumpAndSettle();
          expect(accounts.calls, 1);
          expect(events, ['prepare', 'account', 'commit', 'lock', 'reload']);
          expect(find.text('Unlock destination'), findsOneWidget);
        }
      },
    );
  }
}

class _Accounts extends AccountNotifier {
  _Accounts(this.events, this.failure);
  final List<String> events;
  final String failure;
  int calls = 0;
  String? name;
  String? picture;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    events.add('account');
    calls++;
    this.name = name;
    picture = profilePictureId;
    if (calls > 1) return;
    switch (failure) {
      case 'cleanup failure':
      case 'interrupted':
        throw WalletAccountSetupInterruptedException(
          'saved-account',
          StateError('storage unavailable'),
        );
      case 'uncertain':
        throw WalletAccountStateUncertainException(
          StateError('DB result unknown'),
        );
      default:
        throw StateError('network unavailable');
    }
  }
}

class _Security extends AppSecurityNotifier {
  _Security(this.events, {this.cleanupFails = false});
  final bool cleanupFails;
  final List<String> events;
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: true);
  @override
  Future<void> preparePasswordSetup(String password) async =>
      events.add('prepare');
  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();
  @override
  void commitPasswordSetup() {
    events.add('commit');
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async => events.add('rollback');
  @override
  Future<void> finishPasswordSetupAfterFailure({
    required bool accountMayExist,
  }) async {
    await super.finishPasswordSetupAfterFailure(
      accountMayExist: accountMayExist,
    );
    if (cleanupFails) throw StateError('credential journal unavailable');
  }

  @override
  void lock() {
    events.add('lock');
    state = state.copyWith(isUnlocked: false);
  }
}

class _IdleSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
  @override
  bool needsPauseForWalletMutation() => false;
}
