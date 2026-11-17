@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/privacy/flip_to_hide_balance_host.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/privacy_mode_persistence.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/flip_to_hide_balance_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

import '../../fakes/controlled_privacy_store.dart';
import '../../support/app_test_fonts.dart';

class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({required this.unlocked});

  final bool unlocked;

  void lockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: unlocked);
}

class _FakeWalletNotifier extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(hasWallet: true);
}

class _InitialPrivacyModeNotifier extends PrivacyModeNotifier {
  _InitialPrivacyModeNotifier(ControlledPrivacyStore store, this.hidden)
    : super.testing(store: store);

  final bool hidden;

  @override
  bool build() => hidden;
}

class _FakeFlipToHideNotifier extends FlipToHideBalanceNotifier {
  _FakeFlipToHideNotifier(this.initial);

  final bool initial;

  @override
  bool build() => initial;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}

void main() {
  late StreamController<double> facing;
  late ProviderContainer container;
  late ControlledPrivacyStore store;

  setUpAll(loadAppTestFonts);

  setUp(() {
    facing = StreamController<double>.broadcast();
    store = ControlledPrivacyStore();
  });
  tearDown(() => facing.close());

  Future<void> pumpHost(
    WidgetTester tester, {
    bool enabled = true,
    bool unlocked = true,
    bool hidden = false,
    Locale? locale,
  }) async {
    container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(
          () => _FakeSecurityNotifier(unlocked: unlocked),
        ),
        walletProvider.overrideWith(_FakeWalletNotifier.new),
        privacyModeProvider.overrideWith(
          () => _InitialPrivacyModeNotifier(store, hidden),
        ),
        flipToHideBalanceProvider.overrideWith(
          () => _FakeFlipToHideNotifier(enabled),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(walletProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appSupportedLocales(),
          locale: locale,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
          home: FlipToHideBalanceHost(
            facingEvents: () => facing.stream,
            child: Consumer(
              builder: (_, ref, _) => Text(
                ref.watch(privacyModeProvider) ? 'masked' : '123.45 ZEC',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> flip(WidgetTester tester, {required bool back}) async {
    facing.add(-0.8);
    facing.add(0.9);
    if (back) facing.add(-0.8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a flip hides amounts and a flip back shows them', (
    tester,
  ) async {
    await pumpHost(tester);

    await flip(tester, back: true);
    expect(container.read(privacyModeProvider), isTrue);
    expect(find.text('Balance hidden'), findsOneWidget);

    await flip(tester, back: true);
    expect(container.read(privacyModeProvider), isFalse);
    expect(find.text('Balance shown'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a phone left screen-down only hides', (tester) async {
    await pumpHost(tester);

    await flip(tester, back: false);
    expect(container.read(privacyModeProvider), isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the sensor is off while the setting is off', (tester) async {
    await pumpHost(tester, enabled: false);
    expect(facing.hasListener, isFalse);

    container.read(flipToHideBalanceProvider.notifier).set(true);
    await tester.pump();
    expect(facing.hasListener, isTrue);
  });

  testWidgets('the sensor is off while the wallet is locked', (tester) async {
    await pumpHost(tester, unlocked: false);
    expect(facing.hasListener, isFalse);
  });

  testWidgets('the sensor stops in the background and resumes', (tester) async {
    await pumpHost(tester);
    expect(facing.hasListener, isTrue);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(facing.hasListener, isFalse);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(facing.hasListener, isTrue);
  });
  testWidgets('slow hide masks content before feedback or persistence', (
    tester,
  ) async {
    await pumpHost(tester);
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    store.blocked = Completer<void>();
    await flip(tester, back: true);
    expect(haptics, isEmpty);
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.text('masked'), findsOneWidget);
    expect(find.text('Balance hidden'), findsNothing);
    store.blocked!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Balance hidden'), findsOneWidget);
    expect(haptics, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('failed hide stays masked and reports failure without success', (
    tester,
  ) async {
    await pumpHost(tester);
    store.failWrites = true;
    await flip(tester, back: true);
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.text('Balance hidden'), findsNothing);
    expect(
      find.text("Balance hidden, but the setting couldn't be saved."),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('failed reveal stays masked and does not announce success', (
    tester,
  ) async {
    await pumpHost(tester, hidden: true);
    store.failWrites = true;
    await flip(tester, back: true);
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.text('Balance shown'), findsNothing);
    expect(find.text("Couldn't show your balance. Try again."), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a pending reveal can be hidden by the next down gesture', (
    tester,
  ) async {
    await pumpHost(tester, hidden: true);
    store.blocked = Completer<void>();
    await flip(tester, back: true);
    expect(find.text('123.45 ZEC'), findsNothing);
    await flip(tester, back: false);
    store.blocked!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.text('Balance shown'), findsNothing);
    expect(find.text('Balance hidden'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('eye toggle supersedes pending flip feedback', (tester) async {
    await pumpHost(tester, hidden: true);
    store.blocked = Completer<void>();
    await flip(tester, back: true);
    final eye = container.read(privacyModeProvider.notifier).toggle();
    store.blocked!.complete();
    await tester.pump();
    await eye;
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.text('Balance shown'), findsNothing);
    expect(find.text('Balance hidden'), findsNothing);
  });

  testWidgets('locking while a reveal saves keeps it hidden and silent', (
    tester,
  ) async {
    await pumpHost(tester, hidden: true);
    store.blocked = Completer<void>();
    await flip(tester, back: true);
    (container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier)
        .lockForTest();
    store.blocked!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(privacyModeProvider), isTrue);
    expect(store.values.values, everyElement('true'));
    expect(find.text('Balance shown'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background then foreground invalidates pending reveal feedback',
    (tester) async {
      await pumpHost(tester, hidden: true);
      store.blocked = Completer<void>();
      await flip(tester, back: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      store.blocked!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(privacyModeProvider), isTrue);
      expect(find.text('Balance shown'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing the host cancels a reveal and its feedback', (
    tester,
  ) async {
    await pumpHost(tester, hidden: true);
    store.blocked = Completer<void>();
    await flip(tester, back: true);
    await tester.pumpWidget(const SizedBox());
    store.blocked!.complete();
    await tester.pump();
    expect(container.read(privacyModeProvider), isTrue);
    expect(store.values.values, everyElement('true'));
    expect(tester.takeException(), isNull);
  });
  for (final endSession in [false, true]) {
    testWidgets(
      'accepted reveal cleanup failure endSession=$endSession has consistent feedback',
      (tester) async {
        await pumpHost(tester, hidden: true);
        final haptics = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        store.beforeOperation = (operation) async {
          if (operation == 'delete:$kPrivacyModeRevealPendingKey') {
            expect(container.read(privacyModeProvider), isFalse);
            if (endSession) {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.hidden,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            }
            throw StateError('cleanup failed');
          }
        };
        await flip(tester, back: true);
        expect(container.read(privacyModeProvider), isFalse);
        expect(find.text('123.45 ZEC'), findsOneWidget);
        expect(
          find.text('Balance shown'),
          endSession ? findsNothing : findsOneWidget,
        );
        expect(haptics, hasLength(endSession ? 0 : 1));
        expect(store.values[kPrivacyModeRevealPendingKey], 'true');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final cancellation in ['lock', 'background', 'disable', 'dispose']) {
    for (final afterCommit in [false, true]) {
      testWidgets(
        '$cancellation plus failed rollback (afterCommit=$afterCommit) stays hidden after restart',
        (tester) async {
          await pumpHost(tester, hidden: true);
          store.values[kPrivacyModeEnabledKey] = 'true';
          final entered = Completer<void>();
          final release = Completer<void>();
          final haptics = <MethodCall>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          store.beforeOperation = (operation) async {
            if (operation == 'write:$kPrivacyModeEnabledKey=false') {
              entered.complete();
              await release.future;
            }
            if (!afterCommit &&
                operation == 'write:$kPrivacyModeEnabledKey=true') {
              throw StateError('rollback failed');
            }
          };
          store.afterOperation = (operation) {
            if (afterCommit &&
                operation == 'write:$kPrivacyModeEnabledKey=true') {
              throw StateError('rollback acknowledgement failed');
            }
          };
          await flip(tester, back: true);
          await entered.future;
          switch (cancellation) {
            case 'lock':
              (container.read(appSecurityProvider.notifier)
                      as _FakeSecurityNotifier)
                  .lockForTest();
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.hidden,
              );
            case 'disable':
              await container
                  .read(flipToHideBalanceProvider.notifier)
                  .set(false);
            case 'dispose':
              await tester.pumpWidget(const SizedBox.shrink());
          }
          release.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(container.read(privacyModeProvider), isTrue);
          expect(store.values[kPrivacyModeRevealPendingKey], 'true');
          expect(find.text('123.45 ZEC'), findsNothing);
          expect(find.text('Balance shown'), findsNothing);
          expect(haptics, isEmpty);
          expect(tester.takeException(), isNull);

          final restarted = ControlledPrivacyStore()
            ..values.addAll(store.values);
          final hidden = await PrivacyModePersistence(
            restarted,
          ).readAndRecover();
          await tester.pumpWidget(const SizedBox.shrink());
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          store = restarted;
          await pumpHost(tester, hidden: hidden);
          expect(find.text('masked'), findsOneWidget);
          expect(find.text('123.45 ZEC'), findsNothing);
          expect(find.text('Balance shown'), findsNothing);
        },
      );
    }
  }

  for (final language in ['en', 'ko', 'zh']) {
    for (final initiallyHidden in [false, true]) {
      testWidgets(
        'failure feedback fits a 360px phone ($language, hidden=$initiallyHidden)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await pumpHost(
            tester,
            hidden: initiallyHidden,
            locale: Locale(language),
          );
          store.failWrites = true;
          await flip(tester, back: true);
          final l10n = tester.element(find.byType(FlipToHideBalanceHost)).l10n;
          expect(
            find.text(
              initiallyHidden
                  ? l10n.privacyBalanceShowFailed
                  : l10n.privacyBalanceHiddenSaveFailed,
            ),
            findsOneWidget,
          );
          expect(find.text('123.45 ZEC'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 5));
        },
      );
    }
  }
}
