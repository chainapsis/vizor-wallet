import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_address_edit_modal.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    builder: (_, navigator) =>
        AppTheme(data: AppThemeData.dark, child: navigator!),
    home: Material(
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
}

// USDC's chainTicker is 'eth', which resolves to an EVM AddressBookNetwork
// with a non-null evmChainIdFor — i.e. a chain names can be submitted on.
SwapState _evmState({
  String destinationText = '',
  SwapDestinationResolveStatus destinationResolveStatus =
      SwapDestinationResolveStatus.idle,
  String? destinationResolveError,
}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '1',
    receiveAmountText: '10',
    destinationText: destinationText,
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    destinationResolveStatus: destinationResolveStatus,
    destinationResolveError: destinationResolveError,
  );
}

// SOL is not an EVM chain, so names must keep failing format validation
// there.
SwapState _nonEvmState({String destinationText = ''}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '1',
    receiveAmountText: '10',
    destinationText: destinationText,
    externalAsset: SwapAsset.sol,
    reviewVisible: false,
    intents: const [],
  );
}

void main() {
  testWidgets(
    'typing an ENS name on an EVM chain shows no format error and enables '
    'Update',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          SwapAddressEditModal(
            state: _evmState(),
            onSubmitted: (_, _) async => true,
            onScan: () {},
            onOpenContacts: () {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        'alice.eth',
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('swap_destination_format_error')),
        findsNothing,
      );
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('swap_address_update_button')),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('tapping Update routes the trimmed value to onSubmitted', (
    tester,
  ) async {
    String? submittedValue;
    var submitCalls = 0;
    await tester.pumpWidget(
      _harness(
        SwapAddressEditModal(
          state: _evmState(),
          onSubmitted: (value, remember) async {
            submitCalls++;
            submittedValue = value;
            return true;
          },
          onScan: () {},
          onOpenContacts: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '  alice.eth  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pump();

    expect(submitCalls, 1);
    expect(submittedValue, 'alice.eth');
  });

  testWidgets(
    'a failed resolve status shows the resolve error and keeps Update '
    'actionable',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          SwapAddressEditModal(
            state: _evmState(
              destinationText: 'alice.eth',
              destinationResolveStatus: SwapDestinationResolveStatus.failed,
              destinationResolveError: 'Could not resolve name',
            ),
            onSubmitted: (_, _) async => false,
            onScan: () {},
            onOpenContacts: () {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Could not resolve name'), findsOneWidget);
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('swap_address_update_button')),
      );
      expect(button.onPressed, isNotNull, reason: 'modal stays actionable');
    },
  );

  testWidgets(
    'a name on a non-EVM chain keeps a format error and disables Update',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          SwapAddressEditModal(
            state: _nonEvmState(),
            onSubmitted: (_, _) async => true,
            onScan: () {},
            onOpenContacts: () {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        'alice.eth',
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('swap_destination_format_error')),
        findsOneWidget,
      );
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('swap_address_update_button')),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('a resolving status shows a spinner and disables Update', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SwapAddressEditModal(
          state: _evmState(
            destinationText: 'alice.eth',
            destinationResolveStatus: SwapDestinationResolveStatus.resolving,
          ),
          onSubmitted: (_, _) async => true,
          onScan: () {},
          onOpenContacts: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_destination_resolving_indicator')),
      findsOneWidget,
    );
    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_address_update_button')),
    );
    expect(button.onPressed, isNull);
  });
}
