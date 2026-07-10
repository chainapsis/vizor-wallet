@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_transaction_progress_screen.dart';

void main() {
  testWidgets('renders custom success copy and both actions', (tester) async {
    await _setMobileViewport(tester);
    var primaryPressed = false;
    var secondaryPressed = false;

    await tester.pumpWidget(
      _app(
        MobileTransactionProgressScreen(
          phase: MobileTransactionProgressPhase.succeeded,
          title: 'Payment\nSubmitted',
          body: 'It will confirm on-chain shortly. Track it in Activity.',
          bodyMaxWidth: 245,
          canPop: true,
          titleKey: const ValueKey('custom_progress_title'),
          statusBadgeKey: const ValueKey('custom_progress_badge'),
          successIconKey: const ValueKey('custom_progress_success_icon'),
          primaryActionKey: const ValueKey('custom_progress_primary'),
          primaryActionLabel: 'Done',
          onPrimaryAction: () => primaryPressed = true,
          secondaryActionKey: const ValueKey('custom_progress_secondary'),
          secondaryActionLabel: 'Go to activity',
          onSecondaryAction: () => secondaryPressed = true,
        ),
      ),
    );

    expect(find.text('Payment\nSubmitted'), findsOneWidget);
    expect(
      find.text('It will confirm on-chain shortly. Track it in Activity.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('custom_progress_badge')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('custom_progress_success_icon')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('custom_progress_primary')));
    await tester.tap(find.byKey(const ValueKey('custom_progress_secondary')));
    expect(primaryPressed, isTrue);
    expect(secondaryPressed, isTrue);
  });

  testWidgets('in-progress presentation can block pop and reserve no actions', (
    tester,
  ) async {
    await _setMobileViewport(tester);

    await tester.pumpWidget(
      _app(
        const MobileTransactionProgressScreen(
          phase: MobileTransactionProgressPhase.inProgress,
          title: 'Submitting payment...',
          body: 'Submitting your payment to the network...',
          canPop: false,
          progressIconKey: ValueKey('custom_progress_loader'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('custom_progress_loader')),
      findsOneWidget,
    );
    expect(find.byType(AppButton), findsNothing);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: AppTheme(data: AppThemeData.light, child: child),
  );
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
