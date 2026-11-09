import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_progress_explorer_footer.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';

const _address = 't1provider-deposit';
const _uri = 'https://explorer.near-intents.org/transactions/$_address';
const _footer = ValueKey('swap_progress_explorer_link');

void runActivityProgressChecks({required bool mobile}) {
  for (final pay in [false, true]) {
    final flow = pay ? 'Pay' : 'Swap';
    final progressLabel = pay ? 'Payment progress' : 'Swap progress';

    testWidgets('$flow progress and details open the same external lookup', (
      tester,
    ) async {
      final launched = <Map<Object?, Object?>>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add(call.arguments as Map<Object?, Object?>);
          return true;
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _pump(
        tester,
        mobile: mobile,
        intent: _intent(pay: pay),
      );
      expect(find.text(progressLabel), findsOneWidget);
      expect(find.text('Tx ID'), findsNothing);
      final footer = find.byKey(_footer);
      await tester.ensureVisible(footer);
      // The empty left edge of the row activates the full-width link too.
      await tester.tapAt(tester.getTopLeft(footer) + const Offset(3, 10));
      await tester.pump();
      expect(launched.single['url'], _uri);
      expect(launched.single['useWebView'], isFalse);

      await tester.ensureVisible(find.text('Transaction details'));
      await tester.tap(find.text('Transaction details'));
      await tester.pumpAndSettle();
      expect(find.byKey(_footer), findsNothing);
      expect(find.text('Tx ID'), findsOneWidget);
      final value = find.text(_address);
      // Source-address rows may repeat the ID, so choose the value belonging
      // to the Tx ID row (the last occurrence for this compact fixture).
      await tester.ensureVisible(value.last);
      await tester.tap(value.last);
      await tester.pumpAndSettle();
      expect(launched, hasLength(2));
      expect(launched.last['url'], _uri);
    });

    testWidgets('$flow retains the selected tab during status updates', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        mobile: mobile,
        intent: _intent(pay: pay, status: SwapIntentStatus.awaitingDeposit),
      );
      final notifier =
          container.read(swapStateProvider.notifier) as _ProgressSwap;
      notifier.setIntent(
        _intent(pay: pay, status: SwapIntentStatus.depositObserved),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_footer), findsOneWidget);
      await tester.tap(find.text('Transaction details'));
      await tester.pumpAndSettle();
      notifier.setIntent(_intent(pay: pay));
      await tester.pumpAndSettle();
      expect(find.text('Tx ID'), findsOneWidget);
      expect(find.byKey(_footer), findsNothing);
      notifier.setIntent(_intent(pay: pay, status: SwapIntentStatus.complete));
      await tester.pumpAndSettle();
      expect(find.text(progressLabel), findsNothing);
      expect(
        find.text(pay || mobile ? 'Completed' : 'Complete'),
        findsOneWidget,
      );
      expect(find.text('Tx ID'), findsOneWidget);
    });

    testWidgets('$flow shows the link as soon as a deposit address arrives', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        mobile: mobile,
        intent: _intent(pay: pay, address: null),
      );
      expect(find.byKey(_footer), findsNothing);
      (container.read(swapStateProvider.notifier) as _ProgressSwap).setIntent(
        _intent(pay: pay),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_footer), findsOneWidget);
    });

    testWidgets('$flow progress footer fits a narrow viewport and large text', (
      tester,
    ) async {
      if (mobile) {
        await _pump(
          tester,
          mobile: true,
          intent: _intent(pay: pay),
          narrow: true,
        );
      } else {
        // Desktop windows do not shrink to a phone's viewport; exercise the
        // new footer at that width without unrelated fixed-height headers.
        await loadFigmaCompareFonts();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 240,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.6),
                      ),
                      child: SwapProgressExplorerFooter(uri: Uri.parse(_uri)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(_footer));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final status in [SwapIntentStatus.failed, SwapIntentStatus.refunded]) {
      testWidgets('$flow ${status.name} uses its terminal detail card', (
        tester,
      ) async {
        await _pump(
          tester,
          mobile: mobile,
          intent: _intent(pay: pay, status: status),
        );
        expect(find.text(progressLabel), findsNothing);
        expect(find.byKey(_footer), findsNothing);
        expect(
          find.text(status == SwapIntentStatus.failed ? 'Failed' : 'Refunded'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    if (!mobile && pay) {
      testWidgets('desktop Pay progress grows with enlarged text', (
        tester,
      ) async {
        await _pump(
          tester,
          mobile: false,
          intent: _intent(pay: true),
          textScale: 1.6,
        );
        await tester.ensureVisible(find.byKey(_footer));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

SwapIntent _intent({
  required bool pay,
  String? address = _address,
  SwapIntentStatus status = SwapIntentStatus.processing,
}) => SwapIntent(
  id: 'progress-intent',
  pair: 'ZEC -> USDC',
  sellAmount: '2 ZEC',
  receiveEstimate: '140 USDC',
  provider: 'NEAR Intents',
  status: status,
  nextAction: 'Processing',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: address,
  oneClickRecipient: '0x52908400098527886E0F7030069857D2E4169EE7',
  payMode: pay,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool mobile,
  required SwapIntent intent,
  bool narrow = false,
  double textScale = 1,
}) async {
  await loadFigmaCompareFonts();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = narrow
      ? const Size(320, 568)
      : mobile
      ? const Size(393, 852)
      : const Size(700, 820);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final container = ProviderContainer(
    overrides: [
      accountProvider.overrideWith(_ProgressAccounts.new),
      addressBookProvider.overrideWith(_ProgressAddressBook.new),
      swapStateProvider.overrideWith(() => _ProgressSwap(intent)),
      privacyModeProvider.overrideWith(_ProgressPrivacyMode.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => AppTheme(
          data: AppThemeData.dark,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(narrow ? 1.6 : textScale),
            ),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: AppToastHost(
            child: SwapActivityDetailSurface(
              intentId: intent.id,
              layout: mobile
                  ? SwapActivityDetailLayout.mobile
                  : SwapActivityDetailLayout.desktop,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _ProgressSwap extends SwapNotifier {
  _ProgressSwap(this.initial);
  final SwapIntent initial;
  @override
  SwapState build() => SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [initial],
    selectedIntentId: initial.id,
  );
  @override
  void selectIntent(String intentId) {}
  void setIntent(SwapIntent intent) =>
      state = state.copyWith(intents: [intent]);
}

class _ProgressAccounts extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState();
}

class _ProgressAddressBook extends AddressBookNotifier {
  @override
  FutureOr<AddressBookState> build() => const AddressBookState();
}

class _ProgressPrivacyMode extends PrivacyModeNotifier {
  @override
  bool build() => false;
}
