import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_add_contact_modal.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_amount_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_review_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_wizard_page.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/widgets/pay_activity_status_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_selector_modal.dart';
import 'package:zcash_wallet/widgetbook/pay_use_cases.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('Pay amount use case renders the production wizard anatomy', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayAmountUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(AppDesktopShell), findsOneWidget);
    expect(find.byType(PayWizardPage), findsOneWidget);
    expect(find.byType(PayAmountStep), findsOneWidget);
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text(r'$ 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_amount_counterpart_loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pay_estimated_spend_loading')),
      findsNothing,
    );
    expect(find.byType(PayAmountAction), findsOneWidget);
  });

  testWidgets('Pay recipient use case renders recents and contacts', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayRecipientUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(PayRecipientStep), findsOneWidget);
    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('Recently sent'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Mike'), findsWidgets);
    expect(find.text('-24 USDC'), findsOneWidget);
    expect(find.byType(PayRecipientActions), findsNothing);
  });

  testWidgets('Pay new-address use case renders notice and actions', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayRecipientNewAddressUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('New address detected.'), findsOneWidget);
    expect(find.text('Add to contacts'), findsOneWidget);
    expect(find.text('Select recipient'), findsOneWidget);
  });

  testWidgets('Pay review use case renders a live quote and confirm action', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayReviewUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(PayReviewStep), findsOneWidget);
    expect(find.text('Review Payment'), findsOneWidget);
    expect(find.textContaining('Quote expires in'), findsOneWidget);
    expect(find.text('Confirm & pay'), findsOneWidget);
    expect(find.text('Refresh the quote'), findsNothing);
  });

  testWidgets('Pay expired use case renders the refresh state', (tester) async {
    await _pumpPayUseCase(tester, buildPayReviewExpiredUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Quote expired'), findsOneWidget);
    expect(find.text('Refresh the quote'), findsOneWidget);
    expect(find.text('Confirm & pay'), findsNothing);
  });

  testWidgets('Pay asset selector use case overlays the production modal', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayAssetSelectorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(PayAmountStep), findsOneWidget);
    expect(find.byType(AppPaneModalOverlay), findsOneWidget);
    expect(find.byType(SwapAssetSelectorModal), findsOneWidget);
    expect(find.text('Select asset'), findsOneWidget);
    expect(find.text('Search token or chain'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_external_asset_menu'))),
      const Size(312, 440),
    );
  });

  testWidgets('Pay add contact use case overlays the production modal', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayAddContactUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(PayRecipientStep), findsOneWidget);
    expect(find.byType(AppPaneModalOverlay), findsOneWidget);
    expect(find.byType(PayAddContactModal), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_add_contact_modal')), findsOneWidget);
    expect(find.text('Address label'), findsOneWidget);
    expect(find.text('Chain & address'), findsOneWidget);
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Pay in-progress status use case renders the Figma fixture', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayInProgressUseCase);

    expect(tester.takeException(), isNull);
    final content = tester.widget<PayActivityStatusContent>(
      find.byType(PayActivityStatusContent),
    );
    expect(content.status.phase, PayActivityStatusPhase.inProgress);
    expect(
      tester.getSize(find.byKey(const ValueKey('pay_activity_status_content'))),
      PayActivityStatusContent.contentSize,
    );
    expect(find.text('Pay in progress...'), findsOneWidget);
    expect(find.text('990 USDC'), findsOneWidget);
    expect(find.text(r'$990.12'), findsOneWidget);
    expect(find.text('New address'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    _expectPayStatusDetails();
  });

  testWidgets('Pay completed status use case renders the terminal phase', (
    tester,
  ) async {
    await _pumpPayUseCase(tester, buildPayCompletedUseCase);

    expect(tester.takeException(), isNull);
    final content = tester.widget<PayActivityStatusContent>(
      find.byType(PayActivityStatusContent),
    );
    expect(content.status.phase, PayActivityStatusPhase.completed);
    expect(find.text('Paid successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('In progress'), findsNothing);
    _expectPayStatusDetails();
  });
}

void _expectPayStatusDetails() {
  expect(find.text('25 May, 13:30'), findsOneWidget);
  expect(find.text('0123123124512512'), findsOneWidget);
  expect(find.text('2.45125 ZEC'), findsOneWidget);
  expect(find.text('0.012 ZEC'), findsOneWidget);
}

Future<void> _loadAppFonts() async {
  final fonts = <String, List<String>>{
    'Geist': [
      'assets/fonts/Geist-Regular.ttf',
      'assets/fonts/Geist-Medium.ttf',
      'assets/fonts/Geist-SemiBold.ttf',
    ],
    'Geist Mono': [
      'assets/fonts/GeistMono-Regular.ttf',
      'assets/fonts/GeistMono-Medium.ttf',
    ],
    'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

Future<void> _pumpPayUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1;
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
