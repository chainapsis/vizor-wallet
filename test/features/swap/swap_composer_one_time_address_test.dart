import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_composer_panel.dart';

SwapState _state(SwapDirection direction) => SwapState(
  direction: direction,
  amountText: '',
  receiveAmountText: '',
  destinationText: '0xrecipient',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: const [],
);

Widget _panel(
  SwapDirection direction, {
  bool oneTimeZecAddress = true,
  bool preparing = false,
}) => MaterialApp(
  builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  home: Scaffold(
    body: SwapComposerPanel(
      state: _state(direction),
      onAmountChanged: (_) {},
      onAmountFiatChanged: (_) {},
      onReceiveAmountChanged: (_) {},
      onReceiveAmountFiatChanged: (_) {},
      onToggleFiatInputMode: (_) {},
      onToggleDirection: () {},
      onOpenExternalAssetPicker: () {},
      onOpenDestinationAddress: () {},
      onOpenSlippageSettings: () {},
      onUseMaxZecAmount: () {},
      assetSelectorOpen: false,
      slippageSettingsOpen: false,
      zecAvailableText: '1 ZEC',
      zecAvailableZatoshi: BigInt.from(100000000),
      oneTimeZecAddress: oneTimeZecAddress,
      preparingOneTimeAddress: preparing,
    ),
  ),
);

void main() {
  testWidgets('receiving ZEC names the one-time payout address', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(SwapDirection.externalToZec));

    expect(find.text('One-time address'), findsOneWidget);
  });

  testWidgets('the payout slot says the address is still being prepared', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(SwapDirection.externalToZec, preparing: true),
    );

    expect(find.text('Preparing address…'), findsOneWidget);
    expect(find.text('One-time address'), findsNothing);
  });

  testWidgets('sending ZEC names the one-time refund address', (tester) async {
    await tester.pumpWidget(_panel(SwapDirection.zecToExternal));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_one_time_address_refund')),
        matching: find.text('One-time address'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ordinary addresses leave the slot empty', (tester) async {
    await tester.pumpWidget(
      _panel(SwapDirection.externalToZec, oneTimeZecAddress: false),
    );

    expect(find.text('One-time address'), findsNothing);
  });
}
