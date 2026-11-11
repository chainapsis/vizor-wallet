import '../../rust/api/sync.dart' show BroadcastNotice;
import '../l10n/l10n.dart';

/// The display-language text of a broadcast result's notices.
///
/// Rust's English `message` is the same sentences, so English shows exactly
/// what Rust wrote (`test/fixtures/broadcast_notices_en.json` pins both).
/// Returns null when there are no notices or one has a kind this build does
/// not know; the caller then shows `message` as before.
String? broadcastNoticeText(
  AppLocalizations l10n,
  List<BroadcastNotice> notices,
) {
  if (notices.isEmpty) return null;
  final sentences = <String>[];
  for (final notice in notices) {
    final sentence = _sentence(l10n, notice);
    if (sentence == null) return null;
    sentences.add(sentence);
  }
  final text = StringBuffer();
  for (final sentence in sentences) {
    // Rust puts one space between sentences. A full-width stop already ends
    // a Chinese sentence.
    if (text.isNotEmpty && !text.toString().endsWith('。')) text.write(' ');
    text.write(sentence);
  }
  return text.toString();
}

/// [broadcastNoticeText], falling back to Rust's English [message].
String? broadcastResultText(
  AppLocalizations l10n, {
  required List<BroadcastNotice> notices,
  required String? message,
}) => broadcastNoticeText(l10n, notices) ?? message;

String? _sentence(AppLocalizations l10n, BroadcastNotice notice) {
  final index = '${notice.index ?? 0}';
  final total = '${notice.total ?? 0}';
  final txid = notice.txid ?? '';
  final detail = notice.detail ?? '';
  return switch (notice.kind) {
    'text' => detail,
    'transaction_unknown' => l10n.broadcastNoticeTransactionUnknown(
      index,
      total,
      detail,
    ),
    'transaction_rejected' => l10n.broadcastNoticeTransactionRejected(
      index,
      total,
      detail,
    ),
    'route_unavailable' => l10n.broadcastNoticeRouteUnavailable(
      index,
      total,
      detail,
    ),
    'expired' => l10n.broadcastNoticeExpired(
      txid,
      '${notice.expiryHeight ?? 0}',
      '${notice.chainHeight ?? BigInt.zero}',
    ),
    'broadcast_storage_failed' => l10n.broadcastNoticeBroadcastStorageFailed(
      txid,
      detail,
    ),
    'response_unavailable' => l10n.broadcastNoticeResponseUnavailable(
      txid,
      detail,
    ),
    'database_unavailable' => l10n.broadcastNoticeDatabaseUnavailable(detail),
    'raw_transaction_unavailable' =>
      l10n.broadcastNoticeRawTransactionUnavailable(txid, detail),
    'broadcast_failed' => l10n.broadcastNoticeBroadcastFailed(
      index,
      total,
      txid,
      detail,
    ),
    'stored_locally' => l10n.broadcastNoticeStoredLocally,
    'storage_failed' => l10n.broadcastNoticeStorageFailed(detail),
    'retention_failed' => l10n.broadcastNoticeRetentionFailed(detail),
    'retrying_locally' => l10n.broadcastNoticeRetryingLocally,
    'tracking_failed' => l10n.broadcastNoticeTrackingFailed(detail),
    _ => null,
  };
}

/// Notices as JSON, for records that store them (swap activity).
List<Map<String, Object?>> broadcastNoticesToJson(
  List<BroadcastNotice> notices,
) => [
  for (final notice in notices)
    {
      'kind': notice.kind,
      if (notice.index != null) 'index': notice.index,
      if (notice.total != null) 'total': notice.total,
      if (notice.txid != null) 'txid': notice.txid,
      if (notice.detail != null) 'detail': notice.detail,
      if (notice.expiryHeight != null) 'expiry_height': notice.expiryHeight,
      if (notice.chainHeight != null)
        'chain_height': notice.chainHeight.toString(),
    },
];

/// Reads [broadcastNoticesToJson] and Rust's serde form. Returns null for
/// anything malformed, so the record falls back to its stored text.
List<BroadcastNotice>? broadcastNoticesFromJson(Object? json) {
  if (json is! List || json.isEmpty) return null;
  final notices = <BroadcastNotice>[];
  for (final item in json) {
    if (item is! Map) return null;
    final kind = item['kind'];
    if (kind is! String) return null;
    final chainHeight = switch (item['chain_height']) {
      final String text => BigInt.tryParse(text),
      final int value => BigInt.from(value),
      _ => null,
    };
    notices.add(
      BroadcastNotice(
        kind: kind,
        index: _int(item['index']),
        total: _int(item['total']),
        txid: _string(item['txid']),
        detail: _string(item['detail']),
        expiryHeight: _int(item['expiry_height']),
        chainHeight: chainHeight,
      ),
    );
  }
  return notices;
}

int? _int(Object? value) => value is int ? value : null;

String? _string(Object? value) => value is String ? value : null;
