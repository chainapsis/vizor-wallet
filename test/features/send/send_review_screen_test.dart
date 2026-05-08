import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final tickerLower = kZcashDefaultCurrencyTicker.toLowerCase();

  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  testWidgets('centers receipt and send button as one preview stack', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(_reviewArgs(addressType: 'unified', memo: _longMemo)),
    );
    await tester.pump();

    final receiptTop = tester.getTopLeft(_receiptMaskFinder()).dy;
    final buttonTop = tester
        .getTopLeft(find.widgetWithText(AppButton, 'Send'))
        .dy;

    expect(buttonTop - receiptTop, moreOrLessEquals(420));

    final amountText = tester.widget<Text>(find.text('15.12 $tickerLower'));
    expect(amountText.style?.fontFamily, AppTypography.displayLarge.fontFamily);
    expect(amountText.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(amountText.style?.height, AppTypography.displayLarge.height);
    expect(
      amountText.style?.letterSpacing,
      AppTypography.displayLarge.letterSpacing,
    );
  });

  testWidgets('transparent preview uses transparent balance badge', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(_reviewArgs(addressType: 'transparent')),
    );
    await tester.pump();

    final transparentIcon = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .singleWhere((icon) => icon.name == AppIcons.transparentBalance);

    expect(transparentIcon.size, 20);
    expect(transparentIcon.color, AppThemeData.light.colors.icon.muted);
    expect(find.text('Transparent'), findsOneWidget);
  });

  testWidgets('shortens recipient address with Figma-style middle ellipsis', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(_reviewArgs(addressType: 'unified', memo: _longMemo)),
    );
    await tester.pump();

    final addressText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) => widget.text.toPlainText().contains('kwn3gk64h6dfe...'),
        );

    expect(
      addressText.text.toPlainText(),
      'u1tvg4akwn3gk64h6dfe...\n5j3eds7qfhzek6scgcn8fh5',
    );
    expect(addressText.text.toPlainText(), isNot(contains('000000')));

    final rootSpan = addressText.text as TextSpan;
    final spans = rootSpan.children!.cast<TextSpan>();
    expect(
      spans.first.style?.color,
      AppThemeData.light.colors.text.brandCrimson,
    );
    expect(
      spans.last.style?.color,
      AppThemeData.light.colors.text.brandCrimson,
    );
  });

  testWidgets('renders defensive short recipient address without range error', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(addressType: 'sapling', address: 'shortaddr123'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final addressText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere((widget) => widget.text.toPlainText() == 'shortaddr123');
    expect(addressText.text.toPlainText(), 'shortaddr123');
  });

  testWidgets('message expand toggles between truncated and full message', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(addressType: 'sapling', memo: _veryLongMemo),
      ),
    );
    await tester.pump();

    expect(find.text('Expand'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_veryLongMemo)).maxLines, 3);

    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_veryLongMemo)).maxLines, isNull);
  });

  testWidgets('shielded preview uses success-colored shield badge', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(_reviewArgs(addressType: 'sapling', memo: _longMemo)),
    );
    await tester.pump();

    final badgeText = tester.widget<Text>(find.text('Shielded'));
    expect(badgeText.style?.color, AppThemeData.light.colors.text.success);

    final shieldIcon = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .singleWhere((icon) => icon.name == AppIcons.shieldKeyhole);
    expect(shieldIcon.size, 20);
    expect(shieldIcon.color, AppThemeData.light.colors.icon.success);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _sendReviewHarness(SendReviewArgs args) {
  final router = GoRouter(
    initialLocation: '/send/review',
    routes: [
      GoRoute(
        path: '/send/review',
        builder: (_, _) => SendReviewScreen(args: args),
      ),
      GoRoute(path: '/send/status', builder: (_, _) => const SizedBox.shrink()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

SendReviewArgs _reviewArgs({
  required String addressType,
  String? memo,
  String address = _longAddress,
}) {
  return SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'test-send-flow',
    proposalAccountUuid: 'test-account',
    address: address,
    addressType: addressType,
    amountZatoshi: BigInt.from(1512000000),
    feeZatoshi: BigInt.from(12000),
    needsSaplingParams: false,
    memo: memo,
  );
}

Finder _receiptMaskFinder() {
  return find.byWidgetPredicate((widget) {
    final image = widget is Image ? widget.image : null;
    return image is AssetImage &&
        image.assetName == 'assets/illustrations/send_review_receipt_mask.png';
  });
}

const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs.';

const _longAddress =
    'u1tvg4akwn3gk64h6dfe0000000000000000005j3eds7qfhzek6scgcn8fh5';

const _veryLongMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin. This message should be visible after '
    'the preview expands.';

class _RustApiFake implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
