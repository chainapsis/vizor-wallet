@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_review_content.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const _recipientAddress = '0x52908400098527886E0F7030069857D2E4169EE7';

const _contact = AddressBookContact(
  id: 'mike',
  label: 'Mike',
  network: AddressBookNetwork.ethereum,
  address: _recipientAddress,
  profilePictureId: 'pfp-01',
  createdAtMs: 0,
  updatedAtMs: 0,
);

const _quote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  mode: SwapQuoteMode.exactOutput,
  sellAmount: 2.251,
  receiveAmount: 990,
  minimumReceiveAmount: 990,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '1:30',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 'u1deposit',
    expiresInLabel: '1:30',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: '2.251 ZEC',
  receiveEstimateTextOverride: '990 USDC',
);

Widget _harness(Widget child, {AppThemeData theme = AppThemeData.light}) {
  return MaterialApp(
    home: AppTheme(
      data: theme,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: Center(
          child: SizedBox(
            width: 361,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

MobilePayReviewContent _content({
  AddressBookContact? contact = _contact,
  bool expired = false,
}) {
  return MobilePayReviewContent(
    quote: _quote,
    recipientAddress: _recipientAddress,
    recipientContact: contact,
    payingFiatText: r'$250.12',
    convertedFiatText: r'$250.12',
    expiresInText: '1:30',
    expired: expired,
  );
}

void main() {
  testWidgets('matches the active review card anatomy and contact content', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    expect(find.text('Paying'), findsOneWidget);
    expect(find.text('990 USDC'), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('0x5290 ... 69EE7'), findsOneWidget);
    expect(find.text('Converted amount'), findsOneWidget);
    expect(find.text('2.251 ZEC'), findsOneWidget);
    expect(find.text(r'$250.12'), findsNWidgets(2));
    expect(find.textContaining('Quote expires in'), findsOneWidget);
    expect(find.textContaining('1:30'), findsOneWidget);

    final summaryRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_review_summary_card')),
    );
    final convertedRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_review_converted_card')),
    );
    final dividerRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_review_expiry_divider')),
    );
    expect(summaryRect.size, const Size(361, 252));
    expect(dividerRect.height, 38);
    expect(convertedRect.size, const Size(361, 138));
    expect(convertedRect.top - summaryRect.bottom, 86);
  });

  testWidgets('opens the shared full-address sheet for an unknown recipient', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content(contact: null)));

    expect(find.text('Unknown address'), findsOneWidget);
    expect(find.text('0x5290 ... 69EE7'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_full_address_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_address_verify_chunks')),
      findsOneWidget,
    );
    expect(find.text('Ethereum address'), findsOneWidget);
    expect(find.text('0x529'), findsOneWidget);
    expect(find.text('Hide address'), findsNothing);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_address_verify_chunks')),
      findsNothing,
    );
  });

  testWidgets('uses expired styling and dark semantic surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_content(expired: true), theme: AppThemeData.dark),
    );

    expect(find.text('Quote expired'), findsOneWidget);
    expect(find.textContaining('Quote expires in'), findsNothing);
    final opacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('mobile_pay_review_converted_opacity')),
    );
    expect(opacity.opacity, 0.5);

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('mobile_pay_review_summary_card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, AppThemeData.dark.colors.background.ground);
    expect(decoration.borderRadius, BorderRadius.circular(28));
  });

  testWidgets('actions switch between confirm, blocked, and refresh states', (
    tester,
  ) async {
    var confirmed = 0;
    var refreshed = 0;
    var cancelled = 0;

    await tester.pumpWidget(
      _harness(
        MobilePayReviewActions(
          expired: false,
          starting: false,
          startBlockedReason: null,
          onConfirm: () => confirmed++,
          onRefreshQuote: () => refreshed++,
          onCancel: () => cancelled++,
        ),
      ),
    );

    expect(find.text('Confirm & pay'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
        matching: _appIcon(AppIcons.paid),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_cancel_button')),
    );
    expect(confirmed, 1);
    expect(cancelled, 1);

    await tester.pumpWidget(
      _harness(
        MobilePayReviewActions(
          expired: false,
          starting: false,
          startBlockedReason: 'Insufficient shielded balance',
          onConfirm: () => confirmed++,
          onRefreshQuote: () => refreshed++,
          onCancel: () => cancelled++,
        ),
      ),
    );
    expect(find.text('Not enough ZEC'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
      warnIfMissed: false,
    );
    expect(confirmed, 1);
    expect(cancelled, 1);

    await tester.pumpWidget(
      _harness(
        MobilePayReviewActions(
          expired: false,
          starting: true,
          startBlockedReason: null,
          onConfirm: () => confirmed++,
          onRefreshQuote: () => refreshed++,
          onCancel: () => cancelled++,
        ),
      ),
    );
    expect(find.text('Paying'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_cancel_button')),
      warnIfMissed: false,
    );
    expect(confirmed, 1);
    expect(cancelled, 1);

    await tester.pumpWidget(
      _harness(
        MobilePayReviewActions(
          expired: true,
          starting: false,
          startBlockedReason: null,
          onConfirm: () => confirmed++,
          onRefreshQuote: () => refreshed++,
          onCancel: () => cancelled++,
        ),
      ),
    );
    expect(find.text('Refresh quote'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_pay_review_refresh_quote_button'),
        ),
        matching: _appIcon(AppIcons.renew),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_refresh_quote_button')),
    );
    expect(refreshed, 1);
  });
}

Finder _appIcon(String name) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == name,
  );
}
