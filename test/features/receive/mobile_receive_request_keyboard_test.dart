@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sticky_bottom_action.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_memo_sheet.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_request_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _address = 'u1tvg2412a23kshieldedaddressk64123hhq6d';
const _memo = 'QA_keyboard_check';
const _requestUri = 'zcash:$_address?amount=1&memo=UUFfa2V5Ym9hcmRfY2hlY2s';

const _account = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Test account',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: _address,
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: _account,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _ReceiveAddresses implements ReceiveAddressService {
  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => currentShieldedAddress ?? _address;

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async => 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async =>
      _address;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({double textScale = 1}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
    receiveAddressServiceProvider.overrideWithValue(_ReceiveAddresses()),
    zecLiveUsdUnitPriceProvider.overrideWithValue(70),
  ],
  child: MaterialApp.router(
    localizationsDelegates: appLocalizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppTheme(
        data: AppThemeData.dark,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child!,
        ),
      ),
    ),
    routerConfig: GoRouter(
      initialLocation: '/receive',
      routes: [
        GoRoute(
          path: '/receive',
          builder: (_, _) => const MobileReceiveScreen(),
        ),
        GoRoute(
          path: kReceiveRequestPath,
          builder: (_, state) =>
              MobileReceiveRequestScreen(address: state.extra! as String),
        ),
      ],
    ),
  ),
);

const _screenHeight = 823.4667;

/// The compose step's scrolling fields, above the docked Create button.
Finder get _fields => find.byKey(const ValueKey('request_compose_fields'));

Future<void> _pumpPhone(
  WidgetTester tester, {
  Size size = const Size(384, _screenHeight),
  double textScale = 1,
}) async {
  // Samsung SM-S908U: 384×823dp at font scale 1. The native Gboard report
  // measured 332.09dp of IME inset; its view padding is separate from the
  // top status-bar padding the page's SafeArea takes.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 26.6667);
  tester.view.viewPadding = const FakeViewPadding(
    top: 26.6667,
    bottom: 14.9333,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(textScale: textScale));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Opens the request page from Receive and types an amount, with the
/// keyboard raised to [keyboardInset].
Future<void> _openRequest(
  WidgetTester tester, {
  double keyboardInset = 332.0889,
}) async {
  final requestEntry = find.byKey(const ValueKey('mobile_receive_request'));
  await tester.scrollUntilVisible(
    requestEntry,
    120,
    scrollable: find
        .descendant(
          of: find.byType(MobileReceiveScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _settle(tester);
  await tester.tap(requestEntry);
  await _settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('request_amount_input')),
    '1',
  );
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Types [message] into the message sheet and saves it.
Future<void> _addMessage(WidgetTester tester, String message) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.view.viewInsets = const FakeViewPadding();
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('request_message_row')));
  await _settle(tester);
  expect(find.byType(MobileMemoSheet), findsOneWidget);
  await tester.enterText(
    find.byKey(const ValueKey('mobile_send_memo_editable')),
    message,
  );
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('mobile_send_memo_save')));
  await _settle(tester);
  expect(find.byType(MobileMemoSheet), findsNothing);
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('request_create_button')));
  await tester.idle();
  tester.view.viewInsets = const FakeViewPadding();
  await _settle(tester);
}

String _qrData(WidgetTester tester) =>
    tester.widget<RequestQrSurface>(find.byType(RequestQrSurface)).data;

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final (name, size, scale, inset) in [
    ('Samsung', const Size(384, _screenHeight), 1.0, 358.4),
    ('Gboard', const Size(384, _screenHeight), 1.0, 332.0889),
    ('large text', const Size(320, 700), 1.5, 256.0),
    ('short phone', const Size(320, 568), 1.0, 256.0),
    ('keyboard closed', const Size(384, _screenHeight), 1.0, 0.0),
  ]) {
    testWidgets(
      'the create button stays docked above the keyboard with $name',
      (tester) async {
        await _pumpPhone(tester, size: size, textScale: scale);
        await _openRequest(tester, keyboardInset: inset);
        expect(tester.takeException(), isNull);

        // The action is whole, at the page's footer gap above the keyboard,
        // and the fields scroll above it rather than under it.
        final button = find.byKey(const ValueKey('request_create_button'));
        final buttonRect = tester.getRect(button);
        expect(buttonRect.height, AppButtonSizing.largeHeight);
        expect(buttonRect.bottom, size.height - inset - kMobileFooterGap);
        expect(buttonRect.top - tester.getRect(_fields).bottom, AppSpacing.s);

        await tester.tapAt(buttonRect.center);
        await tester.idle();
        expect(tester.testTextInput.isVisible, isFalse);
        tester.view.viewInsets = const FakeViewPadding();
        await _settle(tester);
        expect(_qrData(tester), 'zcash:$_address?amount=1');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('keeps the button in place through keyboard transitions', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await _openRequest(tester, keyboardInset: 0);
    final button = find.byKey(const ValueKey('request_create_button'));

    for (final inset in [0.0, 332.0889, 358.4, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await _settle(tester);
      final buttonRect = tester.getRect(button);
      expect(buttonRect.height, AppButtonSizing.largeHeight);
      expect(buttonRect.top - tester.getRect(_fields).bottom, AppSpacing.s);
      expect(_screenHeight - inset - buttonRect.bottom, kMobileFooterGap);
      expect(tester.takeException(), isNull);
    }

    await _create(tester);
    expect(_qrData(tester), 'zcash:$_address?amount=1');
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('a message from the sheet travels in the request', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await _openRequest(tester);
    await _addMessage(tester, _memo);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('request_message_preview')))
          .data,
      _memo,
    );
    await _create(tester);
    expect(_qrData(tester), _requestUri);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('an over-limit message cannot be saved', (tester) async {
    await _pumpPhone(tester);
    await _openRequest(tester, keyboardInset: 0);
    await tester.tap(find.byKey(const ValueKey('request_message_row')));
    await _settle(tester);
    final field = find.byKey(const ValueKey('mobile_send_memo_editable'));
    final valid = '${'가' * 170}ab';
    for (final message in ['a' * 512, valid]) {
      await tester.enterText(field, '$message!');
      await _settle(tester);
      expect(find.text('513/512'), findsOneWidget);
      expect(find.text('Message is too long'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('mobile_send_memo_save')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(field, message);
      await _settle(tester);
      expect(find.text('512/512'), findsOneWidget);
      expect(find.text('Message is too long'), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_save')));
    await _settle(tester);
    await _create(tester);
    expect(
      _qrData(tester),
      ZecRequestView(
        address: _address,
        amountZec: '1',
        messageText: valid,
      ).qrData,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('long messages survive creation', (tester) async {
    await _pumpPhone(tester);
    await _openRequest(tester);
    final message = List.generate(12, (i) => 'Memo line $i').join('\n');
    await _addMessage(tester, message);
    await _create(tester);
    expect(
      _qrData(tester),
      ZecRequestView(
        address: _address,
        amountZec: '1',
        messageText: message,
      ).qrData,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'scaled memo drag target and request actions remain usable ($scale)',
      (tester) async {
        await _pumpPhone(tester, size: const Size(360, 800), textScale: scale);
        await _openRequest(tester, keyboardInset: 0);
        await tester.enterText(
          find.byKey(const ValueKey('request_amount_input')),
          '1234567.12345678',
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('request_amount_input')),
          '1',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(
          find.byKey(const ValueKey('request_message_row')),
        );
        await tester.tap(find.byKey(const ValueKey('request_message_row')));
        await _settle(tester);
        final field = find.byKey(const ValueKey('mobile_send_memo_editable'));
        final message = List.generate(
          12,
          (i) => 'Memo line $i with more text',
        ).join('\n');
        await tester.enterText(field, message);
        await _settle(tester);
        final bar = find.byKey(const ValueKey('mobile_send_memo_scrollbar'));
        await tester.ensureVisible(bar);
        final hit = tester.getRect(bar);
        final editable = tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        final scrolling = editable.scrollController!;
        scrolling.jumpTo(0);
        await tester.pump();
        final thumb = tester.getRect(
          find.byKey(const ValueKey('mobile_send_memo_scrollbar_thumb')),
        );
        final drag = await tester.startGesture(
          Offset(hit.left + 2, thumb.center.dy),
        );
        await drag.moveBy(const Offset(0, 45));
        await drag.up();
        await tester.pump();
        expect(scrolling.offset, greaterThan(0));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _settle(tester);
        final save = find.byKey(const ValueKey('mobile_send_memo_save'));
        await tester.ensureVisible(save);
        await _settle(tester);
        expect(tester.getRect(save).bottom, lessThanOrEqualTo(500));
        await tester.tap(save);
        await _settle(tester);
        expect(find.byType(MobileMemoSheet), findsNothing);
        tester.view.viewInsets = const FakeViewPadding();
        await _settle(tester);
        await _create(tester);
        expect(
          _qrData(tester),
          ZecRequestView(
            address: _address,
            amountZec: '1',
            messageText: message,
          ).qrData,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
