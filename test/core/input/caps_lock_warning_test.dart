import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';
import 'package:zcash_wallet/src/core/input/caps_lock_monitor.dart';
import 'package:zcash_wallet/src/core/input/caps_lock_warning.dart';
import 'package:zcash_wallet/src/core/widgets/app_tooltip.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/password_text_field.dart';
import 'package:zcash_wallet/src/features/settings/widgets/confirm_access_card.dart';

void main() {
  late CapsLockMonitor monitor;
  setUp(() => monitor = CapsLockMonitor(enabled: false));
  tearDown(() => monitor.dispose());

  Widget harness(
    Widget child, {
    AppThemeData theme = AppThemeData.dark,
    Alignment alignment = Alignment.center,
  }) => ProviderScope(
    overrides: [capsLockMonitorProvider.overrideWithValue(monitor)],
    child: MaterialApp(
      builder: (context, child) => AppTheme(data: theme, child: child!),
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: SizedBox(
            width: 396,
            child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      ),
    ),
  );

  testWidgets('focused field keeps warning above it without shifting layout', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      harness(
        AppPasswordInput(
          child: PasswordTextField(
            label: 'Password',
            focusNode: focus,
            messageText: 'Incorrect password',
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.getRect(find.byType(PasswordTextField));
    monitor.value = true;
    await tester.pump();
    expect(find.text('Caps Lock is on'), findsNothing);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Caps Lock is on'), findsOneWidget);
    expect(tester.getRect(find.byType(PasswordTextField)), before);
    expect(
      tester.getRect(find.text('Caps Lock is on')).bottom,
      lessThan(tester.getTopLeft(find.byType(CapsLockWarning)).dy),
    );
    expect(find.text('Incorrect password'), findsOneWidget);
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.text('Caps Lock is on'),
            matching: find.byType(Container),
          )
          .first,
    );
    final input = tester.getRect(find.byType(CapsLockWarning));
    expect(bubble.right, input.right);
    expect(bubble.bottom, input.top - 6);
    final label = tester.renderObject<RenderParagraph>(find.text('Password'));
    final labelInk = label
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 8),
        )
        .single
        .toRect()
        .shift(label.localToGlobal(Offset.zero));
    expect(bubble.overlaps(labelInk), isFalse);
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('Caps Lock is on'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Abc123!');
    expect(find.text('Caps Lock is on'), findsOneWidget);
    monitor.value = false;
    await tester.pump();
    expect(find.text('Caps Lock is on'), findsNothing);
    monitor.value = true;
    await tester.pump();
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Caps Lock is on'), findsNothing);
  });

  testWidgets('only the focused password field displays a warning', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    monitor.value = true;
    await tester.pumpWidget(
      harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppPasswordInput(
              child: PasswordTextField(label: 'Password', focusNode: first),
            ),
            const SizedBox(height: 60),
            AppPasswordInput(
              child: PasswordTextField(
                label: 'Confirm password',
                focusNode: second,
              ),
            ),
          ],
        ),
      ),
    );
    first.requestFocus();
    await tester.pumpAndSettle();
    final firstTop = tester.getTopLeft(find.text('Caps Lock is on')).dy;
    second.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Caps Lock is on'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Caps Lock is on')).dy,
      greaterThan(firstTop),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    monitor.value = false;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirm access plain field also warns and disabled field does not',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      monitor.value = true;
      Widget card(bool submitting) => harness(
        ConfirmAccessCard(
          subtitle: 'Enter your password',
          controller: controller,
          errorText: null,
          isSubmitting: submitting,
          canSubmit: true,
          onChanged: () {},
          onSubmit: () {},
        ),
      );
      await tester.pumpWidget(card(false));
      await tester.pumpAndSettle();
      expect(find.text('Caps Lock is on'), findsOneWidget);
      await tester.pumpWidget(card(true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Caps Lock is on'), findsNothing);
    },
  );
  for (final theme in [AppThemeData.dark, AppThemeData.light]) {
    for (final onDarkCard in [false, true]) {
      testWidgets(
        'warning contrast darkTheme=${theme == AppThemeData.dark} darkCard=$onDarkCard',
        (tester) async {
          monitor.value = true;
          await tester.pumpWidget(
            harness(
              AppPasswordInput(
                warningOnDarkCard: onDarkCard,
                child: const PasswordTextField(
                  label: 'Password',
                  showLabel: false,
                  autofocus: true,
                ),
              ),
              theme: theme,
            ),
          );
          await tester.pumpAndSettle();
          final text = find.text('Caps Lock is on');
          final container = find
              .ancestor(of: text, matching: find.byType(Container))
              .first;
          final context = tester.element(text);
          final decoration =
              tester.widget<Container>(container).decoration!
                  as ShapeDecoration;
          final style = tester.widget<Text>(text).style!;
          final special = theme == AppThemeData.light && onDarkCard;
          expect(
            decoration.color,
            special
                ? context.colors.background.ground
                : AppTooltip.decorationOf(context).color,
          );
          expect(
            style.color,
            special
                ? context.colors.text.accent
                : AppTooltip.textStyleOf(context).color,
          );
          final bubble = tester.getRect(container);
          final input = tester.getRect(find.byType(CapsLockWarning));
          expect(bubble.center.dx, input.center.dx);
          expect(bubble.bottom, input.top - 6);
        },
      );
    }
  }
  testWidgets('warning below a field points upwards towards it', (
    tester,
  ) async {
    monitor.value = true;
    await tester.pumpWidget(
      harness(
        const AppPasswordInput(
          child: PasswordTextField(
            label: 'Password',
            showLabel: false,
            autofocus: true,
          ),
        ),
        alignment: Alignment.topCenter,
      ),
    );
    await tester.pumpAndSettle();
    final container = find
        .ancestor(
          of: find.text('Caps Lock is on'),
          matching: find.byType(Container),
        )
        .first;
    final bubble = tester.getRect(container);
    final input = tester.getRect(find.byType(CapsLockWarning));
    expect(bubble.top, input.bottom + 6);
    final decoration =
        tester.widget<Container>(container).decoration! as ShapeDecoration;
    final outline = decoration.shape.getOuterPath(Offset.zero & bubble.size);
    expect(outline.getBounds().top, -4);
    expect(outline.contains(Offset(bubble.width / 2, -3)), isTrue);
    expect(outline.contains(const Offset(1, -3)), isFalse);
  });
}
