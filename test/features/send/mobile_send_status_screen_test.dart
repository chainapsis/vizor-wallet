@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _address =
    'u1l8xunezsvhq8fgzfl7404m450nwnd76zshe7f5dxv5z3w4gthawuwukdn5aalh6g'
    '5wfshmrjmd5gh';
const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
const _displayTxid =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

String _displayOrderToProtocolTxid(String txid) {
  final bytes = <String>[
    for (var index = 0; index < txid.length; index += 2)
      txid.substring(index, index + 2),
  ];
  return bytes.reversed.join();
}

final _args = SendReviewArgs(
  proposalId: BigInt.from(1),
  sendFlowId: 'flow-1',
  proposalAccountUuid: 'account-1',
  address: _address,
  addressType: 'unified',
  amountZatoshi: BigInt.from(12312000000),
  feeZatoshi: BigInt.from(15000),
  needsSaplingParams: false,
  memo: 'thanks!',
);

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return const ZecMarketData(usdPrice: 70);
  }
}

Widget _app({
  required MobileSendBroadcastRunner broadcastRunner,
  SendReviewArgs? args,
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccounts = const {},
}) {
  return ProviderScope(
    overrides: [
      swapFeatureEnabledProvider.overrideWithValue(true),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(contacts),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
    ],
    child: MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileSendStatusScreen(
          args: args ?? _args,
          broadcastRunner: broadcastRunner,
        ),
      ),
    ),
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([this._contacts = const []]);

  final List<AddressBookContact> _contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => _contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

bool _statusRouteCanPop(WidgetTester tester) {
  final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
  return popScope.canPop;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('broadcast success updates the integrated send status screen', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(
      _app(
        broadcastRunner:
            ({
              required ref,
              required args,
              required l10n,
              keystone,
              required confirmSaplingParamsDownload,
              shouldAbort,
            }) => broadcast.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_send_status_sending')), findsOne);
    expect(_statusRouteCanPop(tester), isFalse);
    expect(find.text('Sending...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text(r'$8.62K'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Shielded address'), findsNothing);
    expect(find.text('Unified address'), findsNothing);

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: _displayTxid,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_send_status_succeeded')),
      findsOne,
    );
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(_statusRouteCanPop(tester), isTrue);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_send_status_txid')), findsOne);
    final protocolTxid = _displayOrderToProtocolTxid(_displayTxid);
    final truncatedTxid =
        '${protocolTxid.substring(0, 8)}...'
        '${protocolTxid.substring(protocolTxid.length - 8)}';
    expect(find.text(protocolTxid), findsNothing);
    expect(find.text(truncatedTxid), findsOneWidget);
    final txidText = tester.widget<Text>(find.text(truncatedTxid));
    expect(txidText.maxLines, 1);
    expect(txidText.overflow, TextOverflow.ellipsis);
    expect(find.text('0.00015 ZEC'), findsOneWidget);
  });

  testWidgets('TEX recipient stays distinct from transparent on status', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(
      _app(
        args: SendReviewArgs(
          proposalId: _args.proposalId,
          sendFlowId: _args.sendFlowId,
          proposalAccountUuid: _args.proposalAccountUuid,
          address: _texAddress,
          addressType: 'tex',
          amountZatoshi: _args.amountZatoshi,
          feeZatoshi: _args.feeZatoshi,
          needsSaplingParams: _args.needsSaplingParams,
        ),
        broadcastRunner:
            ({
              required ref,
              required args,
              required l10n,
              keystone,
              required confirmSaplingParamsDownload,
              shouldAbort,
            }) => broadcast.future,
      ),
    );
    await tester.pump();

    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: _displayTxid,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
  });

  testWidgets('failed status allows route pop after broadcast finishes', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(
      _app(
        broadcastRunner:
            ({
              required ref,
              required args,
              required l10n,
              keystone,
              required confirmSaplingParamsDownload,
              shouldAbort,
            }) => broadcast.future,
      ),
    );
    await tester.pump();

    expect(_statusRouteCanPop(tester), isFalse);

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.failed,
        proposalConsumed: true,
        error: 'failed',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_send_status_failed')), findsOne);
    expect(find.text('Send failed'), findsOneWidget);
    expect(_statusRouteCanPop(tester), isTrue);
  });

  testWidgets(
    'recipient saved as a contact shows the name + avatar on status',
    (tester) async {
      final broadcast = Completer<SendBroadcastOutcome>();
      await tester.pumpWidget(
        _app(
          contacts: [
            AddressBookContact(
              id: 'contact-1',
              label: 'Alice',
              network: AddressBookNetwork.zcash,
              address: _address,
              profilePictureId: kDefaultProfilePictureId,
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          ],
          broadcastRunner:
              ({
                required ref,
                required args,
                required l10n,
                keystone,
                required confirmSaplingParamsDownload,
                shouldAbort,
              }) => broadcast.future,
        ),
      );
      // The sending phase shows an infinite loader, so pumpAndSettle would
      // time out here — pump a couple of frames to let the addressBook /
      // ownAccountAddresses futures resolve instead.
      await tester.pump();
      await tester.pump();

      broadcast.complete(
        const SendBroadcastOutcome(
          phase: SendBroadcastPhase.succeeded,
          proposalConsumed: true,
          txid: _displayTxid,
        ),
      );
      // Succeeded state has no infinite spinner, so settling is safe and lets
      // the address-book contact resolve into the To row.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mobile_send_status_succeeded')),
        findsOne,
      );
      // The To headline becomes the contact name with an avatar leading; the
      // truncated address is demoted to the pool strip below.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(AppProfilePicture), findsOneWidget);
      final truncatedAddress =
          '${_address.substring(0, 6)} ... '
          '${_address.substring(_address.length - 5)}';
      expect(find.text(truncatedAddress), findsOneWidget);
    },
  );

  testWidgets('tapping the tx fee value opens the fee info sheet', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(
      _app(
        broadcastRunner:
            ({
              required ref,
              required args,
              required l10n,
              keystone,
              required confirmSaplingParamsDownload,
              shouldAbort,
            }) => broadcast.future,
      ),
    );
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: _displayTxid,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_send_status_succeeded')),
      findsOne,
    );
    expect(find.text('0.00015 ZEC'), findsOneWidget);
    expect(find.textContaining('ZIP 317'), findsNothing);

    // The fee value wraps the help icon in a tap target wired to the shared
    // fee-info bottom sheet.
    await tester.tap(find.text('0.00015 ZEC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ZIP 317'), findsOneWidget);
  });
}
