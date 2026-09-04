import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_viewing_key_screen.dart';
import 'package:zcash_wallet/src/features/settings/viewing_key_copy.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _ufvk =
    'uview1qthqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'previewonly';

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
    AccountInfo(
      uuid: 'account-3',
      name: 'Keystone',
      order: 2,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1currentaddress',
);

void main() {
  setUp(() {
    // Copying a secret schedules the real one-minute clipboard auto-clear
    // timer, which would outlive the widget tree. Hold the expiry open for the
    // duration of each test; the clearing itself is covered by
    // test/core/clipboard/sensitive_clipboard_test.dart.
    SensitiveClipboard.debugExpirationDelay = (_) => Completer<void>().future;
  });

  tearDown(() {
    SensitiveClipboard.debugExpirationDelay = null;
    SensitiveClipboard.debugCancelPendingExpiration();
  });

  testWidgets(
    'reveals the requested account viewing key without making it active',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: true,
      );
      addTearDown(privacyController.dispose);
      final requestedUuids = <String>[];

      final copiedText = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        _harness(
          privacyController: privacyController,
          accountUuid: 'account-2',
          ufvkLoader: (uuid) async {
            requestedUuids.add(uuid);
            return _ufvk;
          },
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'Correct123!');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Confirm password'));
      await tester.pump();

      expect(requestedUuids, ['account-2']);
      expect(find.text(_ufvk), findsOneWidget);
      expect(find.text('Full Viewing Key'), findsOneWidget);
      expect(find.text(viewingKeyExplanation), findsOneWidget);
      expect(find.text(viewingKeyPrivacyNotice), findsOneWidget);
      final explanationText = tester.widget<Text>(
        find.byKey(const ValueKey('viewing_key_explanation')),
      );
      final explanationSpans =
          (explanationText.textSpan! as TextSpan).children!;
      final explanationContext = tester.element(
        find.byKey(const ValueKey('viewing_key_explanation')),
      );
      expect(
        (explanationSpans.first as TextSpan).style,
        AppTypography.bodyLarge.copyWith(
          color: AppTheme.of(explanationContext).colors.text.accent,
          fontWeight: FontWeight.w600,
        ),
      );
      expect((explanationSpans.last as TextSpan).style, isNull);
      final keyText = tester.widget<Text>(find.text(_ufvk));
      final keyContext = tester.element(find.text(_ufvk));
      expect(keyText.style?.color, AppTheme.of(keyContext).colors.text.accent);

      final copyButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('settings_viewing_key_copy_button')),
      );
      expect(copyButton.variant, AppButtonVariant.secondary);
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('settings_viewing_key_copy_button')),
      );
      await tester.pump();
      await tester.pump();
      expect(copiedText, [_ufvk]);
      expect(find.text('Copied'), findsOneWidget);
    },
  );

  testWidgets('reveals a hardware account viewing key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountUuid: 'account-3',
        ufvkLoader: (uuid) async => _ufvk,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(find.text(_ufvk), findsOneWidget);
  });

  testWidgets('shows an error card when the key cannot be loaded', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountUuid: 'account-2',
        ufvkLoader: (uuid) async => throw StateError('boom'),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(
      find.textContaining('Viewing key is not available for this account'),
      findsOneWidget,
    );
    expect(find.text(_ufvk), findsNothing);
  });

  testWidgets('describes removal of the requested account accurately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    late _FakeAccountNotifier accountNotifier;

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountUuid: 'account-2',
        ufvkLoader: (uuid) async => _ufvk,
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();
    accountNotifier.removeRequestedAccount();
    await tester.pump();

    expect(
      find.text('Selected account changed. Enter your password again.'),
      findsOneWidget,
    );
  });
}

Widget _harness({
  required SensitivePrivacyOverlayController privacyController,
  required String accountUuid,
  required Future<String> Function(String accountUuid) ufvkLoader,
  AccountNotifier Function()? accountNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/settings/viewing-key',
    routes: [
      GoRoute(
        path: '/settings/viewing-key',
        builder: (_, _) => SettingsViewingKeyScreen(
          accountUuid: accountUuid,
          privacyOverlayController: privacyController,
          ufvkLoader: ufvkLoader,
        ),
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(accountNotifier ?? _FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/viewing-key',
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

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _accountState;

  void removeRequestedAccount() {
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: state.requireValue.accounts
            .where((account) => account.uuid != 'account-2')
            .toList(),
      ),
    );
  }
}

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}
