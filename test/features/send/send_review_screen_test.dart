import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/features/send/widgets/transaction_receipt_view.dart';
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
    expect(find.text('Tx Fee: 0.00012 ZEC'), findsOneWidget);
  });

  testWidgets('send CTA uses leading action icon', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(_reviewArgs(addressType: 'unified', memo: _longMemo)),
    );
    await tester.pump();

    final sendButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Send'),
    );
    final leadingIcon = sendButton.leading;

    expect(leadingIcon, isA<AppIcon>());
    expect((leadingIcon! as AppIcon).name, AppIcons.plane);
    expect(sendButton.trailing, isNull);
  });

  testWidgets('scales down long receipt amount text', (tester) async {
    const amountText = '123456789.12345678 zec';

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(
          addressType: 'unified',
          amountZatoshi: BigInt.from(12345678912345678),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.text(amountText),
        matching: find.byWidgetPredicate(
          (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark preview uses dark semantic colors', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(addressType: 'transparent'),
        theme: AppThemeData.dark,
      ),
    );
    await tester.pump();

    final sendingLabel = tester.widget<Text>(find.text('Sending'));
    expect(sendingLabel.style?.color, AppThemeData.dark.colors.text.secondary);
    expect(
      _assetImageNames(tester),
      contains('assets/illustrations/send_review_receipt_mask_dark.png'),
    );

    final feeLabel = tester.widget<Text>(find.text('Tx Fee: 0.00012 ZEC'));
    expect(feeLabel.style?.color, AppThemeData.dark.colors.text.accent);

    final transparentIcon = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .singleWhere((icon) => icon.name == AppIcons.transparentBalance);
    expect(transparentIcon.color, AppThemeData.dark.colors.icon.muted);
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

  testWidgets('shows saved recipient label with inline copy action', (
    tester,
  ) async {
    final compactAddress = compactTransactionReceiptSavedAddress(_longAddress);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(addressType: 'unified', memo: _longMemo),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'me', label: 'me', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('me'), findsOneWidget);
    expect(find.text(compactAddress), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(compactAddress)).style?.color,
      AppThemeData.light.colors.text.muted,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Copy',
      ),
      findsNothing,
    );

    final addressRect = tester.getRect(find.text(compactAddress));
    final copyRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.copy &&
            widget.size == 16,
      ),
    );
    final copyGap = copyRect.left - addressRect.right;
    expect(copyGap, greaterThan(0));
    expect(copyGap, lessThanOrEqualTo(AppSpacing.xs));
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

  testWidgets('dark shielded preview uses dark receipt assets', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _sendReviewHarness(
        _reviewArgs(addressType: 'sapling', memo: _longMemo),
        theme: AppThemeData.dark,
      ),
    );
    await tester.pump();

    expect(
      _assetImageNames(tester),
      containsAll(<String>[
        'assets/illustrations/send_review_receipt_mask_dark.png',
        'assets/illustrations/send_review_receipt_pattern_dark.png',
      ]),
    );

    final badgeText = tester.widget<Text>(find.text('Shielded'));
    expect(badgeText.style?.color, AppThemeData.dark.colors.text.success);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _sendReviewHarness(
  SendReviewArgs args, {
  AppThemeData theme = AppThemeData.light,
  AddressBookRepository? addressBookRepository,
}) {
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
      addressBookRepositoryProvider.overrideWithValue(
        addressBookRepository ?? _FakeAddressBookRepository(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: theme, child: child!),
    ),
  );
}

AddressBookContact _contact({
  required String id,
  required String label,
  required String address,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: AddressBookNetwork.zcash,
    address: address,
    profilePictureId: 'knight',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

SendReviewArgs _reviewArgs({
  required String addressType,
  String? memo,
  String address = _longAddress,
  BigInt? amountZatoshi,
}) {
  return SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'test-send-flow',
    proposalAccountUuid: 'test-account',
    address: address,
    addressType: addressType,
    amountZatoshi: amountZatoshi ?? BigInt.from(1512000000),
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

Set<String> _assetImageNames(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((widget) => widget.image)
      .whereType<AssetImage>()
      .map((image) => image.assetName)
      .toSet();
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
