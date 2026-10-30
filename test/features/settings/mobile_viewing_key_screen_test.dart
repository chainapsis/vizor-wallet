@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:zcash_wallet/src/rust/api/wallet.dart' show AccountViewingKeys;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_adaptive_frame.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_wallet_sidebar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_page_viewport.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/native_mobile_navigation_geometry.dart';
import '../../fakes/fake_sync_notifier.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../figma_compare/figma_compare_font_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_viewing_key_screen.dart';
import 'package:zcash_wallet/src/features/settings/viewing_key_copy.dart';
import 'package:zcash_wallet/src/features/settings/widgets/viewing_key_content.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

const _ufvk =
    'uview1qthqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'previewonly';
const _uivk = 'uivk1incomingpreviewonly';
const _keys = AccountViewingKeys(ufvk: _ufvk, uivk: _uivk);

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
);

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

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier([this.initialState = _accountState]);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  void setActiveAccount(String uuid) {
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }

  void removeAccountLocally(String uuid) {
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: state.requireValue.accounts
            .where((account) => account.uuid != uuid)
            .toList(),
      ),
    );
  }
}

class _FakeBiometricUnlock extends BiometricUnlock {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;
}

Widget _app({
  String? accountUuid,
  AccountNotifier Function()? accountNotifier,
  Future<AccountViewingKeys> Function(String accountUuid)? viewingKeysLoader,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(accountNotifier ?? _FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock()),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileViewingKeyScreen(
        accountUuid: accountUuid,
        viewingKeysLoader: viewingKeysLoader,
      ),
    ),
  );
}

Future<void> _confirmPasscode(WidgetTester tester) async {
  for (final digit in '111111'.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets(
    'wide viewing key retains sidebar guards and both levels of back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      addTearDown(tester.view.reset);
      final access = Completer<bool>();
      final keys = Completer<AccountViewingKeys>();
      final router = await _adaptiveApp(tester, access: access, keys: keys);
      final idleSidebar = tester.widget<MobileWalletSidebar>(
        find.byType(MobileWalletSidebar),
      );
      expect(idleSidebar.onSelect, isNotNull);
      expect(idleSidebar.onAccountTap, isNull);
      await _confirmPasscode(tester);
      expect(
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onSelect,
        isNull,
      );
      idleSidebar.onSelect!('/home');
      await tester.pump();
      expect(mobileVisiblePath(router), '/settings/viewing-key');
      access.complete(true);
      await tester.pump();
      expect(
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onSelect,
        isNull,
      );
      keys.complete(_keys);
      await tester.pumpAndSettle();
      expect(find.text('Choose what others can view'), findsOneWidget);
      expect(
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onSelect,
        isNotNull,
      );
      expect(
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onAccountTap,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('viewing_key_choose_full')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_viewing_key_value')),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Choose what others can view'), findsOneWidget);
      expect(mobileVisiblePath(router), '/settings/viewing-key');
      await tester.tap(
        find.byKey(const ValueKey('viewing_key_choose_incoming')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Choose what others can view'), findsOneWidget);
      expect(mobileVisiblePath(router), '/settings/viewing-key');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(mobileVisiblePath(router), '/settings');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'wide sidebar can leave selected viewing key without an intermediate back step',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      addTearDown(tester.view.reset);
      final access = Completer<bool>()..complete(true);
      final keys = Completer<AccountViewingKeys>()..complete(_keys);
      final router = await _adaptiveApp(tester, access: access, keys: keys);
      await _confirmPasscode(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('viewing_key_choose_full')));
      await tester.pumpAndSettle();
      tester
          .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
          .onSelect!('/home');
      await tester.pumpAndSettle();
      expect(mobileVisiblePath(router), '/home');
      expect(find.byType(MobileViewingKeyScreen), findsNothing);
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile copy stays at the bottom with key details above and no repeated sharing warning',
    (tester) async {
      for (final type in ViewingKeyType.values) {
        await _pumpRevealLayout(tester, type: type);
        final copy = find.byKey(const ValueKey('mobile_viewing_key_copy'));
        final initial = tester.getRect(copy);
        for (final format in [
          ViewingKeyFormat.qr,
          ViewingKeyFormat.text,
          ViewingKeyFormat.qr,
        ]) {
          await tester.tap(
            find.byKey(ValueKey('viewing_key_format_${format.name}')),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(copy), initial);
          expect(initial.bottom, closeTo(852 - 24 - AppSpacing.s, 0.01));
          final footer = tester.getRect(
            find.byKey(const ValueKey('mobile_viewing_key_footer')),
          );
          final key = tester.getRect(
            find.byKey(const ValueKey('mobile_viewing_key_value')),
          );
          expect(key.bottom + AppSpacing.md, lessThanOrEqualTo(footer.top));
          final description = tester.getRect(
            find.byKey(
              ValueKey(
                type == ViewingKeyType.full
                    ? 'full_viewing_key_warning'
                    : 'incoming_viewing_key_warning',
              ),
            ),
          );
          expect(description.top, closeTo(key.bottom + AppSpacing.md, 0.01));
          expect(description.bottom, lessThan(footer.top));
          expect(
            find.text('Share only with people or services you trust.'),
            findsNothing,
          );
          final outer = find
              .descendant(
                of: find.byKey(
                  const ValueKey('mobile_viewing_key_reveal_scroll'),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          expect(
            tester.state<ScrollableState>(outer).position.maxScrollExtent,
            0,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(find.text('Copied'), findsOneWidget);
        expect(tester.getRect(copy), initial);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('QR and format controls fit within the mobile content margins', (
    tester,
  ) async {
    for (final width in [280.0, 320.0, 393.0]) {
      for (final type in ViewingKeyType.values) {
        await _pumpRevealLayout(tester, size: Size(width, 852), type: type);
        final qr = tester.getRect(
          find.byKey(const ValueKey('request_qr_surface')),
        );
        expect(qr.width, closeTo(qr.height, 0.01));
        for (final rect in [
          qr,
          tester.getRect(find.byKey(const ValueKey('viewing_key_format_qr'))),
          tester.getRect(find.byKey(const ValueKey('viewing_key_format_text'))),
        ]) {
          expect(rect.left, greaterThanOrEqualTo(AppSpacing.sm));
          expect(rect.right, lessThanOrEqualTo(width - AppSpacing.sm));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  for (final format in ViewingKeyFormat.values) {
    testWidgets(
      'bottom actions remain reachable at 320px and 200% in $format',
      (tester) async {
        await _pumpRevealLayout(
          tester,
          size: const Size(320, 568),
          scale: 2,
          format: format,
        );
        expect(tester.takeException(), isNull);
        if (format == ViewingKeyFormat.text) {
          final textScroll = find.descendant(
            of: find.byType(EditableText),
            matching: find.byType(Scrollable),
          );
          expect(
            tester.state<ScrollableState>(textScroll).position.maxScrollExtent,
            0,
          );
        }
        final copy = find.byKey(const ValueKey('mobile_viewing_key_copy'));
        final outer = find
            .descendant(
              of: find.byKey(
                const ValueKey('mobile_viewing_key_reveal_scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(copy, 150, scrollable: outer);
        await tester.pumpAndSettle();
        expect(copy.hitTestable(), findsOneWidget);
        expect(tester.getRect(copy).bottom, lessThanOrEqualTo(568 - 24));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'copy writes the selected key and confirms without covering the title',
    (tester) async {
      final copied = <String>[];
      final haptics = <Object?>[];
      SensitiveClipboard.debugSupportsNativeClipboardOverride = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const clipboard = MethodChannel('com.zcash.wallet/sensitive_clipboard');
      messenger.setMockMethodCallHandler(clipboard, (call) async {
        if (call.method == 'copyText') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      });
      addTearDown(() {
        SensitiveClipboard.debugSupportsNativeClipboardOverride = null;
        messenger.setMockMethodCallHandler(clipboard, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(_app(viewingKeysLoader: (_) async => _keys));
      await _confirmPasscode(tester);
      await _selectFullIfNeeded(tester);
      haptics.clear();
      await tester.tap(find.byKey(const ValueKey('mobile_viewing_key_copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(copied, [_ufvk]);
      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('Viewing key copied'), findsNothing);
      await _selectIncoming(tester);
      await tester.tap(find.byKey(const ValueKey('mobile_viewing_key_copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(copied, [_ufvk, _uivk]);
      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('Viewing key copied'), findsNothing);
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    },
  );
  testWidgets('confirm gate uses the shared passcode layout', (tester) async {
    await tester.pumpWidget(_app(viewingKeysLoader: (uuid) async => _keys));
    await tester.pumpAndSettle();

    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsNothing);
  });

  testWidgets(
    'reveals the requested account viewing key without making it active',
    (tester) async {
      final accountNotifier = _FakeAccountNotifier();
      final requestedUuids = <String>[];

      await tester.pumpWidget(
        _app(
          accountUuid: 'account-2',
          accountNotifier: () => accountNotifier,
          viewingKeysLoader: (uuid) async {
            requestedUuids.add(uuid);
            return _keys;
          },
        ),
      );
      await _confirmPasscode(tester);

      expect(requestedUuids, ['account-2']);
      expect(accountNotifier.state.requireValue.activeAccountUuid, 'account-1');
      expect(
        find.byKey(const ValueKey('viewing_key_choose_incoming')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_viewing_key_copy')),
        findsNothing,
      );
      await _selectFullIfNeeded(tester);
      expect(find.text('Full viewing key'), findsOneWidget);
      expect(find.text(viewingKeyExplanation), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('viewing_key_account_name')),
            )
            .data,
        'Other',
      );
      await _selectFullIfNeeded(tester);
      if (find
          .byKey(const ValueKey('viewing_key_format_text'))
          .evaluate()
          .isNotEmpty) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('viewing_key_format_text')),
        );
        await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
        await tester.pump();
      }
      expect(find.text(_ufvk), findsOneWidget);
      await _selectIncoming(tester);
      await _selectFullIfNeeded(tester);
      if (find
          .byKey(const ValueKey('viewing_key_format_text'))
          .evaluate()
          .isNotEmpty) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('viewing_key_format_text')),
        );
        await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
        await tester.pump();
      }
      expect(find.text(_uivk), findsOneWidget);
      expect(find.text(_ufvk), findsNothing);
      expect(find.text(incomingViewingKeyExplanation), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        find.byKey(const ValueKey('viewing_key_choose_incoming')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_viewing_key_copy')),
        findsNothing,
      );
      expect(find.text(_uivk), findsNothing);
      expect(requestedUuids, ['account-2']);
    },
  );

  testWidgets('retry confirms the passcode again before reloading the key', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        accountUuid: 'account-2',
        viewingKeysLoader: (uuid) async {
          expect(uuid, 'account-2');
          if (++attempts == 1) {
            throw StateError('private implementation detail');
          }
          return _keys;
        },
      ),
    );
    await _confirmPasscode(tester);
    expect(find.textContaining('private implementation detail'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text(_ufvk), findsNothing);
    expect(attempts, 1);
    await _confirmPasscode(tester);
    expect(attempts, 2);
    await _selectFullIfNeeded(tester);
    if (find
        .byKey(const ValueKey('viewing_key_format_text'))
        .evaluate()
        .isNotEmpty) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('viewing_key_format_text')),
      );
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
      await tester.pump();
    }
    expect(find.text(_ufvk), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('viewing_key_account_name')))
          .data,
      'Other',
    );
  });

  testWidgets('reveals a hardware account viewing key', (tester) async {
    final requestedUuids = <String>[];

    await tester.pumpWidget(
      _app(
        accountUuid: 'account-3',
        viewingKeysLoader: (uuid) async {
          requestedUuids.add(uuid);
          return _keys;
        },
      ),
    );
    await _confirmPasscode(tester);

    expect(requestedUuids, ['account-3']);
    await _selectFullIfNeeded(tester);
    if (find
        .byKey(const ValueKey('viewing_key_format_text'))
        .evaluate()
        .isNotEmpty) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('viewing_key_format_text')),
      );
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
      await tester.pump();
    }
    expect(find.text(_ufvk), findsOneWidget);
  });

  testWidgets('shows an error message when the key cannot be loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        accountUuid: 'account-2',
        viewingKeysLoader: (uuid) async => throw StateError('boom'),
      ),
    );
    await _confirmPasscode(tester);

    expect(
      find.text('Confirm access again to try loading this key.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(_ufvk), findsNothing);
  });

  testWidgets('reports when the target account is removed after reveal', (
    tester,
  ) async {
    final accountNotifier = _FakeAccountNotifier();

    await tester.pumpWidget(
      _app(
        accountUuid: 'account-2',
        accountNotifier: () => accountNotifier,
        viewingKeysLoader: (uuid) async => _keys,
      ),
    );
    await _confirmPasscode(tester);
    await _selectFullIfNeeded(tester);
    if (find
        .byKey(const ValueKey('viewing_key_format_text'))
        .evaluate()
        .isNotEmpty) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('viewing_key_format_text')),
      );
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
      await tester.pump();
    }
    expect(find.text(_ufvk), findsOneWidget);

    await _selectIncoming(tester);
    await _selectFullIfNeeded(tester);
    if (find
        .byKey(const ValueKey('viewing_key_format_text'))
        .evaluate()
        .isNotEmpty) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('viewing_key_format_text')),
      );
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
      await tester.pump();
    }
    expect(find.text(_uivk), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewing_key_format_qr')));
    await tester.pump();
    accountNotifier.removeAccountLocally('account-2');
    await tester.pump();

    expect(
      find.text('Selected account changed. Enter your passcode again.'),
      findsOneWidget,
    );
    expect(find.text(_ufvk), findsNothing);
    expect(find.text(_uivk), findsNothing);
    expect(find.bySemanticsLabel('Incoming viewing key QR code'), findsNothing);
  });
  testWidgets(
    'reveal header wraps at 200 percent and Back takes keyboard focus',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppTheme(
            data: AppThemeData.dark,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
          ),
          home: MobileViewingKeyRevealPreview(
            viewingKeys: _keys,
            account: _accountState.activeAccount!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('viewing_key_mobile_title')),
      );
      expect(title.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final back = find.bySemanticsLabel('Back');
      expect(
        tester.getSemantics(back).getSemanticsData().flagsCollection.isFocused,
        ui.Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('mobile_viewing_key_copy')),
        findsNothing,
      );
      await _selectFullIfNeeded(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile_viewing_key_copy')),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('mobile_viewing_key_reveal_scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mobile_viewing_key_copy')).hitTestable(),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
}

Future<void> _pumpRevealLayout(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1,
  ViewingKeyType type = ViewingKeyType.full,
  ViewingKeyFormat format = ViewingKeyFormat.qr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 55, bottom: 24),
            viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: MobileViewingKeyRevealPreview(
        viewingKeys: AccountViewingKeys(
          ufvk: 'uview1${'q' * 491}previewonly',
          uivk: 'uivk1${'q' * 281}previewonly',
        ),
        account: _accountState.activeAccount!,
        initialType: type,
        initialFormat: format,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectFullIfNeeded(WidgetTester tester) async {
  final choice = find.byKey(const ValueKey('viewing_key_choose_full'));
  if (choice.evaluate().isNotEmpty) {
    await tester.ensureVisible(choice);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(choice);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }
}

Future<void> _selectIncoming(WidgetTester tester) async {
  final choice = find.byKey(const ValueKey('viewing_key_choose_incoming'));
  if (choice.evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }
  await tester.ensureVisible(choice);
  await tester.pump(const Duration(milliseconds: 220));
  await tester.tap(choice);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
}

class _DelayedSecurityNotifier extends _FakeSecurityNotifier {
  _DelayedSecurityNotifier(this.access);
  final Completer<bool> access;
  @override
  Future<bool> confirmPassword(String password) => access.future;
}

class _NoNativeGeometry extends NativeMobileNavigationGeometry {
  @override
  bool get supportedHost => false;
}

Future<GoRouter> _adaptiveApp(
  WidgetTester tester, {
  required Completer<bool> access,
  required Completer<AccountViewingKeys> keys,
}) async {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(() => _DelayedSecurityNotifier(access)),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock()),
      mobileNavigationGeometryServiceProvider.overrideWithValue(
        _NoNativeGeometry(),
      ),
    ],
  );
  addTearDown(container.dispose);
  final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
  addTearDown(privacy.dispose);
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            MobileAdaptiveFrame(router: GoRouter.of(context), child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Home destination')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) =>
                const Scaffold(body: Text('Settings destination')),
          ),
          GoRoute(
            path: '/settings/viewing-key',
            pageBuilder: (_, state) => CupertinoPage(
              key: state.pageKey,
              child: MobilePageViewport(
                child: MobileViewingKeyScreen(
                  privacyOverlayController: privacy,
                  viewingKeysLoader: (_) => keys.future,
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push<void>('/settings/viewing-key'));
  await tester.pumpAndSettle();
  return router;
}
