@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/privacy/flip_to_hide_balance_host.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/flip_to_hide_balance_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({required this.unlocked});

  final bool unlocked;

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: unlocked);
}

class _FakeWalletNotifier extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(hasWallet: true);
}

class _FakePrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  bool build() => false;

  @override
  Future<void> set(bool enabled) async => state = enabled;
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

  setUp(() => facing = StreamController<double>.broadcast());
  tearDown(() => facing.close());

  Future<void> pumpHost(
    WidgetTester tester, {
    bool enabled = true,
    bool unlocked = true,
  }) async {
    container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(
          () => _FakeSecurityNotifier(unlocked: unlocked),
        ),
        walletProvider.overrideWith(_FakeWalletNotifier.new),
        privacyModeProvider.overrideWith(_FakePrivacyModeNotifier.new),
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
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
          home: FlipToHideBalanceHost(
            facingEvents: () => facing.stream,
            child: const SizedBox.expand(),
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
}
