@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

const _address =
    'u1l8xunezsvhq8fgzfl7404m450nwnd76zshe7f5dxv5z3w4gthawuwukdn5aalh6g'
    '5wfshmrjmd5gh';
const _displayTxid =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

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

Widget _app({required MobileSendBroadcastRunner broadcastRunner}) {
  return ProviderScope(
    overrides: [
      swapFeatureEnabledProvider.overrideWithValue(true),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileSendStatusScreen(
          args: _args,
          broadcastRunner: broadcastRunner,
        ),
      ),
    ),
  );
}

void main() {
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
              keystone,
              required confirmSaplingParamsDownload,
              shouldAbort,
            }) => broadcast.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_send_status_sending')), findsOne);
    expect(find.text('Sending...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text(r'$8.62K'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);

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
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_send_status_txid')), findsOne);
    expect(find.text('0.00015 ZEC'), findsOneWidget);
  });
}
