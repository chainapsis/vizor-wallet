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
}) {
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
          args: args ?? _args,
          broadcastRunner: broadcastRunner,
        ),
      ),
    ),
  );
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
}
