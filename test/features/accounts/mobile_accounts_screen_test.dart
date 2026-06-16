@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';
import 'package:zcash_wallet/src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/account_edit_sheets.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
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

Widget _app(AccountState accounts) {
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
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accounts)),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
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
  });

  testWidgets('imported accounts offer removal; the last seed anchor does '
      'not', (tester) async {
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
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Sole seed anchor: edit only.
    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsNothing);
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

    expect(find.text('Account label'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_edit_name_clear')),
      findsOneWidget,
    );
    final accountLabel = tester.widget<Text>(find.text('Account label'));
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
    expect(selectedBadgeRect.size, const Size(20, 20));
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
    expect(find.text('Account label'), findsOneWidget);
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

    expect(find.text('Remove account'), findsOneWidget);
    expect(find.textContaining("can't be reverted"), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be reverted"), findsNothing);
  });
}
