import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' show Colors, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/home/widgets/home_desktop_preview.dart';
import 'package:zcash_wallet/widgetbook/home_desktop_use_cases.dart';

void main() {
  testWidgets('home desktop default use case renders preview shell', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(tester, buildHomeDesktopDefaultUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeDesktopPreview), findsOneWidget);
    expect(
      tester.getSize(find.byType(HomeDesktopPreview)),
      HomeDesktopPreview.size,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Window'), findsNothing);
    expect(find.text('Help'), findsNothing);
    expect(find.text('Mon Jun 10  9:41 AM'), findsNothing);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_preview_balance_fiat_text')),
      findsOneWidget,
    );
    final colors = AppThemeData.light.colors;
    final fiatText = tester.widget<Text>(
      find.byKey(const ValueKey('home_preview_balance_fiat_text')),
    );
    expect(
      fiatText.style?.color,
      colors.text.homeCard.withValues(alpha: 0.80),
    );
    final shieldIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('home_preview_shielded_balance_icon')),
    );
    expect(shieldIcon.color, colors.text.homeCard);
    expect(
      _assetImageNames(tester),
      contains('assets/illustrations/home_default_background_light.png'),
    );
    final background = tester.widget<Image>(
      find.byKey(const ValueKey('home_preview_full_page_background')),
    );
    expect(background.alignment, Alignment.topCenter);
    expect(
      _assetImageNames(tester),
      isNot(contains('assets/illustrations/home_balance_card_bg_light.png')),
    );
    expect(_appIconSizes(tester, AppIcons.shieldKeyhole), contains(20));
    expect(
      find.byKey(const ValueKey('home_preview_transparent_balance_strip')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('home_preview_transparent_balance_strip')),
      ),
      const Size(396, 56),
    );
    expect(find.text('Transparent balance: 2.42 ZEC'), findsOneWidget);
    expect(find.text('Shield balance'), findsOneWidget);
    expect(
      _cursorForKey(
        tester,
        const ValueKey('home_preview_shield_balance_button'),
      ),
      SystemMouseCursors.click,
    );

    final seeAll = tester.widget<Text>(find.text('See all'));
    expect(seeAll.style?.fontSize, 14);
  });

  testWidgets('home desktop importing use case renders import state', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(tester, buildHomeDesktopImportingUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeDesktopPreview), findsOneWidget);
    expect(find.text('32%'), findsOneWidget);
    expect(find.text("We're importing\nyour wallet..."), findsOneWidget);
    expect(find.text('Importing...'), findsOneWidget);
    expect(
      _assetImageNames(tester),
      contains('assets/illustrations/home_importing_background_light.png'),
    );

    final percent = tester.widget<Text>(find.text('32%'));
    expect(percent.style?.fontFamily, 'Libre Caslon Text');
    expect(percent.style?.fontWeight, FontWeight.w400);
    expect(percent.style?.fontSize, 45);

    final headline = tester.widget<Text>(
      find.text("We're importing\nyour wallet..."),
    );
    expect(headline.style?.fontFamily, 'Libre Caslon Text');
    expect(headline.style?.fontWeight, FontWeight.w400);
    expect(headline.style?.fontSize, 28);
  });

  testWidgets('home desktop no-balance use case renders first receive CTA', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(tester, buildHomeDesktopNoBalanceUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeDesktopPreview), findsOneWidget);
    expect(find.text('Receive your first ZEC'), findsOneWidget);
    expect(find.text('No activity, yet...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_preview_transparent_balance_strip')),
      findsNothing,
    );

    final emptyTop = tester.getTopLeft(find.text('No activity, yet...')).dy;
    expect(emptyTop, greaterThan(390));
  });

  testWidgets('home desktop accounts use case renders account popover', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(tester, buildHomeDesktopAccountsUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeDesktopPreview), findsOneWidget);
    expect(find.text('My accounts'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Account 4'), findsOneWidget);

    expect(_appIconSizes(tester, AppIcons.keystone), contains(14));
    expect(_appIconSizes(tester, AppIcons.eye), everyElement(16));
    expect(_appIconSizes(tester, AppIcons.addNew), contains(16));
    expect(_appIconSizes(tester, AppIcons.copy), contains(16));

    expect(
      tester.getSize(find.byKey(const ValueKey('home_accounts_popover'))),
      const Size(221, 254),
    );
    final popoverDecoration = _boxDecorationByKey(
      tester,
      const ValueKey('home_accounts_popover'),
    );
    final popoverBorder = popoverDecoration.border as Border;
    expect(popoverBorder.top.color, AppColors.light.border.subtle);
    expect(popoverBorder.top.width, 1);
    final popoverTop =
        tester
            .getTopLeft(find.byKey(const ValueKey('home_accounts_popover')))
            .dy;
    final popoverBottom =
        tester
            .getBottomLeft(find.byKey(const ValueKey('home_accounts_popover')))
            .dy;
    final homeTop = tester.getTopLeft(find.text('Home')).dy;
    expect(homeTop, greaterThan(popoverTop));
    expect(homeTop, lessThan(popoverBottom));
    expect(
      tester.getSize(find.byKey(const ValueKey('home_accounts_list'))),
      const Size(205, 161),
    );
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('home_accounts_scrollbar')),
    );
    expect(scrollbar.controller, isNotNull);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.thickness, 6);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home_account_row_1'))).dy -
          tester
              .getTopLeft(find.byKey(const ValueKey('home_account_row_0')))
              .dy,
      44,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home_account_row_0'))),
      const Size(187, 40),
    );
    expect(find.byKey(const ValueKey('home_accounts_divider_0')), findsNothing);
    expect(
      find.byKey(const ValueKey('home_accounts_actions_divider')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('home_accounts_actions_divider')),
      ),
      const Size(205, 1),
    );

    final listBottom =
        tester
            .getBottomLeft(find.byKey(const ValueKey('home_accounts_list')))
            .dy;
    final row4Top =
        tester.getTopLeft(find.byKey(const ValueKey('home_account_row_3'))).dy;
    expect(row4Top, lessThan(listBottom));
    expect(row4Top + 40, greaterThan(listBottom));

    expect(
      tester.getSize(find.byKey(const ValueKey('home_accounts_buttons'))),
      const Size(205, 36),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home_accounts_manage'))),
      const Size(153, 36),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home_accounts_add'))),
      const Size(48, 32),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home_accounts_add'))).dx -
          tester
              .getTopRight(find.byKey(const ValueKey('home_accounts_manage')))
              .dx,
      4,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home_accounts_add'))).dy -
          tester
              .getTopLeft(find.byKey(const ValueKey('home_accounts_buttons')))
              .dy,
      2,
    );
    expect(_cursorForText(tester, 'Account 1'), SystemMouseCursors.click);
    expect(
      _cursorForKey(tester, const ValueKey('home_accounts_manage')),
      SystemMouseCursors.click,
    );
    expect(
      _cursorForKey(tester, const ValueKey('home_accounts_add')),
      SystemMouseCursors.click,
    );
  });

  testWidgets(
    'home desktop accounts scroll use case scrolls long account list',
    (tester) async {
      await _pumpHomeDesktopUseCase(
        tester,
        buildHomeDesktopAccountsScrollUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Account 8'), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('home_accounts_list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account 8'), findsOneWidget);
      final listBottom =
          tester
              .getBottomLeft(find.byKey(const ValueKey('home_accounts_list')))
              .dy;
      final lastRowBottom =
          tester
              .getBottomLeft(find.byKey(const ValueKey('home_account_row_7')))
              .dy;
      expect(
        listBottom - lastRowBottom,
        moreOrLessEquals(AppSpacing.xs, epsilon: 0.1),
      );
    },
  );

  testWidgets('home desktop notice use cases render recovery messages', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(
      tester,
      buildHomeDesktopPasswordRecoveryNoticeUseCase,
    );

    expect(
      find.byKey(const ValueKey('home_preview_notice_card')),
      findsOneWidget,
    );
    expect(
      find.text(
        "We couldn't verify the previous password change. Try again or restart Vizor.",
      ),
      findsOneWidget,
    );

    await _pumpHomeDesktopUseCase(
      tester,
      buildHomeDesktopShieldQueuedNoticeUseCase,
    );

    expect(
      find.byKey(const ValueKey('home_preview_notice_card')),
      findsOneWidget,
    );
    expect(
      find.text('Shielding queued for retry. Check Activity.'),
      findsOneWidget,
    );

    await _pumpHomeDesktopUseCase(
      tester,
      buildHomeDesktopSyncFailureNoticeUseCase,
    );

    expect(
      find.byKey(const ValueKey('home_preview_notice_card')),
      findsOneWidget,
    );
    expect(find.text('Network connection lost.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('home desktop activity rows use figma-sized icons and weights', (
    tester,
  ) async {
    await _pumpHomeDesktopUseCase(tester, buildHomeDesktopKeystoneUseCase);

    expect(tester.takeException(), isNull);
    expect(_appIconSizes(tester, AppIcons.plane), contains(16));
    expect(_appIconSizes(tester, AppIcons.arrowDownCircle), contains(16));
    expect(_appIconSizes(tester, AppIcons.swapArrows), contains(16));
    expect(_appIconSizes(tester, AppIcons.shieldKeyholeOutline), contains(16));
    expect(find.byType(CustomPaint), findsWidgets);

    final title = tester.widget<Text>(find.text('Recent activity'));
    expect(title.style?.fontFamily, 'Geist');
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w600);

    final seeAll = tester.widget<Text>(find.text('See all'));
    expect(seeAll.style?.fontWeight, FontWeight.w400);

    const sentRowKey = ValueKey(
      'home_preview_activity_row_Sent_Transparent_-14.123 ZEC_false_true',
    );
    expect(
      _animatedBoxDecorationUnderKey(tester, sentRowKey).color,
      Colors.transparent,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byKey(sentRowKey)));
    await tester.pumpAndSettle();

    expect(
      _animatedBoxDecorationUnderKey(tester, sentRowKey).color,
      AppThemeData.light.colors.state.hoverOpacity,
    );
  });

  testWidgets('home desktop account menu switches account and emits actions', (
    tester,
  ) async {
    var selectedAccount = -1;
    var manageTapped = false;
    var addTapped = false;

    await _pumpHomeDesktopWidget(
      tester,
      HomeDesktopPreview(
        state: HomeDesktopPreviewState.accounts,
        onAccountSelected: (index) => selectedAccount = index,
        onManageAccounts: () => manageTapped = true,
        onAddAccount: () => addTapped = true,
      ),
    );

    await tester.tap(find.text('Account 3'));
    await tester.pump();

    expect(selectedAccount, 2);
    expect(find.text('My accounts'), findsNothing);
    expect(find.text('Account 3'), findsOneWidget);

    await tester.tap(find.text('Account 3'));
    await tester.pump();
    await tester.tap(find.text('Manage'));
    await tester.pump();
    expect(manageTapped, isTrue);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.addNew,
      ),
    );
    await tester.pump();
    expect(addTapped, isTrue);
  });
}

Future<void> _pumpHomeDesktopUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = HomeDesktopPreview.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpHomeDesktopWidget(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = HomeDesktopPreview.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: AppTheme(data: AppThemeData.light, child: child)),
  );
  await tester.pump();
}

List<String> _assetImageNames(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .whereType<AssetImage>()
      .map((image) => image.assetName)
      .toList();
}

BoxDecoration _boxDecorationByKey(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return container.decoration! as BoxDecoration;
}

BoxDecoration _animatedBoxDecorationUnderKey(WidgetTester tester, Key key) {
  final animatedContainer = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return animatedContainer.decoration! as BoxDecoration;
}

MouseCursor _cursorForText(WidgetTester tester, String text) {
  final mouseRegion = tester.widget<MouseRegion>(
    find
        .ancestor(of: find.text(text), matching: find.byType(MouseRegion))
        .first,
  );
  return mouseRegion.cursor;
}

MouseCursor _cursorForKey(WidgetTester tester, Key key) {
  final mouseRegion = tester.widget<MouseRegion>(
    find
        .ancestor(of: find.byKey(key), matching: find.byType(MouseRegion))
        .first,
  );
  return mouseRegion.cursor;
}

List<double> _appIconSizes(WidgetTester tester, String name) {
  return tester
      .widgetList<AppIcon>(find.byType(AppIcon))
      .where((icon) => icon.name == name)
      .map((icon) => icon.size)
      .toList();
}
