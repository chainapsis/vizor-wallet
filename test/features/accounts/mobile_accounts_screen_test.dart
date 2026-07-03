@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_account_avatar.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';
import 'package:zcash_wallet/src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/account_edit_sheets.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

AccountInfo _account(String uuid, String name, {bool isSeedAnchor = false}) =>
    AccountInfo(
      uuid: uuid,
      name: name,
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isSeedAnchor: isSeedAnchor,
    );

AppBootstrapState _bootstrap(AccountState accounts) => AppBootstrapState(
  initialLocation: '/accounts',
  initialAccountState: accounts,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app(
  AccountState accounts, {
  AccountNotifier Function()? accountNotifier,
  BiometricUnlockNotifier Function()? biometricNotifier,
  SyncNotifier Function()? syncNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/accounts',
    routes: [
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const MobileAccountsScreen(),
      ),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account route'),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome route')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accounts)),
      if (accountNotifier != null)
        accountProvider.overrideWith(accountNotifier),
      biometricUnlockProvider.overrideWith(
        biometricNotifier ?? _FakeBiometricUnlockNotifier.new,
      ),
      syncProvider.overrideWith(
        syncNotifier ?? () => FakeSyncNotifier(SyncState()),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;
  var resetCount = 0;
  String? removedUuid;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> removeAccount(String uuid) async {
    removedUuid = uuid;
  }

  @override
  Future<void> resetWallet() async {
    resetCount += 1;
    state = const AsyncData(AccountState());
  }
}

class _FakeWalletMutationSyncNotifier extends FakeSyncNotifier {
  _FakeWalletMutationSyncNotifier() : super(SyncState());

  var pauseCount = 0;
  var resumeCount = 0;
  var clearCachedDbPathCount = 0;

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    pauseCount += 1;
    await onStoppingSync?.call();
    return const WalletMutationSyncPause(
      hadActiveSync: true,
      hadPolling: false,
      hadBackgroundSync: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    resumeCount += 1;
  }

  @override
  void clearCachedWalletDbPath() {
    clearCachedDbPathCount += 1;
  }
}

class _FakeBiometricUnlockNotifier extends BiometricUnlockNotifier {
  var disableCount = 0;

  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;

  @override
  Future<void> disable() async {
    disableCount += 1;
    state = const AsyncData(BiometricUnlockState.initial);
  }
}

Widget _nestedShellApp(AccountState accounts, ValueNotifier<int> tabTaps) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accounts)),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: AppMobileShell(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const MobileAccountsScreen(),
          ),
        ),
        tabBar: GestureDetector(
          key: const ValueKey('test_mobile_tab_bar'),
          behavior: HitTestBehavior.opaque,
          onTap: () => tabTaps.value += 1,
          child: const SizedBox(
            height: kMobileTabBarHeight,
            child: Center(child: Text('tab')),
          ),
        ),
      ),
    ),
  );
}

Widget _profilePictureSheetHarness() {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    home: Builder(
      builder: (context) => GestureDetector(
        onTap: () => showProfilePictureSheet(
          context,
          selectedId: kDefaultProfilePictureId,
        ),
        child: const Text('open pfp'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1200)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('groups the active account under Current and the rest under '
      'Other', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    expect(find.text('Viking'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Accounts'));
    expect(title.style?.fontSize, AppTypography.headlineLarge.fontSize);
    expect(title.style?.height, AppTypography.headlineLarge.height);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_accounts_row_a'))),
      const Size(456, 44),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_accounts_row_a')),
          matching: find.byType(MobileAccountAvatar),
        ),
      ),
      const Size(40, 40),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.padding,
      const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        kMobileTabBarHeight + AppSpacing.lg,
      ),
    );
    final safeArea = tester.widget<SafeArea>(find.byType(SafeArea).first);
    expect(safeArea.bottom, isFalse);
  });

  testWidgets('imported accounts and seed anchors offer removal', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    // Imported account: edit + remove.
    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_b')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
    final openMenuButton = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile_accounts_menu_button_b')),
    );
    expect(
      (openMenuButton.decoration as BoxDecoration).color,
      AppThemeData.light.colors.state.hover,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_account_menu_card'))),
      const Size(173, 173),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_account_menu_copy'))),
      const Size(165, 26),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Seed anchor with another account: edit + remove.
    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
  });

  testWidgets('the last remaining seed account resets the app on removal', (
    tester,
  ) async {
    final accountState = AccountState(
      accounts: [_account('a', 'Knight', isSeedAnchor: true)],
      activeAccountUuid: 'a',
    );
    final accountNotifier = _FakeAccountNotifier(accountState);
    final biometricNotifier = _FakeBiometricUnlockNotifier();
    final syncNotifier = _FakeWalletMutationSyncNotifier();

    await tester.pumpWidget(
      _app(
        accountState,
        accountNotifier: () => accountNotifier,
        biometricNotifier: () => biometricNotifier,
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    expect(find.text('Remove account'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_account_menu_remove')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('completely reset the Vizor app'),
      findsOneWidget,
    );
    expect(find.text('Reset Vizor'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_account_remove_confirm')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.resetCount, 1);
    expect(accountNotifier.removedUuid, isNull);
    expect(syncNotifier.pauseCount, 1);
    expect(syncNotifier.resumeCount, 0);
    expect(syncNotifier.clearCachedDbPathCount, 1);
    expect(biometricNotifier.disableCount, 1);
    expect(find.text('welcome route'), findsOneWidget);
  });

  testWidgets('row menu stays above the floating tab bar clearance', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            for (var i = 0; i < 12; i++) _account('other-$i', 'Other $i'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_other-11')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final menuRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_menu_card')),
    );
    expect(
      menuRect.bottom,
      lessThanOrEqualTo(852 - (kMobileTabBarHeight + AppSpacing.lg)),
    );
  });

  testWidgets('row menu barrier dismisses before the floating tab bar', (
    tester,
  ) async {
    final tabTaps = ValueNotifier(0);
    addTearDown(tabTaps.dispose);

    await tester.pumpWidget(
      _nestedShellApp(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
        tabTaps,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_b')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_account_menu_card')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('test_mobile_tab_bar')));
    await tester.pumpAndSettle();

    expect(tabTaps.value, 0);
    expect(
      find.byKey(const ValueKey('mobile_account_menu_card')),
      findsNothing,
    );
  });

  testWidgets('the edit sheet shows the avatar picker and validates the '
      'name', (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;

    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [_account('a', 'Knight', isSeedAnchor: true)],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit account'));
    await tester.pumpAndSettle();

    expect(find.text('Account name'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_edit_name_clear')),
      findsOneWidget,
    );
    final accountLabel = tester.widget<Text>(find.text('Account name'));
    expect(accountLabel.style?.fontWeight, FontWeight.w400);
    expect(accountLabel.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(accountLabel.style?.height, AppTypography.labelLarge.height);
    expect(
      accountLabel.style?.letterSpacing,
      AppTypography.labelLarge.letterSpacing,
    );
    final avatarRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_edit_avatar_image')),
    );
    final editBadgeFrameRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_edit_avatar_badge_frame')),
    );
    final editBadgeOuterRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_edit_avatar_badge_outer')),
    );
    final editBadgeFillRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_edit_avatar_badge_fill')),
    );
    expect(avatarRect.size, const Size(72, 72));
    expect(editBadgeFrameRect.size, const Size(24, 24));
    expect(editBadgeFrameRect.right - avatarRect.right, moreOrLessEquals(4));
    expect(editBadgeFrameRect.bottom - avatarRect.bottom, moreOrLessEquals(4));
    expect(editBadgeOuterRect.size, const Size(32, 32));
    expect(editBadgeFillRect.size, const Size(24, 24));
    expect(editBadgeOuterRect.right - avatarRect.right, moreOrLessEquals(8));
    expect(editBadgeOuterRect.bottom - avatarRect.bottom, moreOrLessEquals(8));
    final editIcon = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.editFilled,
      ),
    );
    expect(editIcon.size, moreOrLessEquals(11.572));
    expect(tester.getSize(find.byType(MobileTextField)).height, 60);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_account_edit_save')))
          .height,
      50,
    );
    expect(tester.getSize(find.byType(MobileSheetCancel)).height, 50);
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('mobile_account_edit_save')),
              )
              .dy -
          tester.getBottomLeft(find.byType(MobileTextField)).dy,
      moreOrLessEquals(48),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.qr,
      ),
      findsNothing,
    );
    final crossIcons = tester.widgetList<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.cross,
      ),
    );
    expect(crossIcons.map((icon) => icon.size), everyElement(20));

    await tester.enterText(
      find.byKey(const ValueKey('mobile_account_edit_name')),
      'Ranger',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_account_edit_name_clear')),
    );
    await tester.pump();
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_account_edit_name')),
    );
    expect(nameField.controller?.text, isEmpty);

    await tester.tap(find.byKey(const ValueKey('mobile_account_edit_avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Select profile picture'), findsOneWidget);
    final profilePictureTitle = tester.widget<Text>(
      find.text('Select profile picture'),
    );
    expect(profilePictureTitle.style?.fontWeight, FontWeight.w600);
    expect(
      profilePictureTitle.style?.fontSize,
      AppTypography.bodyLarge.fontSize,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_account_pfp_current_image')),
      ),
      const Size(72, 72),
    );
    for (final suffix in ['01', '02', '03', '04', '05', '06', '15']) {
      expect(
        find.byKey(ValueKey('mobile_account_pfp_option_pfp-$suffix')),
        findsOneWidget,
      );
    }
    final firstRowTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('mobile_account_pfp_option_pfp-01')),
        )
        .dy;
    final firstPfpRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_pfp_option_pfp-01')),
    );
    final secondPfpRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_pfp_option_pfp-02')),
    );
    final fifthPfpRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_pfp_option_pfp-05')),
    );
    expect(secondPfpRect.left - firstPfpRect.left, moreOrLessEquals(68.25));
    expect(fifthPfpRect.right - firstPfpRect.left, moreOrLessEquals(329));
    for (final suffix in ['02', '03', '04', '05']) {
      expect(
        tester
            .getTopLeft(
              find.byKey(ValueKey('mobile_account_pfp_option_pfp-$suffix')),
            )
            .dy,
        moreOrLessEquals(firstRowTop),
      );
    }
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_account_pfp_option_pfp-01')),
          )
          .height,
      56,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_account_pfp_option_pfp-01')),
          )
          .width,
      56,
    );
    final selectedBadgeRect = tester.getRect(
      find.byKey(const ValueKey('mobile_account_pfp_selected_badge_pfp-01')),
    );
    expect(selectedBadgeRect.size, const Size(24, 20));
    expect(selectedBadgeRect.right - firstPfpRect.right, moreOrLessEquals(4));
    expect(selectedBadgeRect.bottom - firstPfpRect.bottom, moreOrLessEquals(4));
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('mobile_account_pfp_option_pfp-06')),
          )
          .dy,
      moreOrLessEquals(firstRowTop + 72),
    );

    await tester.tap(find.byKey(const ValueKey('mobile_account_pfp_update')));
    await tester.pumpAndSettle();
    expect(find.text('Select profile picture'), findsNothing);

    // Empty name is rejected in place.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_account_edit_name')),
      '   ',
    );
    await tester.tap(find.byKey(const ValueKey('mobile_account_edit_save')));
    await tester.pump();
    expect(find.text('Account name'), findsOneWidget);
  });

  testWidgets('profile picture sheet wraps the grid on narrow phones', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_profilePictureSheetHarness());
    await tester.tap(find.text('open pfp'));
    await tester.pumpAndSettle();

    final firstRowTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('mobile_account_pfp_option_pfp-01')),
        )
        .dy;
    for (final suffix in ['02', '03', '04']) {
      expect(
        tester
            .getTopLeft(
              find.byKey(ValueKey('mobile_account_pfp_option_pfp-$suffix')),
            )
            .dy,
        moreOrLessEquals(firstRowTop),
      );
    }
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('mobile_account_pfp_option_pfp-05')),
          )
          .dy,
      moreOrLessEquals(firstRowTop + 72),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add account routes to the add-account flow', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [_account('a', 'Knight', isSeedAnchor: true)],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('mobile_accounts_add_account'));
    expect(button, findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('add account route'), findsOneWidget);
  });

  testWidgets('remove asks for confirmation with the design copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileModalScaffold), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
    expect(find.textContaining("can't be reverted"), findsOneWidget);
    final title = tester.widget<Text>(find.text('Remove account'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.height, 24 / 16);
    expect(title.style?.fontWeight, FontWeight.w600);
    final body = tester.widget<Text>(find.textContaining("can't be reverted"));
    expect(body.style?.fontSize, 14);
    expect(body.style?.height, 21 / 14);
    expect(body.style?.fontWeight, FontWeight.w400);
    final remove = tester.widget<Text>(find.text('Remove'));
    expect(remove.style?.fontSize, 14);
    expect(remove.style?.height, 16 / 14);
    expect(remove.style?.fontWeight, FontWeight.w500);
    final cancel = tester.widget<Text>(find.text('Cancel'));
    expect(cancel.style?.fontSize, 14);
    expect(cancel.style?.height, 16 / 14);
    expect(cancel.style?.fontWeight, FontWeight.w500);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be reverted"), findsNothing);
  });
}
