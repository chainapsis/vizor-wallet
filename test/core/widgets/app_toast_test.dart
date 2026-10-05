import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  testWidgets('AppToast uses inverse neutral tokens in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: Center(child: AppToast(message: 'Address copied')),
      ),
    );

    final toastFinder = find.byType(AppToast);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: toastFinder,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, AppThemeData.light.colors.background.inverse);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.small));

    final padding = tester.widget<Padding>(
      find.descendant(of: toastFinder, matching: find.byType(Padding)),
    );
    expect(
      padding.padding.resolve(TextDirection.ltr),
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
    );

    final text = tester.widget<Text>(find.text('Address copied'));
    expect(text.style?.color, AppThemeData.light.colors.text.inverse);
    expect(text.style?.fontFamily, AppTypography.labelLarge.fontFamily);
    expect(text.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(text.style?.height, AppTypography.labelLarge.height);
    expect(text.style?.letterSpacing, AppTypography.labelLarge.letterSpacing);

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.name, AppIcons.checkCircle);
    expect(icon.size, 20);
    expect(icon.color, AppThemeData.light.colors.icon.inverse);
  });

  testWidgets('AppToast destructive tone matches the error toast tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.dark,
        child: Center(
          child: AppToast(
            message: "Can't read the clipboard",
            iconName: AppIcons.cancel,
            tone: AppToastTone.destructive,
          ),
        ),
      ),
    );

    final toastFinder = find.byType(AppToast);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: toastFinder,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.color,
      AppThemeData.dark.colors.background.utilityDestructiveStrong,
    );

    final text = tester.widget<Text>(find.text("Can't read the clipboard"));
    expect(text.style?.color, const Color(0xFFFFFFFF));
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(text.style?.fontSize, AppTypography.labelLarge.fontSize);

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.name, AppIcons.cancel);
    expect(icon.size, 20);
    expect(icon.color, const Color(0xFFFFFFFF));
  });

  testWidgets('AppToast clears inherited text decoration', (tester) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: DefaultTextStyle(
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.yellow,
          ),
          child: Center(child: AppToast(message: 'Address copied')),
        ),
      ),
    );

    final textContext = tester.element(find.text('Address copied'));
    expect(
      DefaultTextStyle.of(textContext).style.decoration,
      TextDecoration.none,
    );
  });

  testWidgets('showAppToast displays a top-centered transient toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: SizedBox(
          width: 400,
          height: 300,
          child: AppToastHost(child: _ToastTrigger(message: 'Address copied')),
        ),
      ),
    );

    expect(find.text('Address copied'), findsNothing);

    await tester.tap(find.text('Show toast'));
    await tester.pump();

    expect(find.text('Address copied'), findsOneWidget);
    final hostTopLeft = tester.getTopLeft(find.byType(AppToastHost));
    final hostSize = tester.getSize(find.byType(AppToastHost));
    final toastTopLeft = tester.getTopLeft(find.byType(AppToast));
    final toastSize = tester.getSize(find.byType(AppToast));
    expect(toastTopLeft.dy, hostTopLeft.dy + AppSpacing.base);
    expect(
      toastTopLeft.dx + toastSize.width / 2,
      moreOrLessEquals(hostTopLeft.dx + hostSize.width / 2),
    );

    await tester.pump(AppToast.defaultDuration);
    await tester.pump();

    expect(find.text('Address copied'), findsNothing);
  });

  testWidgets('toast clears the status bar when the host ignores SafeArea', (
    tester,
  ) async {
    const statusBarHeight = 59.0;
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.light,
        child: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: statusBarHeight),
          ),
          child: const SizedBox(
            width: 400,
            height: 600,
            child: AppToastHost(
              child: _ToastTrigger(message: 'Address copied'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show toast'));
    await tester.pump();

    final hostTop = tester.getTopLeft(find.byType(AppToastHost)).dy;
    final toastTop = tester.getTopLeft(find.byType(AppToast)).dy;
    expect(toastTop, hostTop + statusBarHeight + AppSpacing.xs);
  });

  testWidgets('a long message wraps inside the pill instead of overflowing', (
    tester,
  ) async {
    const message =
        "We couldn't refresh your shielded address. Try again, or use "
        'your current one.';
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: SizedBox(
          width: 393,
          height: 600,
          child: AppToastHost(child: _ToastTrigger(message: message)),
        ),
      ),
    );

    await tester.tap(find.text('Show toast'));
    await tester.pump();

    // No RenderFlex overflow: the toast stays within the host bounds.
    expect(tester.takeException(), isNull);
    final toastRight = tester.getTopRight(find.byType(AppToast)).dx;
    final hostRight = tester.getTopRight(find.byType(AppToastHost)).dx;
    expect(toastRight, lessThanOrEqualTo(hostRight - AppSpacing.sm + 0.01));
  });

  testWidgets('showAppToast can use the active host from an ancestor context', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.light,
        child: Builder(
          builder: (outerContext) {
            return Stack(
              children: [
                const Positioned.fill(
                  child: AppToastHost(child: SizedBox.expand()),
                ),
                TextButton(
                  onPressed: () =>
                      showAppToast(outerContext, 'Parent Context Toast'),
                  child: const Text('Show from parent'),
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Show from parent'));
    await tester.pump();

    expect(find.text('Parent Context Toast'), findsOneWidget);
  });

  testWidgets(
    'actionable notice stays readable and dismissible at large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        late BuildContext toastContext;
        var openedCard = false;
        await tester.pumpWidget(
          _ThemedHarness(
            theme: AppThemeData.light,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: AppToastHost(
                child: Builder(
                  builder: (context) {
                    toastContext = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        );
        void showNotice() => showAppToast(
          toastContext,
          'Couldn’t redeem your gift card.',
          duration: null,
          action: AppToastAction(
            label: 'View card',
            onPressed: () => openedCard = true,
          ),
        );
        showNotice();
        await tester.pump(const Duration(seconds: 30));
        expect(tester.takeException(), isNull);
        expect(find.text('Couldn’t redeem your gift card.'), findsOneWidget);
        final message = tester.widget<Text>(
          find.text('Couldn’t redeem your gift card.'),
        );
        expect(message.maxLines, isNull);
        final action = find.widgetWithText(TextButton, 'View card');
        expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSize(find.byType(IconButton)).width,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester.getSemantics(find.byType(AppToast)),
          matchesSemantics(isLiveRegion: true),
        );
        await tester.tap(find.bySemanticsLabel('Dismiss notification'));
        await tester.pump();
        expect(find.byType(AppToast), findsNothing);
        expect(openedCard, isFalse);
        showNotice();
        await tester.pump();
        await tester.tap(action);
        await tester.pump();
        expect(openedCard, isTrue);
        expect(find.byType(AppToast), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('screen dismissal does not remove a replacement toast', (
    tester,
  ) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.light,
        child: AppToastHost(
          child: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final dismiss = showAppToast(toastContext, 'Old notice', duration: null);
    showAppToast(toastContext, 'Address copied');
    dismiss?.call();
    await tester.pump();
    expect(find.text('Address copied'), findsOneWidget);
  });

  for (final direction in TextDirection.values) {
    testWidgets('toast controls share one axis in $direction', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _ThemedHarness(
          theme: AppThemeData.light,
          child: Directionality(
            textDirection: direction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Center(
                child: AppToast(
                  message: 'Couldn’t redeem your gift card.',
                  iconName: AppIcons.warning,
                  action: AppToastAction(label: 'View card', onPressed: () {}),
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final messageCenter = tester
          .getCenter(find.text('Couldn’t redeem your gift card.'))
          .dy;
      for (final control in [
        find.widgetWithText(TextButton, 'View card'),
        find.byType(IconButton),
        find.byType(AppIcon).first,
      ]) {
        expect(tester.getCenter(control).dy, moreOrLessEquals(messageCenter));
      }
      final toastRect = tester.getRect(find.byType(AppToast));
      final iconRect = tester.getRect(find.byType(AppIcon).first);
      final dismissIconRect = tester.getRect(find.byType(AppIcon).last);
      final leadingInset = direction == TextDirection.ltr
          ? iconRect.left - toastRect.left
          : toastRect.right - iconRect.right;
      final trailingInset = direction == TextDirection.ltr
          ? toastRect.right - dismissIconRect.right
          : dismissIconRect.left - toastRect.left;
      expect(leadingInset, moreOrLessEquals(trailingInset));

      // Large text moves the action below the same logical leading edge.
      await tester.pumpWidget(
        _ThemedHarness(
          theme: AppThemeData.dark,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: direction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Center(
                  child: AppToast(
                    message: 'Couldn’t redeem your gift card.',
                    action: AppToastAction(
                      label: 'View card',
                      onPressed: () {},
                    ),
                    onDismiss: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final messageRect = tester.getRect(
        find.text('Couldn’t redeem your gift card.'),
      );
      final actionRect = tester.getRect(find.text('View card'));
      expect(actionRect.top, greaterThanOrEqualTo(messageRect.bottom));
      expect(
        direction == TextDirection.ltr ? actionRect.left : actionRect.right,
        moreOrLessEquals(
          direction == TextDirection.ltr ? messageRect.left : messageRect.right,
        ),
      );
    });
  }

  testWidgets(
    'active host fallback restores parent after nested host disposes',
    (tester) async {
      await tester.pumpWidget(
        const _ThemedHarness(
          theme: AppThemeData.light,
          child: _NestedToastHosts(showNestedHost: true),
        ),
      );
      await tester.pumpWidget(
        const _ThemedHarness(
          theme: AppThemeData.light,
          child: _NestedToastHosts(showNestedHost: false),
        ),
      );

      await tester.tap(find.text('Show after nested dispose'));
      await tester.pump();

      expect(find.text('Restored Parent Toast'), findsOneWidget);
    },
  );

  testWidgets('toast from a root-navigator modal renders above the modal', (
    tester,
  ) async {
    // A host-bearing screen (e.g. mobile home) covered by a root-navigator
    // bottom sheet (e.g. the accounts sheet). Copying from the sheet must
    // surface the toast in the root overlay ABOVE the sheet, not inside the
    // host the sheet covers (which would render it behind the scrim).
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: const AppToastHost(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _OpenModalButton(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open modal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy from modal'));
    await tester.pump();

    // Renders (the captured theme keeps AppToast.build from throwing) ...
    expect(find.text('Modal Toast'), findsOneWidget);
    // ... and from the root overlay, not inside the covered host.
    expect(
      find.descendant(
        of: find.byType(AppToastHost),
        matching: find.text('Modal Toast'),
      ),
      findsNothing,
    );
  });
}

class _OpenModalButton extends StatelessWidget {
  const _OpenModalButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          builder: (_) => AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (sheetContext) => TextButton(
                onPressed: () => showAppToast(sheetContext, 'Modal Toast'),
                child: const Text('Copy from modal'),
              ),
            ),
          ),
        ),
        child: const Text('Open modal'),
      ),
    );
  }
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.theme, required this.child});

  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AppTheme(
        data: theme,
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );
  }
}

class _ToastTrigger extends StatelessWidget {
  const _ToastTrigger({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => showAppToast(context, message),
      child: const Text('Show toast'),
    );
  }
}

class _NestedToastHosts extends StatelessWidget {
  const _NestedToastHosts({required this.showNestedHost});

  final bool showNestedHost;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (outerContext) {
        return Stack(
          children: [
            const Positioned.fill(
              child: AppToastHost(child: SizedBox.expand()),
            ),
            if (showNestedHost)
              const Positioned.fill(
                child: AppToastHost(child: SizedBox.expand()),
              ),
            TextButton(
              onPressed: () =>
                  showAppToast(outerContext, 'Restored Parent Toast'),
              child: const Text('Show after nested dispose'),
            ),
          ],
        );
      },
    );
  }
}
