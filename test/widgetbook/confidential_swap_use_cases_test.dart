import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/settings/widgets/network_privacy_control.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_confidential_ui.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';
import '../figma_compare/figma_compare_font_loader.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

final _settings = find.byKey(const ValueKey('confidential_preview_settings'));
final _switch = find.byKey(const ValueKey('swap_confidential_switch'));
final _cancel = find.byKey(const ValueKey('swap_slippage_cancel_button'));
final _update = find.byKey(const ValueKey('swap_slippage_update_button'));

/// The composer shows the mode only as the mark on the settings button.
bool _confidential(WidgetTester tester) => find
    .descendant(of: _settings, matching: find.byType(SwapConfidentialIcon))
    .evaluate()
    .isNotEmpty;

bool _switchOn(WidgetTester tester) =>
    tester.widget<PrivacyToggle>(find.byType(PrivacyToggle)).enabled;

void main() {
  setUpAll(loadFigmaCompareFonts);
  test('new text and toggle pairs meet contrast in both themes', () {
    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      final colors = theme.colors;
      // ground: the unfilled receive card behind the status and mode text.
      for (final bg in [
        colors.background.base,
        colors.background.raised,
        colors.background.ground,
      ]) {
        final a = colors.text.secondary.computeLuminance();
        final b = bg.computeLuminance();
        final ratio =
            (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
      final a = colors.text.inverse.computeLuminance();
      final b = colors.background.inverse.computeLuminance();
      final ratio =
          (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
      expect(ratio, greaterThanOrEqualTo(3));
    }
  });

  testWidgets('confidential is set in settings and marks the settings button', (
    tester,
  ) async {
    await _pump(tester, buildConfidentialSwapStandardUseCase);
    expect(_confidential(tester), isFalse);
    await tester.tap(_settings);
    await tester.pumpAndSettle();
    expect(find.text('Swap settings'), findsOneWidget);
    // Confidential comes first, then slippage, in one modal.
    final setting = tester.getRect(
      find.byKey(const ValueKey('swap_confidential_setting')),
    );
    expect(
      setting.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Slippage')).top),
    );
    expect(
      find.textContaining("can't be matched on NEAR Intents"),
      findsOneWidget,
    );
    expect(_switchOn(tester), isFalse);
    // Nothing applies until Update, and Cancel drops the choice.
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(_switchOn(tester), isTrue);
    expect(_confidential(tester), isFalse);
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(find.text('Swap settings'), findsNothing);
    expect(_confidential(tester), isFalse);
    await tester.tap(_settings);
    await tester.pumpAndSettle();
    expect(_switchOn(tester), isFalse);
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(find.text('Swap settings'), findsNothing);
    expect(_confidential(tester), isTrue);
    expect(find.textContaining('112.00'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('confidential_preview_review')));
    await tester.pumpAndSettle();
    // Review marks the flow with the hidden route, as status does.
    expect(
      find.byKey(const ValueKey('swap_confidential_route')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mode changes and quote failures keep the ticket and CTA in place',
    (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(393, 640),
        const Size(393, 852),
        const Size(1080, 720),
      ]) {
        await _pump(
          tester,
          buildConfidentialSwapStandardUseCase,
          width: size.width,
          height: size.height,
        );
        final ticket = find.byKey(const ValueKey('swap_compact_ticket'));
        final beforeTicket = tester.getRect(ticket);
        final before = tester.getRect(
          find.byKey(const ValueKey('confidential_preview_review')),
        );
        final beforeScroll = _verticalScrollExtents(tester);
        for (final builder in [
          buildConfidentialSwapStandardUseCase,
          buildConfidentialSwapReadyUseCase,
          buildConfidentialSwapLoadingUseCase,
          buildConfidentialSwapLiquidityUseCase,
          buildConfidentialSwapNoLiquidityUseCase,
          buildConfidentialSwapMinimumUseCase,
          buildConfidentialSwapNetworkUseCase,
          buildConfidentialSwapUnknownUseCase,
          buildConfidentialSwapDeniedUseCase,
        ]) {
          await _pump(tester, builder, width: size.width, height: size.height);
          final action = find.byWidgetPredicate(
            (widget) =>
                widget.key == const ValueKey('confidential_preview_review') ||
                widget.key == const ValueKey('swap_quote_recovery'),
          );
          expect(
            tester.getRect(ticket),
            beforeTicket,
            reason: 'Ticket moved at $size',
          );
          final status = find.byKey(const ValueKey('swap_quote_feedback'));
          // Desktop fits the status into the attribution band. Mobile inserts
          // it above the action row, which moves down by exactly that block.
          final shift = _mobile && status.evaluate().isNotEmpty
              ? tester.getSize(status).height +
                    AppSpacing.s +
                    AppSpacing.xs -
                    AppSpacing.md
              : 0.0;
          // The mark can widen the mobile settings pill beside the action,
          // so only the action's vertical position and right edge are fixed.
          final rect = tester.getRect(action);
          final expected = before.shift(Offset(0, shift));
          expect(rect.top, expected.top, reason: 'Action moved at $size');
          expect(rect.bottom, expected.bottom, reason: 'Action moved at $size');
          expect(rect.right, expected.right, reason: 'Action moved at $size');
          final scroll = _verticalScrollExtents(tester);
          expect(scroll.length, beforeScroll.length);
          for (var i = 0; i < scroll.length; i++) {
            expect(
              scroll[i],
              inInclusiveRange(beforeScroll[i], beforeScroll[i] + shift),
              reason: 'Page grew at $size',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('turning confidential on flips the seam once settings close', (
    tester,
  ) async {
    final seamMark = find.descendant(
      of: find.byKey(const ValueKey('swap_compact_ticket')),
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.incognito,
      ),
    );
    Future<void> turnOn({required bool animate}) async {
      await _pump(
        tester,
        buildConfidentialSwapStandardUseCase,
        animate: animate,
      );
      await tester.tap(_settings);
      await tester.pumpAndSettle();
      await tester.tap(_switch);
      await tester.pump(const Duration(milliseconds: 300));
      // Held while the settings cover the ticket.
      expect(seamMark, findsNothing);
      await tester.tap(_update);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await turnOn(animate: true);
    expect(seamMark, findsOneWidget);
    await tester.pumpAndSettle();
    expect(seamMark, findsNothing);
    expect(_confidential(tester), isTrue);
    // Turning it off again plays nothing, nor does off-then-on, which leaves
    // nothing to update.
    for (final flips in [1, 2]) {
      await tester.tap(_settings);
      await tester.pumpAndSettle();
      for (var i = 0; i < flips; i++) {
        await tester.tap(_switch);
        await tester.pumpAndSettle();
      }
      await tester.tap(flips == 1 ? _update : _cancel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(seamMark, findsNothing, reason: '$flips flips');
    }

    // Reduced motion only changes the state.
    await turnOn(animate: false);
    expect(seamMark, findsNothing);
    expect(_confidential(tester), isTrue);
  });

  testWidgets('the settings switch reads as a toggle', (tester) async {
    await _pump(tester, buildConfidentialSwapReadyUseCase);
    expect(
      tester.getSemantics(_settings),
      isSemantics(label: 'Slippage settings, 0.5%, confidential'),
    );
    await tester.tap(_settings);
    await tester.pumpAndSettle();
    final toggle = find.byType(PrivacyToggle);
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        label: 'Confidential',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    final semantics = tester.getSemantics(toggle);
    tester
        .renderObject<RenderBox>(_switch)
        .owner!
        .semanticsOwner!
        .performAction(semantics.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(_switchOn(tester), isFalse);
  });

  testWidgets(
    'liquidity feedback sits above the CTA and requests a confidential quote',
    (tester) async {
      await _pump(tester, buildConfidentialSwapLiquidityUseCase);
      final status = find.text('No quote for this amount');
      expect(status, findsOneWidget);
      expect(tester.getSemantics(status), isSemantics(isLiveRegion: true));
      // Feedback belongs between the ticket and the recovery action.
      final ticket = tester.getRect(
        find.byKey(const ValueKey('swap_compact_ticket')),
      );
      expect(tester.getRect(status).top, greaterThanOrEqualTo(ticket.bottom));
      final action = tester.getRect(
        find.byKey(const ValueKey('swap_quote_recovery')),
      );
      expect(tester.getRect(status).bottom, lessThanOrEqualTo(action.top));
      expect(
        find.byKey(const ValueKey('swap_receive_amount_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_quote_error_message')),
        findsNothing,
      );
      expect(find.text(r'$0'), findsNothing);
      expect(find.textContaining('1125'), findsNothing);
      expect(find.textContaining('1120'), findsNothing);
      expect(find.textContaining('0.00'), findsNothing);
      expect(_confidential(tester), isFalse);
      expect(find.text('Get confidential quote').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('swap_quote_recovery')));
      await tester.pumpAndSettle();
      expect(status, findsNothing);
      expect(_confidential(tester), isTrue);
      expect(
        find.byKey(const ValueKey('confidential_preview_review')).hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('other failures state their own cause and keep the mode', (
    tester,
  ) async {
    for (final (builder, status, recovery, confidential) in [
      (
        buildConfidentialSwapNetworkUseCase,
        'Unable to connect',
        'Try again',
        false,
      ),
      (
        buildConfidentialSwapUnknownUseCase,
        'Quote unavailable',
        'Try again',
        false,
      ),
      (
        buildConfidentialSwapDeniedUseCase,
        'Confidential quotes unavailable',
        'Try again',
        true,
      ),
      // Same gap as standard liquidity, but the confidential mode is never
      // downgraded or re-offered: only the plain retry remains.
      (
        buildConfidentialSwapNoLiquidityUseCase,
        'No confidential quote for this amount',
        'Try again',
        true,
      ),
      (
        buildConfidentialSwapMinimumUseCase,
        'Amount below minimum',
        'Edit amount',
        false,
      ),
    ]) {
      await _pump(tester, builder);
      expect(_confidential(tester), confidential, reason: status);
      expect(find.text(status), findsOneWidget);
      expect(find.text(recovery), findsOneWidget);
      expect(find.text('Get confidential quote'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('swap_quote_recovery')));
      await tester.pumpAndSettle();
      expect(_confidential(tester), confidential, reason: status);
    }
  });

  testWidgets('minimum recovery focuses amount', (tester) async {
    await _pump(tester, buildConfidentialSwapMinimumUseCase);
    await tester.tap(find.byKey(const ValueKey('swap_quote_recovery')));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Confidential preview amount',
    );
  });

  testWidgets('keyboard flips the setting inside the modal', (tester) async {
    await _pump(tester, buildConfidentialSwapStandardUseCase);
    await tester.tap(_settings);
    await tester.pumpAndSettle();
    Focus.of(tester.element(_switch)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_switchOn(tester), isTrue);
    // The flip waits for Update, like a slippage choice.
    expect(_confidential(tester), isFalse);
  });

  testWidgets('loading prevents mode changes and review', (tester) async {
    await _pump(tester, buildConfidentialSwapLoadingUseCase);
    await tester.tap(_settings);
    await tester.tap(find.byKey(const ValueKey('confidential_preview_review')));
    await tester.pumpAndSettle();
    expect(find.text('Swap settings'), findsNothing);
    expect(_confidential(tester), isTrue);
    expect(find.text('Confirm & swap'), findsNothing);
  });

  testWidgets('standard review keeps the plain flow arrow', (tester) async {
    await _pump(tester, buildConfidentialSwapStandardReviewUseCase);
    expect(find.text('Confirm & swap'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_confidential_route')), findsNothing);
  });

  testWidgets('pending and completed details retain recorded mode', (
    tester,
  ) async {
    for (final builder in [
      buildConfidentialSwapStatusUseCase,
      buildConfidentialSwapCompletedUseCase,
    ]) {
      await _pump(tester, builder);
      // The recorded mode replaces the flow arrow instead of adding a row.
      expect(
        find.byKey(const ValueKey('swap_confidential_route')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the route flows only while the swap is in progress', (
    tester,
  ) async {
    final flowing = find.byKey(
      const ValueKey('swap_confidential_route_flowing'),
    );
    await _pump(
      tester,
      buildConfidentialSwapStatusUseCase,
      animate: true,
      settle: false,
    );
    expect(flowing, findsOneWidget);
    await _pump(tester, buildConfidentialSwapCompletedUseCase, animate: true);
    expect(flowing, findsNothing);
    // Review has not started anything yet.
    await _pump(tester, buildConfidentialSwapReviewUseCase, animate: true);
    expect(flowing, findsNothing);
    // Reduced motion keeps the in-progress route still.
    await _pump(tester, buildConfidentialSwapStatusUseCase);
    expect(flowing, findsNothing);
    expect(
      find.byKey(const ValueKey('swap_confidential_route')),
      findsOneWidget,
    );
  });

  testWidgets('slippage settings remain independent and restore focus', (
    tester,
  ) async {
    await _pump(tester, buildConfidentialSwapReadyUseCase);
    await tester.tap(
      find.byKey(const ValueKey('confidential_preview_settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Slippage'), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey(
          _mobile ? 'mobile_swap_slippage_plus' : 'swap_slippage_100bps',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('swap_slippage_cancel_button')));
    await tester.pumpAndSettle();
    expect(find.text('0.5%'), findsOneWidget);
    expect(_confidential(tester), isTrue);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Confidential preview settings',
    );
  });

  testWidgets('invalid custom slippage retains recovery copy', (tester) async {
    await _pump(tester, buildConfidentialSwapSettingsUseCase);
    // Desktop types into its custom card; mobile into the stepper value.
    await tester.enterText(
      find.byKey(
        ValueKey(
          _mobile ? 'mobile_swap_slippage_value' : 'swap_slippage_custom_input',
        ),
      ),
      '15',
    );
    await tester.pump();
    if (!_mobile) {
      await tester.tap(
        find.byKey(const ValueKey('swap_slippage_update_button')),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('Slippage must be 0.1 - 5%'), findsOneWidget);
  });

  testWidgets(
    'confidential setting stays readable at 320px with 200 percent text',
    (tester) async {
      for (final theme in [AppThemeData.light, AppThemeData.dark]) {
        for (final confidential in [false, true]) {
          await _pump(
            tester,
            (_) => Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: SwapConfidentialSetting(
                confidential: confidential,
                onChanged: (_) {},
              ),
            ),
            width: 320,
            scale: 2,
            theme: theme,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}

List<double> _verticalScrollExtents(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .where((scroll) => scroll.position.axis == Axis.vertical)
    .map((scroll) => scroll.position.maxScrollExtent)
    .toList();

Future<void> _pump(
  WidgetTester tester,
  WidgetBuilder builder, {
  double width = 1080,
  double scale = 1,
  double height = 852,
  AppThemeData? theme,
  bool animate = false,
  bool settle = true,
}) async {
  // Give each fixture a fresh local State, as Widgetbook does when changing cases.
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AppTheme(
        data: theme ?? AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: !animate,
          ),
          child: child!,
        ),
      ),
      home: Scaffold(body: Builder(builder: builder)),
    ),
  );
  // An in-progress route repeats, so it never settles.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
