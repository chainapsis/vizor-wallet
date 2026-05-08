import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';

void main() {
  testWidgets('AppToast uses inverse neutral tokens in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: Center(child: AppToast(message: 'Address Copied')),
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
      padding.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
    );

    final text = tester.widget<Text>(find.text('Address Copied'));
    expect(text.style?.color, AppThemeData.light.colors.text.inverse);
    expect(text.style?.fontFamily, AppTypography.labelLarge.fontFamily);
    expect(text.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(text.style?.height, AppTypography.labelLarge.height);
    expect(text.style?.letterSpacing, AppTypography.labelLarge.letterSpacing);

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.name, AppIcons.checkCircle);
    expect(icon.size, AppIconSize.medium);
    expect(icon.color, AppThemeData.light.colors.icon.inverse);
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
          child: AppToastHost(child: _ToastTrigger(message: 'Address Copied')),
        ),
      ),
    );

    expect(find.text('Address Copied'), findsNothing);

    await tester.tap(find.text('Show toast'));
    await tester.pump();

    expect(find.text('Address Copied'), findsOneWidget);
    final hostTopLeft = tester.getTopLeft(find.byType(AppToastHost));
    final hostSize = tester.getSize(find.byType(AppToastHost));
    final enteringToastTopLeft = tester.getTopLeft(find.byType(AppToast));
    expect(enteringToastTopLeft.dy, lessThan(hostTopLeft.dy + AppSpacing.base));

    await tester.pump(AppToastHost.animationDuration);

    final toastTopLeft = tester.getTopLeft(find.byType(AppToast));
    final toastSize = tester.getSize(find.byType(AppToast));
    expect(toastTopLeft.dy, hostTopLeft.dy + AppSpacing.base);
    expect(
      toastTopLeft.dx + toastSize.width / 2,
      moreOrLessEquals(hostTopLeft.dx + hostSize.width / 2),
    );

    await tester.pump(AppToast.defaultDuration);
    await tester.pumpAndSettle();

    expect(find.text('Address Copied'), findsNothing);
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
