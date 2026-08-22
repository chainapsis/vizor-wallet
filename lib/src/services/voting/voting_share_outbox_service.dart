import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/layout/app_form_factor.dart';

/// Dart wrapper over the iOS background voting-share outbox
/// (`com.zcash.wallet/background_voting`).
///
/// The native lane may only GET share-status and POST exact staged payloads
/// to helper servers; it never reads wallet or sidecar state. The foreground
/// stages pre-rendered recovery bodies here after every tracking pass
/// (restage-is-truth: `prune: true` replaces the round's share set), and
/// reconciles the lane's receipts into the voting sidecar on the next open.
///
/// Every method is best-effort: the foreground share-tracking restorer is the
/// primary recovery path, so channel failures are logged and swallowed. On
/// non-iOS platforms (and on desktop) the service is a no-op.
class VotingShareOutboxService {
  VotingShareOutboxService({MethodChannel? channel, bool? supported})
    : _channel =
          channel ?? const MethodChannel('com.zcash.wallet/background_voting'),
      _supported =
          supported ??
          (kAppFormFactor == AppFormFactor.mobile &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.iOS);

  final MethodChannel _channel;
  final bool _supported;

  bool get isSupported => _supported;

  /// Stages the current unconfirmed share set of one round. With
  /// [prune] the native store replaces the round's shares (dropping ones the
  /// foreground already confirmed). Returns the per-share payload digests for
  /// the stage→arm handshake, or null when unsupported or failed.
  Future<Map<String, String>?> stageShareRound({
    required String network,
    required String accountUuid,
    required String roundId,
    required BigInt voteEndSeconds,
    required List<String> helperUrls,
    required bool prune,
    required List<VotingShareOutboxShare> shares,
  }) async {
    if (!_supported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'stageShareRound',
        {
          'network': network,
          'accountUuid': accountUuid,
          'roundId': roundId,
          'voteEndSeconds': voteEndSeconds.toInt(),
          'helperUrls': helperUrls,
          'prune': prune,
          'shares': [for (final share in shares) share.toChannelMap()],
        },
      );
      if (result == null) return null;
      return {
        for (final entry in result.entries)
          if (entry.value is String) entry.key: entry.value! as String,
      };
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox stage failed: $error');
      return null;
    }
  }

  /// Marks a staged round armed (digest handshake) and submits the
  /// background task request.
  Future<bool> armShareRound({
    required String roundKey,
    required Map<String, String> expectedDigests,
  }) async {
    if (!_supported) return false;
    try {
      final armed = await _channel.invokeMethod<bool>('armShareRound', {
        'roundKey': roundKey,
        'expectedDigests': expectedDigests,
      });
      return armed ?? false;
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox arm failed: $error');
      return false;
    }
  }

  /// Background outcomes waiting for foreground sidecar reconciliation.
  Future<List<VotingShareOutboxReceipt>> listShareReceipts() async {
    if (!_supported) return const [];
    try {
      final rows = await _channel.invokeListMethod<Object?>(
        'listShareReceipts',
      );
      if (rows == null) return const [];
      return [
        for (final row in rows)
          if (row is Map)
            ?VotingShareOutboxReceipt.fromChannelMap(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
      ];
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox receipt list failed: $error');
      return const [];
    }
  }

  /// Prunes receipts (and their reconciled shares) after the sidecar has
  /// absorbed them. Idempotent; apply-then-ack keeps a crash in between safe.
  Future<bool> ackShareReceipts(List<String> receiptIds) async {
    if (!_supported || receiptIds.isEmpty) return true;
    try {
      final acked = await _channel.invokeMethod<bool>('ackShareReceipts', {
        'receiptIds': receiptIds,
      });
      return acked ?? false;
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox receipt ack failed: $error');
      return false;
    }
  }

  /// Drops every staged round and receipt for one account, stopping any
  /// active run first. Called before account deletion removes the sidecar.
  Future<bool> revokeAccount({
    required String network,
    required String accountUuid,
  }) async {
    if (!_supported) return true;
    try {
      final revoked = await _channel.invokeMethod<bool>('revokeAccount', {
        'network': network,
        'accountUuid': accountUuid,
      });
      return revoked ?? false;
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox account revoke failed: $error');
      return false;
    }
  }

  /// Drops the whole store. Called on wallet reset.
  Future<bool> revokeAll() async {
    if (!_supported) return true;
    try {
      final revoked = await _channel.invokeMethod<bool>('revokeAll');
      return revoked ?? false;
    } catch (error) {
      debugPrint('[zcash] Voting: share outbox revoke failed: $error');
      return false;
    }
  }

  static String roundKey({
    required String network,
    required String accountUuid,
    required String roundId,
  }) => '$network:$accountUuid:$roundId';
}

/// One share as staged into the native store: identity, timing inputs for
/// the crate-mirrored policy, and the exact recovery POST body.
@immutable
class VotingShareOutboxShare {
  const VotingShareOutboxShare({
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.shareIdHex,
    required this.submitAtSeconds,
    required this.createdAtSeconds,
    required this.recoveryBodyJson,
    required this.sentToUrls,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final String shareIdHex;
  final BigInt submitAtSeconds;
  final BigInt createdAtSeconds;
  final String recoveryBodyJson;
  final List<String> sentToUrls;

  Map<String, Object?> toChannelMap() => {
    'bundleIndex': bundleIndex,
    'proposalId': proposalId,
    'shareIndex': shareIndex,
    'shareIdHex': shareIdHex,
    'submitAtSeconds': submitAtSeconds.toInt(),
    'createdAtSeconds': createdAtSeconds.toInt(),
    'recoveryBodyJson': recoveryBodyJson,
    'sentToUrls': sentToUrls,
  };
}

@immutable
class VotingShareOutboxReceipt {
  const VotingShareOutboxReceipt({
    required this.receiptId,
    required this.network,
    required this.accountUuid,
    required this.roundId,
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.outcome,
    this.url,
  });

  final String receiptId;
  final String network;
  final String accountUuid;
  final String roundId;
  final int bundleIndex;
  final int proposalId;
  final int shareIndex;

  /// `confirmed`, `resubmitted`, or `expired`.
  final String outcome;
  final String? url;

  static VotingShareOutboxReceipt? fromChannelMap(Map<String, Object?> map) {
    final receiptId = map['receiptId'];
    final network = map['network'];
    final accountUuid = map['accountUuid'];
    final roundId = map['roundId'];
    final bundleIndex = map['bundleIndex'];
    final proposalId = map['proposalId'];
    final shareIndex = map['shareIndex'];
    final outcome = map['outcome'];
    if (receiptId is! String ||
        network is! String ||
        accountUuid is! String ||
        roundId is! String ||
        bundleIndex is! int ||
        proposalId is! int ||
        shareIndex is! int ||
        outcome is! String) {
      return null;
    }
    final url = map['url'];
    return VotingShareOutboxReceipt(
      receiptId: receiptId,
      network: network,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      outcome: outcome,
      url: url is String ? url : null,
    );
  }
}
