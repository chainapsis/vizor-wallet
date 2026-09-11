import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart'
    show kPaymentRequestRequesterTooltip;
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart'
    show kPaymentRequestRequesterNoteScrollViewKey;
import 'package:zcash_wallet/src/features/pay/models/payment_request_resolution.dart';
import 'package:zcash_wallet/src/features/pay/widgets/cross_chain_payment_request_card.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_icon.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _recipient = '0x52908400098527886E0F7030069857D2E4169EE7';
const _contract = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _continueKey = ValueKey('cross_chain_payment_request_continue');
const _cancelKey = ValueKey('cross_chain_payment_request_cancel');
const _editKey = ValueKey('cross_chain_payment_request_edit');
const _captureKey = ValueKey('cross_chain_card_capture');
final _baseUsdc = SwapAsset.live(
  assetId: 'base-usdc',
  symbol: 'USDC',
  blockchain: 'base',
  decimals: 6,
  contractAddress: _contract,
);

void runCrossChainPaymentRequestCardTests({required bool isMobile}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFigmaCompareFonts);

  Future<void> pump(
    WidgetTester tester, {
    CrossChainPaymentRequest? request,
    PaymentRequestResolution? resolution,
    VoidCallback? onContinue,
    VoidCallback? onCancel,
    VoidCallback? onRetry,
    VoidCallback? onEdit,
    ValueChanged<String>? onNetworkSelected,
    String? selectedChain,
    String? availabilityMessage,
    double? estimatedZecAmount = 0.25,
    int? slippageBps = 50,
    VoidCallback? onOpenSlippage,
    bool isLoading = false,
    bool isPreparingReview = false,
    Size? viewport,
    AppThemeData theme = AppThemeData.dark,
  }) async {
    tester.view.physicalSize =
        viewport ?? (isMobile ? const Size(360, 740) : const Size(600, 800));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: theme,
          child: Material(
            color: theme.colors.background.ground,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: RepaintBoundary(
                  key: _captureKey,
                  child: AppModalCard(
                    width: isMobile ? 360 : 396,
                    child: CrossChainPaymentRequestCard(
                      request: request ?? _request(),
                      resolution:
                          resolution ??
                          PaymentRequestResolution(
                            asset: _baseUsdc,
                            amountText: '25',
                          ),
                      onContinue: onContinue ?? () {},
                      onCancel: onCancel ?? () {},
                      onRetry: onRetry ?? () {},
                      onEdit: onEdit ?? () {},
                      onNetworkSelected: onNetworkSelected ?? (_) {},
                      selectedChain: selectedChain,
                      availabilityMessage: availabilityMessage,
                      estimatedZecAmount: estimatedZecAmount,
                      slippageBps: slippageBps,
                      onOpenSlippage: onOpenSlippage ?? () {},
                      isLoading: isLoading,
                      isPreparingReview: isPreparingReview,
                      isMobile: isMobile,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reviews exact recipient amount and network before continuing', (
    tester,
  ) async {
    var continued = 0;
    var cancelled = 0;
    var openedSlippage = 0;
    await pump(
      tester,
      onContinue: () => continued++,
      onCancel: () => cancelled++,
      onOpenSlippage: () => openedSlippage++,
    );

    expect(find.text('Payment request'), findsOneWidget);
    expect(find.text('Recipient gets'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('Selected by you'), findsNothing);
    expect(find.text('Pay with ZEC'), findsNothing);
    expect(find.text('Review payment'), findsOneWidget);
    expect(find.text('Slippage'), findsOneWidget);
    expect(find.text('0.5%'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('cross_chain_payment_request_slippage')),
    );
    expect(openedSlippage, 1);
    expect(find.text('Estimated spend'), findsOneWidget);
    expect(find.text('≈ 0.2500 ZEC'), findsOneWidget);
    expect(
      find.text('Before fees. Actual payment may be higher.'),
      findsNothing,
    );
    expect(find.text('Cancel'), findsNothing);
    expect(find.text(_contract), findsNothing);
    expect(find.text('Token details'), findsNothing);
    expect(find.text(_recipient), findsNothing);
    if (isMobile) {
      await tester.tap(find.text(truncatedAddress(_recipient)));
      await tester.pumpAndSettle();
      expect(find.text(_recipient), findsOneWidget);
      await tester.tap(find.text('Hide full address'));
      await tester.pumpAndSettle();
      expect(find.text(_recipient), findsNothing);
    }
    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    expect(find.text(_recipient), findsOneWidget);
    await tester.tap(find.byKey(_continueKey));
    expect(continued, 1);
    await tester.tap(find.byKey(_cancelKey));
    expect(cancelled, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('amountless requests lead to entering an amount', (tester) async {
    var continued = false;
    await pump(
      tester,
      request: _request(includeAmount: false),
      resolution: PaymentRequestResolution(asset: _baseUsdc),
      onContinue: () => continued = true,
    );
    expect(find.text('Amount not specified'), findsOneWidget);
    expect(find.text('Enter amount'), findsOneWidget);
    expect(find.text('Estimated spend'), findsNothing);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.byKey(_editKey), findsNothing);
    await _capture(tester, isMobile: isMobile, state: 'no-amount');
    await tester.tap(find.byKey(_continueKey));
    expect(continued, isTrue);
  });

  testWidgets(
    'missing prices hide the estimate and tiny costs never show zero',
    (tester) async {
      await pump(tester, estimatedZecAmount: null);
      expect(find.text('Estimated spend'), findsNothing);
      expect(_primary(tester).onPressed, isNotNull);
      await pump(tester, estimatedZecAmount: 0.000001);
      expect(find.text('< 0.0001 ZEC'), findsOneWidget);
      expect(find.text('≈ 0.0000 ZEC'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('requires an explicit missing network and hides atomic amounts', (
    tester,
  ) async {
    String? selected;
    await pump(
      tester,
      request: _request(chainId: null),
      resolution: const PaymentRequestResolution(
        needsNetwork: true,
        message: 'Select the receiving network to see the payment amount.',
      ),
      onNetworkSelected: (chain) => selected = chain,
    );
    expect(find.text('Select network'), findsOneWidget);
    expect(find.text('Selected by you'), findsNothing);
    expect(find.text('Network not specified'), findsOneWidget);
    expect(find.textContaining('25000000'), findsNothing);
    expect(_primary(tester).onPressed, isNull);
    expect(
      find.byKey(const ValueKey('payment_request_asset_icon')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('payment_network_base')), findsNothing);
    await _capture(tester, isMobile: isMobile, state: 'choose-network');
    await tester.tap(
      find.byKey(const ValueKey('payment_request_select_network')),
    );
    await tester.pumpAndSettle();
    for (final network in evmPaymentNetworks.values) {
      final button = tester.widget<AppButton>(
        find.byKey(ValueKey('payment_network_${network.chain}')),
      );
      expect(button.variant, AppButtonVariant.secondary);
      expect(
        find.text('${network.nativeSymbol} · ${network.label}'),
        findsNothing,
      );
    }
    await _capture(tester, isMobile: isMobile, state: 'network-options');
    await tester.tap(find.byKey(const ValueKey('payment_network_base')));
    expect(selected, 'base');

    await pump(
      tester,
      request: _request(chainId: null),
      selectedChain: selected,
    );
    expect(find.text('25'), findsOneWidget);
    expect(_primary(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('payment_network_base')), findsNothing);
    expect(find.text('Selected by you'), findsOneWidget);
    await _capture(tester, isMobile: isMobile, state: 'network-selected');
    await tester.tap(
      find.byKey(const ValueKey('payment_request_select_network')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('payment_network_base')))
          .variant,
      AppButtonVariant.primary,
    );

    final nativeRequest = CrossChainPaymentRequest(
      id: 'native-network-request',
      rawUri: 'ethereum:$_recipient?value=10000000000000000',
      address: _recipient,
      isEvm: true,
      amount: PaymentRequestAmount.atomicHex('0x2386f26fc10000'),
    );
    final nativeAssets = [
      for (final network in evmPaymentNetworks.values)
        SwapAsset.live(
          assetId: 'native-${network.chain}',
          symbol: network.nativeSymbol,
          blockchain: network.chain,
          decimals: 18,
        ),
    ];
    selected = null;
    await pump(
      tester,
      request: nativeRequest,
      resolution: resolveCrossChainPaymentRequest(nativeRequest, nativeAssets),
      onNetworkSelected: (chain) => selected = chain,
    );
    expect(_primary(tester).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('payment_request_select_network')),
    );
    await tester.pumpAndSettle();
    for (final network in evmPaymentNetworks.values) {
      expect(
        find.text('${network.nativeSymbol} · ${network.label}'),
        findsOneWidget,
      );
    }
    await _capture(tester, isMobile: isMobile, state: 'native-network-options');
    await tester.tap(find.byKey(const ValueKey('payment_network_bsc')));
    expect(selected, 'bsc');
    await pump(
      tester,
      request: nativeRequest,
      selectedChain: selected,
      resolution: resolveCrossChainPaymentRequest(
        nativeRequest,
        nativeAssets,
        selectedChain: selected,
      ),
    );
    expect(find.text('0.01'), findsOneWidget);
    expect(find.text('BNB'), findsOneWidget);
    expect(find.text('BNB Chain'), findsOneWidget);
    expect(find.text('USDC'), findsNothing);
    expect(find.text('Network not specified'), findsNothing);
    expect(_primary(tester).onPressed, isNotNull);
    await _capture(
      tester,
      isMobile: isMobile,
      state: 'native-network-selected',
    );
    await pump(
      tester,
      request: nativeRequest,
      selectedChain: selected,
      resolution: resolveCrossChainPaymentRequest(
        nativeRequest,
        nativeAssets,
        selectedChain: selected,
      ),
      theme: AppThemeData.light,
    );
    await _capture(
      tester,
      isMobile: isMobile,
      state: 'native-network-selected-light',
    );
  });

  testWidgets('unsupported requests cannot continue or become raw addresses', (
    tester,
  ) async {
    const reason =
        'This request needs tracking details that Vizor cannot send.';
    const uri = 'solana:https://merchant.example/transaction';
    await pump(
      tester,
      request: const CrossChainPaymentRequest(
        id: 'unsupported',
        rawUri: uri,
        address: '',
        isEvm: false,
        chain: 'sol',
        unsupportedReason: reason,
      ),
      resolution: const PaymentRequestResolution(message: reason),
    );
    expect(find.text(reason), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text(uri), findsNothing);
    expect(find.text('To'), findsNothing);
    expect(find.text('Pay with ZEC'), findsNothing);
    expect(find.text('Estimated spend'), findsNothing);
    expect(_primary(tester).onPressed, isNull);
    await _capture(tester, isMobile: isMobile, state: 'unsupported');
  });

  testWidgets(
    'unresolved token skeletons become payment details after loading',
    (tester) async {
      await pump(
        tester,
        isLoading: true,
        resolution: const PaymentRequestResolution(),
      );
      expect(
        find.byKey(const ValueKey('payment_request_icon_skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_request_token_skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_request_amount_skeleton')),
        findsOneWidget,
      );
      expect(find.text('Base'), findsOneWidget);
      expect(find.text(truncatedAddress(_recipient)), findsOneWidget);
      expect(find.text('Amount unavailable'), findsNothing);
      expect(_primary(tester).onPressed, isNull);
      await _capture(tester, isMobile: isMobile, state: 'loading-skeleton');
      await pump(tester);
      expect(
        find.byKey(const ValueKey('payment_request_icon_skeleton')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment_request_token_skeleton')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment_request_amount_skeleton')),
        findsNothing,
      );
      expect(find.text('25'), findsOneWidget);
      expect(find.text('USDC'), findsOneWidget);
      expect(_primary(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await _capture(tester, isMobile: isMobile, state: 'loaded-skeleton');
    },
  );

  testWidgets('loading preserves request details and blocks continuing', (
    tester,
  ) async {
    await pump(tester, isLoading: true);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Checking payment options…'), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('cross_chain_payment_request_slippage')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Estimated spend'), findsNothing);
    expect(_primary(tester).onPressed, isNull);
  });

  testWidgets('lookup failure offers retry instead of continuing', (
    tester,
  ) async {
    var continued = 0;
    var retried = 0;
    await pump(
      tester,
      availabilityMessage: 'Could not load payment assets. Try again.',
      onContinue: () => continued++,
      onRetry: () => retried++,
    );
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.byKey(_continueKey));
    expect(retried, 1);
    expect(continued, 0);
  });

  testWidgets('preparing a review disables Review and Edit but allows Cancel', (
    tester,
  ) async {
    var cancelled = false;
    await pump(
      tester,
      request: _request(chainId: null),
      selectedChain: 'base',
      isPreparingReview: true,
      onCancel: () => cancelled = true,
    );
    expect(find.text('Preparing payment review…'), findsOneWidget);
    expect(find.text('Preparing…'), findsOneWidget);
    expect(_primary(tester).onPressed, isNull);
    expect(tester.widget<AppButton>(find.byKey(_editKey)).onPressed, isNull);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('payment_request_select_network')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_cancelKey));
    expect(cancelled, isTrue);
    await _capture(tester, isMobile: isMobile, state: 'preparing');
  });

  testWidgets('Edit remains available after a failed review', (tester) async {
    var edited = false;
    await pump(
      tester,
      availabilityMessage:
          'Payment review could not be prepared. Try again or edit the payment.',
      onEdit: () => edited = true,
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.byKey(_editKey));
    expect(edited, isTrue);
    await _capture(tester, isMobile: isMobile, state: 'review-failed');
  });

  testWidgets(
    'long requester details stay separate and leave actions visible',
    (tester) async {
      final note = List.filled(50, 'Please pay this invoice.').join(' ');
      await pump(
        tester,
        viewport: const Size(320, 600),
        request: _request(label: 'Merchant supplied label', message: note),
        availabilityMessage: 'Could not load payment assets. Try again.',
      );
      expect(find.text('Requester'), findsOneWidget);
      expect(find.text('Merchant supplied label'), findsOneWidget);
      expect(find.text(note), findsNothing);
      expect(find.text(kPaymentRequestRequesterTooltip), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('payment_request_requester_help')),
      );
      await tester.pumpAndSettle();
      expect(find.text(kPaymentRequestRequesterTooltip), findsOneWidget);
      expect(find.text(note), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('payment_request_requester_toggle')),
      );
      await tester.tap(
        find.byKey(const ValueKey('payment_request_requester_toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Note from requester'), findsOneWidget);
      final noteScroll = tester.widget<SingleChildScrollView>(
        find.byKey(kPaymentRequestRequesterNoteScrollViewKey),
      );
      expect(noteScroll.controller!.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(_continueKey)).bottom, lessThan(600));
      expect(tester.getRect(find.byKey(_cancelKey)).bottom, lessThan(600));
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('cross_chain_payment_request_status')),
            )
            .bottom,
        lessThan(tester.getRect(find.byKey(_continueKey)).top),
      );
      expect(find.text(note), findsOneWidget);
      await _capture(tester, isMobile: isMobile, state: 'long-requester');
    },
  );

  testWidgets('captures a representative reviewed request', (tester) async {
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<void> captureHover(Key key, String state) async {
      await mouse.moveTo(tester.getCenter(find.byKey(key)));
      await tester.pumpAndSettle();
      await _capture(tester, isMobile: isMobile, state: state);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    }

    await pump(tester);
    await _capture(tester, isMobile: isMobile, state: 'ready');
    await captureHover(
      const ValueKey('payment_request_show_address'),
      'address-hover',
    );
    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _capture(tester, isMobile: isMobile, state: 'address-expanded');
    await captureHover(
      const ValueKey('payment_request_show_address'),
      'address-expanded-hover',
    );
    await tester.tap(find.text('Hide full address'));
    await tester.pumpAndSettle();
    await pump(tester, theme: AppThemeData.light);
    await _capture(tester, isMobile: isMobile, state: 'ready-light');
    await captureHover(
      const ValueKey('payment_request_show_address'),
      'address-hover-light',
    );
    await pump(
      tester,
      request: _request(label: 'Coffee corner', message: 'Order 1042'),
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, isMobile: isMobile, state: 'requester');
    await captureHover(
      const ValueKey('payment_request_requester_toggle'),
      'requester-hover',
    );
    await pump(
      tester,
      request: _request(label: 'Coffee corner', message: 'Order 1042'),
      theme: AppThemeData.light,
    );
    await _capture(tester, isMobile: isMobile, state: 'requester-light');
  });

  testWidgets('asset identity follows the resolved network and native asset', (
    tester,
  ) async {
    await pump(tester);
    final assetIconFinder = find.byKey(
      const ValueKey('payment_request_asset_icon'),
    );
    final baseIcon = tester.widget<SwapAssetIcon>(assetIconFinder);
    expect(baseIcon.asset, _baseUsdc);
    expect(baseIcon.showChainBadge, isTrue);

    const mint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
    final solUsdc = SwapAsset.live(
      assetId: 'sol-usdc',
      symbol: 'USDC',
      blockchain: 'sol',
      decimals: 6,
      contractAddress: mint,
    );
    await pump(
      tester,
      request: CrossChainPaymentRequest(
        id: 'sol-request',
        rawUri: 'solana:recipient?amount=25&spl-token=$mint',
        address: 'So11111111111111111111111111111111111111112',
        isEvm: false,
        chain: 'sol',
        contractAddress: mint,
        amount: PaymentRequestAmount.display('25'),
      ),
      resolution: PaymentRequestResolution(asset: solUsdc, amountText: '25'),
    );
    expect(tester.widget<SwapAssetIcon>(assetIconFinder).asset, solUsdc);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('Base'), findsNothing);
    await _capture(tester, isMobile: isMobile, state: 'solana-usdc');
    expect(find.text('Token details'), findsNothing);
    expect(find.text(mint), findsNothing);

    await pump(
      tester,
      viewport: const Size(320, 600),
      request: CrossChainPaymentRequest(
        id: 'btc-request',
        rawUri: 'bitcoin:recipient?amount=0.00123456',
        address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
        isEvm: false,
        chain: 'btc',
        amount: PaymentRequestAmount.display('0.00123456'),
      ),
      resolution: const PaymentRequestResolution(
        asset: SwapAsset.btc,
        amountText: '0.00123456',
      ),
      estimatedZecAmount: 1.23456,
    );
    expect(find.text('0.00123456'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(
      tester.widget<SwapAssetIcon>(assetIconFinder).showChainBadge,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('payment_request_show_token')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, isMobile: isMobile, state: 'bitcoin-narrow');
  });
}

Future<void> _capture(
  WidgetTester tester, {
  required bool isMobile,
  required String state,
}) async {
  const captureDirectory = String.fromEnvironment('VIZOR_CAPTURE_DIR');
  if (captureDirectory.isEmpty) return;
  final context = tester.element(find.byKey(_captureKey));
  final imagePaths = <String>{
    for (final icon in tester.widgetList<SwapAssetIcon>(
      find.byType(SwapAssetIcon),
    )) ...[
      icon.asset.tokenIconAsset,
      if (icon.showChainBadge) icon.asset.chainIconAsset,
    ],
  };
  await tester.runAsync(() async {
    await Future.wait([
      for (final path in imagePaths) precacheImage(AssetImage(path), context),
    ]);
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '$captureDirectory/cross-chain-payment-${isMobile ? 'mobile' : 'desktop'}-$state.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

AppButton _primary(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(_continueKey));

CrossChainPaymentRequest _request({
  String? chainId = '8453',
  bool includeAmount = true,
  String? label,
  String? message,
}) => CrossChainPaymentRequest(
  id: 'request',
  rawUri:
      'ethereum:$_contract@8453/transfer?address=$_recipient&uint256=25000000',
  address: _recipient,
  isEvm: true,
  chainId: chainId,
  contractAddress: _contract,
  amount: includeAmount ? PaymentRequestAmount.atomicHex('0x17d7840') : null,
  label: label,
  message: message,
);
