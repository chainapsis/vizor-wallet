import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/core/zcash/broadcast_notice_text.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' show BroadcastNotice;

import '../../tool/l10n/korean_arb.dart' show wordJoiner;

/// Shared with `rust/src/wallet/sync/broadcast_notice.rs`, whose formatter
/// writes the same English into each broadcast result's `message`.
List<({List<BroadcastNotice> notices, String message})> _fixtures() {
  final json = jsonDecode(
    File('test/fixtures/broadcast_notices_en.json').readAsStringSync(),
  );
  return [
    for (final entry in (json as List).cast<Map<String, dynamic>>())
      (
        notices: broadcastNoticesFromJson(entry['notices'])!,
        message: entry['message'] as String,
      ),
  ];
}

String _withoutJoiners(String text) => text.replaceAll(wordJoiner, '');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));
  final zh = lookupAppLocalizations(const Locale('zh'));

  test('English is exactly the message Rust writes', () {
    for (final fixture in _fixtures()) {
      expect(broadcastNoticeText(en, fixture.notices), fixture.message);
    }
  });

  test('Korean and Chinese translate every sentence and keep its values', () {
    for (final fixture in _fixtures()) {
      for (final l10n in [ko, zh]) {
        final text = _withoutJoiners(
          broadcastNoticeText(l10n, fixture.notices)!,
        );
        final onlyRustText = fixture.notices.every(
          (notice) => notice.kind == 'text',
        );
        if (!onlyRustText) expect(text, isNot(fixture.message));
        for (final notice in fixture.notices) {
          for (final value in [
            notice.detail,
            notice.txid,
            notice.expiryHeight?.toString(),
            notice.chainHeight?.toString(),
          ]) {
            if (value != null && value.isNotEmpty) {
              expect(text, contains(value), reason: '${l10n.localeName} $text');
            }
          }
        }
      }
    }
  });

  test('Chinese sentences are not separated by a space after 。', () {
    final text = broadcastNoticeText(zh, const [
      BroadcastNotice(kind: 'storage_failed', detail: 'disk full'),
      BroadcastNotice(kind: 'retention_failed', detail: 'lock busy'),
    ])!;
    expect(text, isNot(contains('。 ')));
  });

  test('an unknown kind falls back to the message', () {
    const notices = [
      BroadcastNotice(kind: 'stored_locally'),
      BroadcastNotice(kind: 'from_a_newer_build'),
    ];
    expect(broadcastNoticeText(ko, notices), isNull);
    expect(
      broadcastResultText(ko, notices: notices, message: 'Rust text'),
      'Rust text',
    );
    expect(
      broadcastResultText(ko, notices: const [], message: 'Rust text'),
      'Rust text',
    );
    expect(broadcastResultText(ko, notices: const [], message: null), isNull);
  });

  test('JSON round-trips and rejects malformed records', () {
    final notices = _fixtures().expand((fixture) => fixture.notices).toList();
    expect(
      broadcastNoticesFromJson(
        jsonDecode(jsonEncode(broadcastNoticesToJson(notices))),
      ),
      notices,
    );
    expect(broadcastNoticesFromJson(null), isNull);
    expect(broadcastNoticesFromJson(const []), isNull);
    expect(broadcastNoticesFromJson('text'), isNull);
    expect(
      broadcastNoticesFromJson(const [
        {'index': 1},
      ]),
      isNull,
    );
  });
}
