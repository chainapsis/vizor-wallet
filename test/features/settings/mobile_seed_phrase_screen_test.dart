@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Knight', order: 0)],
  activeAccountUuid: 'account-1',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/seed-phrase',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _ControlledSecurityNotifier extends AppSecurityNotifier {
  _ControlledSecurityNotifier(this.result);

  final Future<bool> result;

  @override
  Future<bool> confirmPassword(String password) => result;
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier([this.initialState = _accountState]);

  final AccountState initialState;
  final requestedMnemonicUuids = <String>[];

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<String?> getMnemonicForAccount(String uuid) async {
    requestedMnemonicUuids.add(uuid);
    return _mnemonic;
  }

  void setActiveAccount(String uuid) {
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }
}

class _FakeBiometricUnlock extends BiometricUnlock {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;
}

class _FakeBiometricController {
  _FakeBiometricController({required this.initialState});

  BiometricUnlockState initialState;
  String? passcode;
  var reads = 0;
  String? lastReason;
}

class _FakeBiometricNotifier extends BiometricUnlockNotifier {
  _FakeBiometricNotifier(this.controller);

  final _FakeBiometricController controller;

  @override
  Future<BiometricUnlockState> build() async => controller.initialState;

  @override
  Future<String?> readPasscode({required String reason}) async {
    controller.reads += 1;
    controller.lastReason = reason;
    return controller.passcode;
  }
}

const _faceBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.face,
  ),
  enabled: true,
);

const _fingerprintBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.fingerprint,
  ),
  enabled: true,
);

Widget _app({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
  _FakeBiometricController? biometric,
  String? accountUuid,
  AccountNotifier Function()? accountNotifier,
  AppSecurityNotifier Function()? securityNotifier,
  Future<int> Function(String accountUuid)? birthdayHeightLoader,
  Future<int> Function(int height)? birthdayBlockTimeLoader,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(accountNotifier ?? _FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(
        securityNotifier ?? _FakeSecurityNotifier.new,
      ),
      if (biometric == null)
        biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock())
      else
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricNotifier(biometric),
        ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileSeedPhraseScreen(
        accountUuid: accountUuid,
        screenshotStream: screenshotStream,
        privacyOverlayController: privacyOverlayController,
        loadBirthday: birthdayHeightLoader != null,
        birthdayHeightLoader: birthdayHeightLoader,
        birthdayBlockTimeLoader: birthdayBlockTimeLoader,
      ),
    ),
  );
}

Widget _routerApp(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Future<void> _revealSecret(WidgetTester tester) async {
  for (final digit in '111111'.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('confirm gate uses the shared passcode layout', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Confirm Access'), findsNothing);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Enter Passcode'));
    expect(title.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot Passcode?'), findsOneWidget);
    expect(find.text('Continue to reset Vizor'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Passcode?'), findsNothing);
  });

  testWidgets('reveals the requested account without making it active', (
    tester,
  ) async {
    const accountState = AccountState(
      accounts: [
        AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
      ],
      activeAccountUuid: 'account-1',
    );
    final accountNotifier = _FakeAccountNotifier(accountState);

    await tester.pumpWidget(
      _app(accountUuid: 'account-2', accountNotifier: () => accountNotifier),
    );
    await _revealSecret(tester);

    expect(accountNotifier.requestedMnemonicUuids, ['account-2']);
    expect(accountNotifier.state.requireValue.activeAccountUuid, 'account-1');
    expect(find.text('abandon'), findsOneWidget);
  });

  testWidgets('ignores a stale birthday load after the account changes', (
    tester,
  ) async {
    const accountState = AccountState(
      accounts: [
        AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
      ],
      activeAccountUuid: 'account-1',
    );
    final accountNotifier = _FakeAccountNotifier(accountState);
    final birthdayLoads = <String, Completer<int>>{
      'account-1': Completer<int>(),
      'account-2': Completer<int>(),
    };
    final requestedBlockTimes = <int>[];

    await tester.pumpWidget(
      _app(
        accountNotifier: () => accountNotifier,
        birthdayHeightLoader: (uuid) => birthdayLoads[uuid]!.future,
        birthdayBlockTimeLoader: (height) async {
          requestedBlockTimes.add(height);
          return 0;
        },
      ),
    );
    await _revealSecret(tester);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    expect(
      find.text('Selected account changed. Enter your passcode again.'),
      findsOneWidget,
    );

    await _revealSecret(tester);
    birthdayLoads['account-1']!.complete(111);
    await tester.pump();

    expect(find.text('111'), findsNothing);
    expect(requestedBlockTimes, isEmpty);

    birthdayLoads['account-2']!.complete(222);
    await tester.pumpAndSettle();

    expect(find.text('222'), findsOneWidget);
    expect(requestedBlockTimes, [222]);
  });

  testWidgets('requires another confirmation when the account changes', (
    tester,
  ) async {
    const accountState = AccountState(
      accounts: [
        AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
      ],
      activeAccountUuid: 'account-1',
    );
    final accountNotifier = _FakeAccountNotifier(accountState);
    final confirmation = Completer<bool>();

    await tester.pumpWidget(
      _app(
        accountNotifier: () => accountNotifier,
        securityNotifier: () =>
            _ControlledSecurityNotifier(confirmation.future),
      ),
    );
    await _revealSecret(tester);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    confirmation.complete(true);
    await tester.pumpAndSettle();

    expect(accountNotifier.requestedMnemonicUuids, isEmpty);
    expect(find.text('abandon'), findsNothing);
    expect(
      find.text('Selected account changed. Enter your passcode again.'),
      findsOneWidget,
    );
  });

  testWidgets('confirm gate keeps biometric retry after prompt cancel', (
    tester,
  ) async {
    final biometric = _FakeBiometricController(
      initialState: _faceBiometricState,
    );
    await tester.pumpWidget(_app(biometric: biometric));
    await tester.pumpAndSettle();

    expect(biometric.reads, 1);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsOneWidget);

    biometric.passcode = '111111';
    await tester.tap(find.bySemanticsLabel('Sign in with Face ID'));
    await tester.pumpAndSettle();

    expect(biometric.reads, 2);
    expect(biometric.lastReason, 'Confirm access to your secret passphrase');
    expect(find.text('abandon'), findsOneWidget);
  });

  testWidgets('confirm gate labels fingerprint retry by modality', (
    tester,
  ) async {
    final biometric = _FakeBiometricController(
      initialState: _fingerprintBiometricState,
    );
    await tester.pumpWidget(_app(biometric: biometric));
    await tester.pumpAndSettle();

    expect(biometric.reads, 1);
    expect(find.bySemanticsLabel('Sign in with fingerprint'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
  });

  testWidgets('shows the screenshot warning after the phrase is revealed', (
    tester,
  ) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);

    await tester.pumpWidget(_app(screenshotStream: screenshots.stream));
    await _revealSecret(tester);

    expect(find.text('abandon'), findsOneWidget);

    screenshots.add(null);
    await tester.pumpAndSettle();

    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_seed_screenshot_ack')),
      findsOneWidget,
    );
    final sheetFinder = find.byKey(
      const ValueKey('mobile_seed_screenshot_sheet'),
    );
    final buttonFinder = find.byKey(
      const ValueKey('mobile_seed_screenshot_ack'),
    );
    expect(tester.widget(sheetFinder), isA<MobileModalScaffold>());
    final eye = tester.widget<AppIcon>(
      find.byKey(const ValueKey('mobile_seed_screenshot_icon')),
    );
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_seed_screenshot_title')),
    );
    final titleSize = tester.getSize(
      find.byKey(const ValueKey('mobile_seed_screenshot_title')),
    );
    final body = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_seed_screenshot_body')),
    );
    final buttonLabel = tester.widget<Text>(find.text('I understand'));

    expect(eye.size, 30);
    expect(title.data, 'Don’t take screenshots of your Secret Passphrase');
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    expect(title.style?.fontFamily, 'Young Serif');
    expect(title.style?.fontSize, 24);
    expect(title.style?.height, 28 / 24);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.style?.letterSpacing, -0.4);
    expect(titleSize.width, 253);
    expect(body.textAlign, TextAlign.center);
    expect(body.maxLines, isNull);
    expect(body.overflow, isNull);
    final bodySpan = body.textSpan! as TextSpan;
    expect(
      bodySpan.toPlainText(),
      'Screenshots are not reliable. Anyone who has access to your phone '
      'or your photo library will be able to see your Secret Passphrase. '
      'Write down your Phrase on a piece of paper instead.',
    );
    expect(
      bodySpan.style,
      AppTypography.bodyMedium.copyWith(
        color: AppThemeData.light.colors.text.accent,
      ),
    );
    expect(
      (bodySpan.children!.first as TextSpan).style,
      AppTypography.bodyMediumStrong,
    );
    expect(buttonLabel.style, AppTypography.labelLarge);
    expect(tester.getSize(buttonFinder).height, 50);
  });

  testWidgets(
    'does not show screenshot warning when covered by another route',
    (tester) async {
      final screenshots = StreamController<void>();
      addTearDown(screenshots.close);
      final router = GoRouter(
        initialLocation: '/seed',
        routes: [
          GoRoute(
            path: '/seed',
            builder: (_, _) => MobileSeedPhraseScreen(
              screenshotStream: screenshots.stream,
              loadBirthday: false,
            ),
          ),
          GoRoute(path: '/other', builder: (_, _) => const Text('other route')),
        ],
      );

      await tester.pumpWidget(_routerApp(router));
      await _revealSecret(tester);
      unawaited(router.push('/other'));
      await tester.pumpAndSettle();

      expect(find.text('other route'), findsOneWidget);

      screenshots.add(null);
      await tester.pumpAndSettle();

      expect(find.textContaining('Don’t take screenshots'), findsNothing);
    },
  );

  testWidgets(
    'covers the revealed phrase when the privacy controller is unsafe',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);

      await tester.pumpWidget(
        _app(privacyOverlayController: privacyController),
      );
      await _revealSecret(tester);

      final shield = find.byKey(SensitivePrivacyOverlay.shieldKey);
      expect(shield, findsOneWidget);
      expect(
        tester.getTopLeft(shield).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(MobileTopNav)).dy),
      );

      privacyController.markSafe();
      await tester.pump();

      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );
}
