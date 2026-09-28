import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';
import 'package:zcash_wallet/src/core/input/caps_lock_monitor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/password_text_field.dart';
import 'package:zcash_wallet/src/features/settings/widgets/confirm_access_card.dart';

void main() {
  late CapsLockMonitor monitor;
  setUp(() => monitor = CapsLockMonitor(enabled: false));
  tearDown(() => monitor.dispose());

  Widget harness(Widget child) => ProviderScope(
    overrides: [capsLockMonitorProvider.overrideWithValue(monitor)],
    child: MaterialApp(
      builder: (context, child) =>
          AppTheme(data: AppThemeData.dark, child: child!),
      home: Scaffold(
        body: Center(
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
      lessThan(before.top),
    );
    expect(find.text('Incorrect password'), findsOneWidget);
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
}
