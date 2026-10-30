import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/settings/widgets/swap_history_check_control.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/swap_history_check_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

/// NEAR swap privacy, on.
class _Privacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;
}

/// A check fixed in `shown`, so the control renders that state's actions.
class _Check extends SwapHistoryCheckNotifier {
  _Check(this.shown);

  final SwapHistoryCheck shown;

  @override
  SwapHistoryCheck build() => shown;
}

/// Whether the wallet keeps a manual job, fixed.
class _JobSaved extends SwapHistoryJobSaved {
  _JobSaved(this.saved);

  final bool saved;

  @override
  bool build() => saved;
}

/// The control at phone width in `theme`, showing `check`, with the wallet
/// calls of `api` when given and a saved manual job when `saved`.
Widget _control(
  AppThemeData theme,
  SwapHistoryCheck check, {
  SwapHistoryApi? api,
  bool saved = false,
}) => ProviderScope(
  overrides: [
    nearSwapPrivacyProvider.overrideWith(_Privacy.new),
    swapRecoveryStatusReaderProvider.overrideWithValue(() async => null),
    swapHistoryCheckProvider.overrideWith(() => _Check(check)),
    swapHistoryJobSavedProvider.overrideWith(() => _JobSaved(saved)),
    if (api != null) swapHistoryApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    builder: (context, child) => AppTheme(data: theme, child: child!),
    home: const Scaffold(
      body: Center(
        child: SizedBox(width: 320, child: SwapHistoryCheckControl()),
      ),
    ),
  ),
);

void main() {
  for (final (name, theme) in [
    ('light', AppThemeData.light),
    ('dark', AppThemeData.dark),
  ]) {
    testWidgets('the control lays out without overlap in the $name theme', (
      tester,
    ) async {
      await tester.pumpWidget(_control(theme, SwapHistoryCheck.checking));
      await tester.pump();

      // No address count to choose: no field, one explanation line.
      expect(find.byType(EditableText), findsNothing);
      final explanation = find.byKey(
        const ValueKey('settings_swap_history_explanation'),
      );
      final status = find.byKey(
        const ValueKey('settings_check_swap_history_status'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(explanation);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'shown in full');
      final check = tester.getRect(
        find.byKey(const ValueKey('settings_check_swap_history')),
      );
      final pause = tester.getRect(
        find.byKey(const ValueKey('settings_cancel_swap_history')),
      );
      expect(tester.getRect(explanation).bottom, lessThanOrEqualTo(check.top));
      for (final above in [check, pause]) {
        expect(above.bottom, lessThanOrEqualTo(tester.getRect(status).top));
      }
      // The two actions are separate buttons with a gap between them.
      expect(check.overlaps(pause), isFalse);
      expect(check.right < pause.left || check.bottom < pause.top, isTrue);
    });
  }

  testWidgets('a check waiting for sync says so instead of interrupted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.waitingForSync),
    );
    await tester.pump();
    expect(
      find.text('Waiting for wallet sync. Try again in a few minutes.'),
      findsOneWidget,
    );
    expect(find.textContaining('interrupted'), findsNothing);
  });

  testWidgets('a check waiting for the service blames the service, not sync', (
    tester,
  ) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.waitingForService),
    );
    await tester.pump();
    expect(
      find.text(
        "The swap recovery service hasn't caught up with this wallet yet. "
        'Try again in a few minutes.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('wallet sync'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings_cancel_swap_history')),
      findsNothing,
    );
  });

  testWidgets('a check waiting for sync can still pause a saved job', (
    tester,
  ) async {
    var cancelled = 0;
    await tester.pumpWidget(
      _control(
        AppThemeData.dark,
        SwapHistoryCheck.waitingForSync,
        saved: true,
        api: SwapHistoryApi(
          begin: () async {},
          cancel: () async => cancelled++,
          status: () async => throw StateError('not polled'),
        ),
      ),
    );
    await tester.pump();
    final pause = find.byKey(const ValueKey('settings_cancel_swap_history'));
    expect(pause, findsOneWidget);
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(find.text('Paused. Check again to resume.'), findsOneWidget);
  });

  testWidgets('a fresh wait for sync with no saved job offers no pause', (
    tester,
  ) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.waitingForSync),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings_cancel_swap_history')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings_check_swap_history')),
      findsOneWidget,
    );
  });

  for (final (check, line) in [
    (
      SwapHistoryCheck.failed,
      "Swap history can't be checked right now. Try again later.",
    ),
    (
      SwapHistoryCheck.walletChanged,
      'The check stopped because the wallet changed. Try again.',
    ),
    (
      SwapHistoryCheck.notStarted,
      "The check couldn't start. Try again in a moment.",
    ),
  ]) {
    testWidgets('${check.name} with no saved job offers no pause and never '
        'mentions it', (tester) async {
      await tester.pumpWidget(_control(AppThemeData.dark, check));
      await tester.pump();
      expect(find.text(line), findsOneWidget);
      expect(line.toLowerCase(), isNot(contains('pause')));
      expect(
        find.byKey(const ValueKey('settings_cancel_swap_history')),
        findsNothing,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('settings_check_swap_history')),
            )
            .onPressed,
        isNotNull,
        reason: 'the user can try again',
      );
    });
  }

  testWidgets('a refused pause keeps Pause on screen', (tester) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.pauseFailed, saved: true),
    );
    await tester.pump();
    expect(find.text("Couldn't pause the check. Try again."), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings_cancel_swap_history')),
      findsOneWidget,
    );
  });

  testWidgets('an update request uses the quote wording', (tester) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.updateRequired),
    );
    await tester.pump();
    expect(
      find.text(
        'Update Vizor to keep checking private swap addresses. '
        'Your saved progress is kept.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a long check promises progress only while Vizor is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _control(AppThemeData.dark, SwapHistoryCheck.continuing, saved: true),
    );
    await tester.pump();
    expect(
      find.text('The check will keep going while Vizor is open.'),
      findsOneWidget,
    );
    expect(find.textContaining('background'), findsNothing);
  });

  testWidgets('a finished check says so plainly', (tester) async {
    await tester.pumpWidget(_control(AppThemeData.dark, SwapHistoryCheck.done));
    await tester.pump();
    expect(find.text('Swap history check complete.'), findsOneWidget);
  });
}
