import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/content_overlay_inset.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/network_fallback_toast.dart';

void main() {
  testWidgets(
    'NetworkFallbackToast uses seed phrase container styling in light mode',
    (tester) async {
      await tester.pumpWidget(
        const _ThemedHarness(
          theme: AppThemeData.light,
          child: Center(
            child: NetworkFallbackToast(
              message: 'Selected endpoint is unstable.',
            ),
          ),
        ),
      );

      final toastFinder = find.byType(NetworkFallbackToast);
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

      expect(decoration.color, AppThemeData.light.colors.background.ground);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.small));
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, const [
        BoxShadow(
          color: Color(0xFFE1E1E1),
          offset: Offset(0, 2),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Color(0xFFE1E1E1),
          offset: Offset(0, 10),
          blurRadius: 15,
        ),
      ]);

      final text = tester.widget<Text>(
        find.text('Selected endpoint is unstable.'),
      );
      expect(text.style?.color, AppThemeData.light.colors.text.accent);
      expect(text.style?.fontFamily, AppTypography.labelLarge.fontFamily);
      expect(text.style?.fontSize, AppTypography.labelLarge.fontSize);
      expect(text.style?.height, AppTypography.labelLarge.height);
      expect(text.style?.letterSpacing, AppTypography.labelLarge.letterSpacing);
      expect(find.byType(AppIcon), findsNothing);
    },
  );

  testWidgets(
    'NetworkFallbackToast uses a subtle border without shadow in dark mode',
    (tester) async {
      await tester.pumpWidget(
        const _ThemedHarness(
          theme: AppThemeData.dark,
          child: Center(
            child: NetworkFallbackToast(
              message: 'Selected endpoint is unstable.',
            ),
          ),
        ),
      );

      final toastFinder = find.byType(NetworkFallbackToast);
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
      final border = decoration.border as Border?;

      expect(decoration.color, AppThemeData.dark.colors.background.ground);
      expect(decoration.boxShadow, isNull);
      expect(border?.top.color, AppThemeData.dark.colors.border.subtle);
      expect(border?.top.width, 1);

      final text = tester.widget<Text>(
        find.text('Selected endpoint is unstable.'),
      );
      expect(text.style?.color, AppThemeData.dark.colors.text.accent);
    },
  );

  testWidgets('NetworkFallbackToast clears inherited text decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: DefaultTextStyle(
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.yellow,
          ),
          child: Center(
            child: NetworkFallbackToast(
              message: 'Selected endpoint is unstable.',
            ),
          ),
        ),
      ),
    );

    final textContext = tester.element(
      find.text('Selected endpoint is unstable.'),
    );
    expect(
      DefaultTextStyle.of(textContext).style.decoration,
      TextDecoration.none,
    );
  });

  testWidgets('showNetworkFallbackToast slides in and expires', (tester) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: SizedBox(
          width: 400,
          height: 300,
          child: NetworkFallbackToastHost(
            child: _ToastTrigger(message: 'Fallback selected'),
          ),
        ),
      ),
    );

    expect(find.text('Fallback selected'), findsNothing);

    await tester.tap(find.text('Show toast'));
    await tester.pump();

    expect(find.text('Fallback selected'), findsOneWidget);
    final hostTopLeft = tester.getTopLeft(
      find.byType(NetworkFallbackToastHost),
    );
    final hostSize = tester.getSize(find.byType(NetworkFallbackToastHost));
    final enteringToastTopLeft = tester.getTopLeft(
      find.byType(NetworkFallbackToast),
    );
    expect(enteringToastTopLeft.dy, lessThan(hostTopLeft.dy + AppSpacing.base));

    await tester.pump(NetworkFallbackToastHost.animationDuration);

    final toastTopLeft = tester.getTopLeft(find.byType(NetworkFallbackToast));
    final toastSize = tester.getSize(find.byType(NetworkFallbackToast));
    expect(toastTopLeft.dy, hostTopLeft.dy + AppSpacing.base);
    expect(
      toastTopLeft.dx + toastSize.width / 2,
      moreOrLessEquals(hostTopLeft.dx + hostSize.width / 2),
    );

    await tester.pump(NetworkFallbackToast.defaultDuration);
    await tester.pumpAndSettle();

    expect(find.text('Fallback selected'), findsNothing);
  });

  testWidgets('toast clears a mounted sidebar inset and re-centers on release', (
    tester,
  ) async {
    const inset = 272.0;
    await tester.pumpWidget(
      const _ThemedHarness(
        theme: AppThemeData.light,
        child: SizedBox(
          width: 800,
          height: 300,
          child: NetworkFallbackToastHost(
            child: ContentOverlayInset(
              leftInset: inset,
              child: _ToastTrigger(message: 'Fallback selected'),
            ),
          ),
        ),
      ),
    );
    // Let the post-frame inset push land.
    await tester.pump();

    await tester.tap(find.text('Show toast'));
    await tester.pump();
    await tester.pump(NetworkFallbackToastHost.animationDuration);

    final hostTopLeft = tester.getTopLeft(
      find.byType(NetworkFallbackToastHost),
    );
    final hostSize = tester.getSize(find.byType(NetworkFallbackToastHost));
    final toastTopLeft = tester.getTopLeft(find.byType(NetworkFallbackToast));
    final toastSize = tester.getSize(find.byType(NetworkFallbackToast));

    // Centered within the pane region [inset, width], not the full window.
    final paneCenter = hostTopLeft.dx + inset + (hostSize.width - inset) / 2;
    expect(
      toastTopLeft.dx + toastSize.width / 2,
      moreOrLessEquals(paneCenter),
    );
    expect(toastTopLeft.dx, greaterThan(hostTopLeft.dx + inset / 2));

    await tester.pump(NetworkFallbackToast.defaultDuration);
    await tester.pumpAndSettle();
  });
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
      onPressed: () => showNetworkFallbackToast(context, message),
      child: const Text('Show toast'),
    );
  }
}
