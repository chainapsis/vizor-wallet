import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_intent_presentation_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' show BroadcastNotice;

import '../../../tool/l10n/korean_arb.dart' show wordJoiner;
import '../../support/test_l10n.dart';

final _ko = lookupAppLocalizations(const Locale('ko'));

/// Korean as a reader sees it: the shipped strings carry invisible word
/// joiners for line breaking.
String _plain(String text) => text.replaceAll(wordJoiner, '');

const _autoRefreshKo = '최신 상태를 새로고침하지 못했어요.\n계속 시도하고 이 화면을 자동으로 업데이트할게요.';
const _broadcastUnknownKo =
    '거래가 네트워크에 전달됐을 수 있지만 확인 시간이 초과됐어요. 다시 시도하기 전에 활동을 확인해 주세요.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore secureStore;
  late SwapActivityStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStore = AppSecureStore.instance;
    await secureStore.deleteAll();
    store = AppSecureStoreSwapActivityStore(secureStore);
  });

  tearDown(() async {
    await secureStore.deleteAll();
  });

  Future<SwapIntent> loadSingle() async {
    final records = await store.loadRecords(accountUuid: 'account-1');
    return swapIntentsFromRecords(records).single;
  }

  String detailValue(
    AppLocalizations l10n,
    SwapIntent intent,
    SwapStatusDetailKind kind,
  ) {
    final presentation = swapActivityStatusPresentationForIntent(
      l10n,
      const SwapState(
        direction: SwapDirection.zecToExternal,
        amountText: '',
        receiveAmountText: '',
        destinationText: '',
        externalAsset: SwapAsset.usdc,
        reviewVisible: false,
        intents: [],
      ),
      intent,
    );
    return presentation.details.firstWhere((row) => row.kind == kind).value;
  }

  test(
    'a record an earlier build wrote shows its text in English and Korean',
    () async {
      // The shape release/v0.0.63 writes: English text, no codes.
      await secureStore.writeString(
        swapActivityStorageKeyForTest('account-1'),
        jsonEncode({
          'version': 1,
          'records': [
            {
              'id': 't1legacy',
              'provider': 'NEAR Intents',
              'pair': 'ZEC -> USDC',
              'sellAmount': '1.5 ZEC',
              'receiveEstimate': '105 USDC',
              'status': 'processing',
              'nextAction': 'Swap is processing',
              'direction': 'zecToExternal',
              'depositAddress': 't1legacy',
              'depositTxHash': 'legacy-txid',
              'swapFeeText': 'Included in shown rate',
              'minimumReceiveText': 'Not reported',
              'slippageToleranceText': 'Not reported',
              'statusError':
                  "We couldn't refresh the latest status.\n"
                  "We'll keep trying and update this screen automatically.",
              'broadcastNotice':
                  'The transaction may have reached the network, but '
                  'confirmation timed out. Check activity before trying again.',
              'broadcastStatus': 'broadcast_unknown',
              'payMode': false,
              'createdAt': '2026-05-07T10:00:00.000Z',
            },
          ],
        }),
      );

      final intent = await loadSingle();

      expect(
        intent.statusError,
        const SwapFailureMessage(
          SwapFailureOperation.refreshStatus,
          SwapFailureCategory.serviceUnavailable,
        ),
      );
      expect(
        intent.statusError!.text(testL10n),
        "We couldn't refresh the latest status.\n"
        "We'll keep trying and update this screen automatically.",
      );
      expect(_plain(intent.statusError!.text(_ko)), _autoRefreshKo);

      expect(
        intent.broadcastNotice,
        const SwapNotice(SwapNoticeKind.broadcastUnknown),
      );
      expect(
        intent.broadcastNotice!.text(testL10n),
        'The transaction may have reached the network, but confirmation timed '
        'out. Check activity before trying again.',
      );
      expect(_plain(intent.broadcastNotice!.text(_ko)), _broadcastUnknownKo);

      expect(intent.nextAction, SwapNextAction.processing.name);

      expect(
        detailValue(testL10n, intent, SwapStatusDetailKind.swapFee),
        'Included in shown rate',
      );
      expect(
        _plain(detailValue(_ko, intent, SwapStatusDetailKind.swapFee)),
        '표시된 환율에 포함됨',
      );
      expect(
        detailValue(testL10n, intent, SwapStatusDetailKind.guaranteedMinimum),
        'Not reported',
      );
      expect(
        _plain(
          detailValue(_ko, intent, SwapStatusDetailKind.guaranteedMinimum),
        ),
        '보고되지 않음',
      );
    },
  );

  test('text no build coded is shown as stored in every language', () async {
    await secureStore.writeString(
      swapActivityStorageKeyForTest('account-1'),
      jsonEncode([
        {
          'id': 't1rust',
          'provider': 'NEAR Intents',
          'pair': 'ZEC -> USDC',
          'sellAmount': '1.5 ZEC',
          'receiveEstimate': '105 USDC',
          'status': 'processing',
          'nextAction': 'Waiting for the provider',
          'statusError': 'transport error: connection reset by peer',
          'broadcastNotice': 'transport error: connection reset by peer',
        },
      ]),
    );

    final intent = await loadSingle();

    const literal = SwapLiteralMessage(
      'transport error: connection reset by peer',
    );
    expect(intent.statusError, literal);
    expect(intent.broadcastNotice, literal);
    expect(
      intent.statusError!.text(_ko),
      'transport error: connection reset by peer',
    );
    expect(intent.nextAction, 'Waiting for the provider');
  });

  test(
    'a new record stores codes beside the English older builds show',
    () async {
      final intent = SwapIntent(
        id: 't1new',
        pair: 'ZEC -> USDC',
        sellAmount: '1.5 ZEC',
        receiveEstimate: '105 USDC',
        provider: 'NEAR Intents',
        status: SwapIntentStatus.processing,
        nextAction: SwapNextAction.processing.name,
        direction: SwapDirection.zecToExternal,
        depositAddress: 't1new',
        statusError: const SwapFailureMessage(
          SwapFailureOperation.submitDeposit,
          SwapFailureCategory.depositRejected,
        ),
        broadcastNotice: const SwapNotice(SwapNoticeKind.broadcastUnknown),
        broadcastStatus: 'broadcast_unknown',
      );

      await store.saveRecords(
        accountUuid: 'account-1',
        records: [SwapIntentRecord.fromIntent(intent)],
      );

      final raw = jsonDecode(
        (await secureStore.readString(
          swapActivityStorageKeyForTest('account-1'),
        ))!,
      );
      final json = (raw['records'] as List).single as Map<String, dynamic>;
      expect(json['statusErrorCode'], {
        'type': 'failure',
        'operation': 'submitDeposit',
        'category': 'depositRejected',
        'surface': 'swap',
      });
      expect(
        json['statusError'],
        'Deposit transaction was rejected.\n'
        'Check the address, memo, and tx hash.',
      );
      expect(json['broadcastNoticeCode'], {
        'type': 'notice',
        'kind': 'broadcastUnknown',
      });
      expect(
        json['broadcastNotice'],
        'The transaction may have reached the network, but confirmation timed '
        'out. Check activity before trying again.',
      );
      expect(json['nextAction'], 'processing');

      final restored = await loadSingle();
      expect(restored.statusError, intent.statusError);
      expect(restored.broadcastNotice, intent.broadcastNotice);
      expect(
        _plain(restored.statusError!.text(_ko)),
        '입금 거래가 거부됐어요.\n주소, 메모, 거래 해시를 확인해 주세요.',
      );
      expect(_plain(restored.broadcastNotice!.text(_ko)), _broadcastUnknownKo);
    },
  );

  test(
    'a broadcast result stores its notices beside the English Rust wrote',
    () async {
      const english =
          'Transaction 2 of 2 has an unknown broadcast result: deadline '
          'exceeded The accepted-or-ambiguous transaction prefix was stored '
          'locally for recovery.';
      final notice = SwapBroadcastMessage.tryFrom(const [
        BroadcastNotice(
          kind: 'transaction_unknown',
          index: 2,
          total: 2,
          detail: 'deadline exceeded',
        ),
        BroadcastNotice(kind: 'stored_locally'),
      ])!;
      final intent = SwapIntent(
        id: 't1notice',
        pair: 'ZEC -> USDC',
        sellAmount: '1.5 ZEC',
        receiveEstimate: '105 USDC',
        provider: 'NEAR Intents',
        status: SwapIntentStatus.processing,
        nextAction: SwapNextAction.processing.name,
        direction: SwapDirection.zecToExternal,
        depositAddress: 't1notice',
        broadcastNotice: notice,
        broadcastStatus: 'partial_broadcast',
      );
      await store.saveRecords(
        accountUuid: 'account-1',
        records: [SwapIntentRecord.fromIntent(intent)],
      );

      final raw = jsonDecode(
        (await secureStore.readString(
          swapActivityStorageKeyForTest('account-1'),
        ))!,
      );
      final json = (raw['records'] as List).single as Map<String, dynamic>;
      expect(json['broadcastNotice'], english);
      expect(json['broadcastNoticeCode'], {
        'type': 'broadcast',
        'notices': [
          {
            'kind': 'transaction_unknown',
            'index': 2,
            'total': 2,
            'detail': 'deadline exceeded',
          },
          {'kind': 'stored_locally'},
        ],
      });

      final restored = await loadSingle();
      expect(restored.broadcastNotice, notice);
      expect(restored.broadcastNotice!.text(testL10n), english);
      expect(
        _plain(restored.broadcastNotice!.text(_ko)),
        '전체 2건 중 2번째 거래의 전송 결과를 알 수 없어요: deadline exceeded '
        '전송됐거나 전송됐을 수 있는 거래는 복구를 위해 로컬에 저장했어요.',
      );
    },
  );

  test('broadcast notices from a newer build fall back to the text', () async {
    await secureStore.writeString(
      swapActivityStorageKeyForTest('account-1'),
      jsonEncode([
        {
          'id': 't1future',
          'provider': 'NEAR Intents',
          'pair': 'ZEC -> USDC',
          'sellAmount': '1.5 ZEC',
          'receiveEstimate': '105 USDC',
          'status': 'processing',
          'nextAction': 'processing',
          'broadcastNotice': 'A sentence a newer build wrote.',
          'broadcastNoticeCode': {
            'type': 'broadcast',
            'notices': [
              {'kind': 'from_the_future'},
            ],
          },
        },
      ]),
    );

    final intent = await loadSingle();

    expect(
      intent.broadcastNotice,
      const SwapLiteralMessage('A sentence a newer build wrote.'),
    );
  });

  test('a stored code wins over its English text', () async {
    await secureStore.writeString(
      swapActivityStorageKeyForTest('account-1'),
      jsonEncode([
        {
          'id': 't1code',
          'provider': 'NEAR Intents',
          'pair': 'ZEC -> USDC',
          'sellAmount': '1.5 ZEC',
          'receiveEstimate': '105 USDC',
          'status': 'processing',
          'nextAction': 'processing',
          'statusError': 'Copy that a later build reworded.',
          'statusErrorCode': {
            'type': 'failure',
            'operation': 'refreshStatus',
            'category': 'depositNotFound',
            'surface': 'swap',
          },
          // A code this build does not know falls back to the text.
          'broadcastNotice': 'Swap could not be started.\nTry again later.',
          'broadcastNoticeCode': {'type': 'notice', 'kind': 'fromTheFuture'},
        },
      ]),
    );

    final intent = await loadSingle();

    expect(
      intent.statusError,
      const SwapFailureMessage(
        SwapFailureOperation.refreshStatus,
        SwapFailureCategory.depositNotFound,
      ),
    );
    expect(
      intent.broadcastNotice,
      const SwapFailureMessage(
        SwapFailureOperation.start,
        SwapFailureCategory.unknown,
      ),
    );
  });

  test('every legacy text maps to a code that renders it unchanged', () {
    for (final entry in swapLegacyMessagesForTest.entries) {
      expect(entry.value.text(testL10n), entry.key);
      expect(swapMessageFromLegacyText(entry.key), entry.value);
    }
  });

  test('legacy next actions map to their codes', () {
    const legacy = {
      'Send USDC to the one-time deposit address': SwapNextAction.sendDeposit,
      'Send ZEC to the one-time deposit address': SwapNextAction.sendDeposit,
      'Deposit detected': SwapNextAction.depositDetected,
      'Swap is processing': SwapNextAction.processing,
      'Provider returned a status this wallet does not recognize':
          SwapNextAction.unrecognizedStatus,
      'Deposit is below the quoted amount': SwapNextAction.incompleteDeposit,
      'Swap complete': SwapNextAction.complete,
      'Refund sent to your refund address': SwapNextAction.refundSent,
      'Start a fresh quote': SwapNextAction.startFreshQuote,
      'Swap failed': SwapNextAction.failed,
      'Sign and send the ZEC deposit with Ledger.':
          SwapNextAction.signLedgerDeposit,
      'Sign and send the ZEC deposit with Keystone.':
          SwapNextAction.signKeystoneDeposit,
    };
    for (final entry in legacy.entries) {
      expect(SwapNextAction.normalizeStored(entry.key), entry.value.name);
    }
    for (final action in SwapNextAction.values) {
      expect(SwapNextAction.normalizeStored(action.name), action.name);
    }
  });

  test('quote expiry and pending rate are worded at display time', () {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      amount: 1,
      expiryLabel: null,
      quoteExpiresAt: DateTime(2026, 5, 7, 9, 5).toUtc(),
    );
    expect(swapQuoteExpiryText(testL10n, quote), 'Expires 09:05');
    expect(_plain(swapQuoteExpiryText(_ko, quote)), '09:05에 만료');

    final pending = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      amount: 1,
      expiryLabel: null,
    );
    expect(swapQuoteExpiryText(testL10n, pending), 'Quote expiry pending');
    expect(
      swapDetailValueText(testL10n, kSwapRatePendingToken),
      'Rate pending',
    );
    expect(_plain(swapDetailValueText(_ko, kSwapRatePendingToken)), '환율 확인 중');
    expect(swapDetailValueText(_ko, '0.5 USDC'), '0.5 USDC');
  });
}
