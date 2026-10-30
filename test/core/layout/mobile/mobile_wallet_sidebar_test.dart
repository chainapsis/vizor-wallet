@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_navigation_scope.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_wallet_sidebar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sidebar_surface.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sync_status.dart';

const status = SyncStatusLabel(
  kind: SyncStatusKind.syncing,
  label: '4% Syncing...',
  semanticsLabel: '4% Syncing',
);
Widget harness(Widget child, {double scale = 1, AppThemeData? theme}) =>
    MaterialApp(
      // Like MaterialApp.router.builder in production: the sidebar is a sibling
      // of the router, outside its Scaffold/Material default text styles.
      builder: (context, navigator) => AppTheme(
        data: theme ?? AppThemeData.light,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Stack(
            children: [
              navigator!,
              Center(child: child),
            ],
          ),
        ),
      ),
      home: const Scaffold(),
    );

void main() {
  for (final dark in [false, true]) {
    for (final enabled in [false, true]) {
      for (final kind in SyncStatusKind.values) {
        testWidgets('sidebar resets inherited text decoration '
            '(dark=$dark, enabled=$enabled, sync=$kind)', (tester) async {
          final theme = dark ? AppThemeData.dark : AppThemeData.light;
          final label = switch (kind) {
            SyncStatusKind.syncing => '4% Syncing...',
            SyncStatusKind.synced => 'Vizor is synced',
            SyncStatusKind.failed => 'Syncing failed',
          };
          await tester.pumpWidget(
            harness(
              SizedBox(
                width: 200,
                height: 600,
                child: MobileWalletSidebar(
                  accountName: 'Account probe',
                  avatar: const SizedBox(width: 40, height: 40),
                  status: SyncStatusLabel(
                    kind: kind,
                    label: label,
                    semanticsLabel: label,
                  ),
                  currentPath: '/home',
                  swapEnabled: true,
                  onSelect: enabled ? (_) {} : null,
                  onAccountTap: enabled ? () {} : null,
                ),
              ),
              theme: theme,
            ),
          );
          TextStyle effectiveStyle(String label) =>
              (tester
                          .widget<RichText>(
                            find.descendant(
                              of: find.text(label),
                              matching: find.byType(RichText),
                            ),
                          )
                          .text
                      as TextSpan)
                  .style!;
          for (final text in [
            'Account probe',
            'Home',
            'Swap',
            'Activity',
            'Settings',
            label,
          ]) {
            final style = effectiveStyle(text);
            expect(style.decoration, TextDecoration.none, reason: text);
            final typography = text == label
                ? AppTypography.labelMedium
                : AppTypography.bodyMediumStrong;
            expect(style.fontFamily, typography.fontFamily, reason: text);
            expect(style.fontSize, typography.fontSize, reason: text);
            expect(style.fontWeight, typography.fontWeight, reason: text);
          }
          final syncColor = switch (kind) {
            SyncStatusKind.syncing => theme.colors.sync.textSyncing,
            SyncStatusKind.synced => theme.colors.sync.text,
            SyncStatusKind.failed => theme.colors.sync.textError,
          };
          expect(effectiveStyle(label).color, syncColor);
          if (enabled) {
            expect(
              effectiveStyle('Home').color,
              theme.colors.navPanel.activeIcon,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    testWidgets(
      'full lock veils the panel and preserves sync and disabled input (${theme == AppThemeData.dark ? 'dark' : 'light'})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final visits = <String>[];
          var accounts = 0;
          Widget subject({
            bool navigation = true,
            bool account = true,
            bool pending = false,
            SyncStatusLabel sync = status,
          }) => harness(
            SizedBox(
              width: 256,
              height: 600,
              child: MobileWalletSidebar(
                accountName: 'Account probe',
                avatar: const SizedBox.square(dimension: 40),
                status: sync,
                currentPath: '/home',
                swapEnabled: true,
                onSelect: navigation ? visits.add : null,
                onAccountTap: account ? () => accounts++ : null,
                inputBlocked: pending,
              ),
            ),
            theme: theme,
          );
          List<Color?> fills() => tester
              .widgetList<AnimatedContainer>(
                find.descendant(
                  of: find.byType(MobileWalletSidebar),
                  matching: find.byType(AnimatedContainer),
                ),
              )
              .map((w) => (w.decoration as ShapeDecoration).color)
              .toList();
          await tester.pumpWidget(subject());
          final restingFills = fills();
          final syncState = tester.state(find.byType(MobileSyncStatus));
          final syncRect = tester.getRect(find.byType(MobileSyncStatus));
          final syncColors = tester.widget<MobileSyncStatus>(
            find.byType(MobileSyncStatus),
          );
          final focus = Focus.of(tester.element(find.text('Settings')));
          focus.requestFocus();
          await tester.pump();
          await tester.pumpWidget(subject(navigation: false, account: false));
          expect(fills(), restingFills); // No individual disabled pills.
          expect(focus.hasFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.tap(find.text('Settings'));
          await tester.tap(find.text('Account probe'));
          expect(visits, isEmpty);
          expect(accounts, 0);
          for (final label in [
            'Account probe',
            'Home',
            'Swap',
            'Activity',
            'Settings',
          ]) {
            expect(
              tester
                  .getSemantics(find.text(label))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
          }
          expect(tester.state(find.byType(MobileSyncStatus)), same(syncState));
          expect(tester.getRect(find.byType(MobileSyncStatus)), syncRect);
          final sync = tester.widget<MobileSyncStatus>(
            find.byType(MobileSyncStatus),
          );
          expect(sync.baseColor, syncColors.baseColor);
          expect(sync.indicatorColor, syncColors.indicatorColor);
          expect(sync.animated, syncColors.animated);
          final panel = tester.getRect(find.byType(MobileSidebarSurface));
          final top = tester.getRect(
            find.byKey(const ValueKey('mobile_sidebar_controls_veil')),
          );
          final bottom = tester.getRect(
            find.byKey(const ValueKey('mobile_sidebar_footer_veil')),
          );
          expect(top.topLeft, panel.topLeft);
          expect(top.width, panel.width);
          expect(bottom.width, panel.width);
          expect(top.bottom, bottom.top);
          expect(bottom.bottomRight, panel.bottomRight);
          final footerStack = tester.widget<Stack>(
            find
                .ancestor(
                  of: find.byKey(
                    const ValueKey('mobile_sidebar_sync_foreground'),
                  ),
                  matching: find.byType(Stack),
                )
                .first,
          );
          expect(
            footerStack.children.last.key,
            const ValueKey('mobile_sidebar_sync_foreground'),
          );
          expect(
            footerStack.clipBehavior,
            Clip.none,
          ); // Preserve the upper glow.
          await tester.pumpWidget(
            subject(
              navigation: false,
              account: false,
              sync: const SyncStatusLabel(
                kind: SyncStatusKind.failed,
                label: 'Syncing failed',
                semanticsLabel: 'Syncing failed',
              ),
            ),
          );
          expect(find.text('Syncing failed'), findsOneWidget);
          expect(
            tester
                .widget<MobileSyncStatus>(find.byType(MobileSyncStatus))
                .liveRegion,
            isTrue,
          );
          expect(tester.state(find.byType(MobileSyncStatus)), same(syncState));
          await tester.pumpWidget(subject(account: false));
          expect(
            find.byKey(const ValueKey('mobile_sidebar_controls_veil')),
            findsNothing,
          );
          expect(fills().first, theme.colors.button.disabled.bg);
          await tester.tap(find.text('Settings'));
          expect(visits, ['/settings']);
          await tester.pumpWidget(subject(pending: true));
          expect(
            find.byKey(const ValueKey('mobile_sidebar_controls_veil')),
            findsNothing,
          );
          await tester.pumpWidget(subject());
          await tester.tap(find.text('Account probe'));
          expect(accounts, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'locked short sidebar still scrolls to the readable sync footer',
    (tester) async {
      await tester.pumpWidget(
        harness(
          SizedBox(
            width: 200,
            height: 260,
            child: MobileWalletSidebar(
              accountName: 'Account probe',
              avatar: const SizedBox.square(dimension: 40),
              status: status,
              currentPath: '/home',
              swapEnabled: true,
              onSelect: null,
              onAccountTap: null,
            ),
          ),
          scale: 2,
        ),
      );
      await tester.ensureVisible(find.text('4% Syncing...'));
      await tester.pump();
      final sync = tester.getRect(find.byType(MobileSyncStatus));
      final panel = tester.getRect(find.byType(MobileSidebarSurface));
      expect(sync.bottom, lessThanOrEqualTo(panel.bottom));
      expect(sync.top, greaterThanOrEqualTo(panel.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'temporary lock keeps paint and labels while blocking all input',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final visits = <String>[];
        var accounts = 0;
        Widget sidebar({required bool blocked}) => SizedBox(
          width: 256,
          height: 600,
          child: MobileWalletSidebar(
            accountName: 'Account probe',
            avatar: const SizedBox(width: 40, height: 40),
            status: status,
            currentPath: '/home',
            swapEnabled: true,
            inputBlocked: blocked,
            onSelect: visits.add,
            onAccountTap: () => accounts++,
          ),
        );
        Color? textColor(String text) =>
            (tester
                        .widget<RichText>(
                          find.descendant(
                            of: find.text(text),
                            matching: find.byType(RichText),
                          ),
                        )
                        .text
                    as TextSpan)
                .style!
                .color;
        await tester.pumpWidget(harness(sidebar(blocked: false)));
        final labels = [
          'Account probe',
          'Home',
          'Swap',
          'Activity',
          'Settings',
        ];
        final colors = [for (final label in labels) textColor(label)];
        final settingsNode = Focus.of(tester.element(find.text('Settings')));
        settingsNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(visits, ['/settings']);
        expect(
          tester
              .getSemantics(find.text('Settings'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );

        await tester.pumpWidget(harness(sidebar(blocked: true)));
        expect(settingsNode.hasFocus, isFalse);
        settingsNode.requestFocus();
        await tester.pump();
        expect(settingsNode.hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.tap(find.text('Settings'), warnIfMissed: false);
        await tester.tap(find.text('Account probe'), warnIfMissed: false);
        expect(visits, ['/settings']);
        expect(accounts, 0);
        for (var i = 0; i < labels.length; i++) {
          expect(textColor(labels[i]), colors[i]);
          expect(find.text(labels[i]), findsOneWidget);
          expect(
            tester
                .getSemantics(find.text(labels[i]))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
        }

        await tester.pumpWidget(harness(sidebar(blocked: false)));
        await tester.tap(find.text('Settings'));
        await tester.tap(find.text('Account probe'));
        expect(visits, ['/settings', '/settings']);
        expect(accounts, 1);
        expect(
          tester
              .getSemantics(find.text('Settings'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'sidebar shows mobile destinations and sync, respects flag and disabled state',
    (tester) async {
      final visits = <String>[];
      Widget sidebar({bool enabled = true}) => SizedBox(
        width: 200,
        height: 600,
        child: MobileWalletSidebar(
          accountName: 'Windborne Trailguard',
          avatar: const SizedBox(width: 40, height: 40),
          status: status,
          currentPath: '/activity',
          swapEnabled: false,
          onAccountTap: enabled ? () {} : null,
          onSelect: enabled ? visits.add : null,
        ),
      );
      await tester.pumpWidget(harness(sidebar()));
      expect(find.text('Swap'), findsNothing);
      expect(find.text('4% Syncing...'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      expect(visits, ['/settings']);
      await tester.pumpWidget(harness(sidebar(enabled: false)));
      await tester.tap(find.text('Home'));
      expect(visits, ['/settings']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'short sidebar scrolls all controls at large accessibility text size',
    (tester) async {
      await tester.pumpWidget(
        harness(
          SizedBox(
            width: 200,
            height: 260,
            child: MobileWalletSidebar(
              accountName: 'A long account name that should wrap',
              avatar: const SizedBox(width: 40, height: 40),
              status: status,
              currentPath: '/home',
              swapEnabled: true,
              onAccountTap: () {},
              onSelect: (_) {},
            ),
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('4% Syncing...'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'side tabs retain upright icons and every destination scrolls into view',
    (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        harness(
          SizedBox(
            width: 492,
            height: 720,
            child: MobileNavigationScope(
              mode: MobileNavigationMode.systemSideTabs,
              navigation: MobileBranchNavigation(),
              railRect: const Rect.fromLTWH(416, 200, 64, 100),
              child: AppMobileShell(
                body: const SizedBox.expand(),
                tabBar: AppMobileTabBar(
                  axis: Axis.vertical,
                  items: const [
                    AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
                    AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
                  ],
                  currentIndex: 0,
                  onSelect: selected.add,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.bySemanticsLabel('Settings'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Settings'));
      expect(selected, [1]);
      expect(tester.takeException(), isNull);
    },
  );
}
