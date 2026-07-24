import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/sync.dart' as rust_sync;
import 'ironwood_migration_phases.dart';
import 'ironwood_migration_presentation.dart';

enum MobileIronwoodMigrationAttentionKind {
  signature,
  continueMigration,
  proof,
  lateBroadcast,
}

class MobileIronwoodMigrationAttention {
  const MobileIronwoodMigrationAttention({
    required this.kind,
    required this.count,
  });

  final MobileIronwoodMigrationAttentionKind kind;
  final int count;
}

MobileIronwoodMigrationAttention? mobileIronwoodMigrationAttention(
  rust_sync.MigrationStatus? status, {
  required int currentHeight,
  required bool isHardware,
}) {
  if (status == null) return null;
  final needsInputCount = status.parts
      .where((part) => part.state == rust_sync.MigrationPartState.needsInput)
      .length;
  if (needsInputCount > 0) {
    return MobileIronwoodMigrationAttention(
      kind: isHardware
          ? MobileIronwoodMigrationAttentionKind.signature
          : MobileIronwoodMigrationAttentionKind.continueMigration,
      count: needsInputCount,
    );
  }
  if (status.phase == kIronwoodMigrationReadyToMigratePhase) {
    final nextActionHeight = status.nextActionHeight;
    if (nextActionHeight == null ||
        currentHeight <= 0 ||
        nextActionHeight <= currentHeight) {
      if (isHardware && status.signedChildPcztCount <= 0) {
        return MobileIronwoodMigrationAttention(
          kind: MobileIronwoodMigrationAttentionKind.signature,
          count: math.max(1, status.totalCount),
        );
      }
      return const MobileIronwoodMigrationAttention(
        kind: MobileIronwoodMigrationAttentionKind.proof,
        count: 1,
      );
    }
  }
  if (migrationHasDueProofBatch(status, currentHeight: currentHeight)) {
    return const MobileIronwoodMigrationAttention(
      kind: MobileIronwoodMigrationAttentionKind.proof,
      count: 1,
    );
  }
  if (currentHeight <= 0) return null;
  final hasLateBroadcast = status.scheduledBroadcasts.any(
    (item) =>
        item.status.toLowerCase() == 'scheduled' &&
        item.scheduledHeight > 0 &&
        currentHeight >=
            item.scheduledHeight + kIronwoodMigrationLateGraceBlocks,
  );
  return hasLateBroadcast
      ? const MobileIronwoodMigrationAttention(
          kind: MobileIronwoodMigrationAttentionKind.lateBroadcast,
          count: 1,
        )
      : null;
}

String mobileIronwoodMigrationAttentionFingerprint({
  required String accountUuid,
  required String runId,
  required rust_sync.MigrationStatus status,
  required MobileIronwoodMigrationAttention attention,
}) {
  final actionIdentity = switch (attention.kind) {
    MobileIronwoodMigrationAttentionKind.signature ||
    MobileIronwoodMigrationAttentionKind.continueMigration =>
      status.parts
          .where(
            (part) => part.state == rust_sync.MigrationPartState.needsInput,
          )
          .map((part) => part.partIndex)
          .toList()
        ..sort(),
    MobileIronwoodMigrationAttentionKind.proof => [
      status.nextActionPartIndex,
      status.nextActionHeight,
    ],
    MobileIronwoodMigrationAttentionKind.lateBroadcast =>
      status.scheduledBroadcasts
          .where((item) => item.status.toLowerCase() == 'scheduled')
          .map((item) => '${item.txidHex}@${item.scheduledHeight}')
          .toList()
        ..sort(),
  };
  return '$accountUuid:$runId:${status.phase}:'
      '${attention.kind.name}:${attention.count}:$actionIdentity';
}

class MobileIronwoodMigrationAttentionSession extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void markSeen(String fingerprint) {
    if (state.contains(fingerprint)) return;
    state = {...state, fingerprint};
  }
}

final mobileIronwoodMigrationAttentionSessionProvider =
    NotifierProvider<MobileIronwoodMigrationAttentionSession, Set<String>>(
      MobileIronwoodMigrationAttentionSession.new,
    );
