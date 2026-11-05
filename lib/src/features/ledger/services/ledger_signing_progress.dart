import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart' show AppLocalizations;

/// Coarse user-facing stages, independent of device connection/readiness state.
enum LedgerSigningStage { preparing, sending, reviewing, finishing }

typedef LedgerSigningProgressReporter =
    void Function(String phase, {String? deviceModel});

class LedgerSigningProgress {
  const LedgerSigningProgress(this.accountUuid, this.stage, {this.deviceModel});
  final String accountUuid;
  final LedgerSigningStage stage;

  /// The device selected for this attempt, not persisted account metadata.
  final String? deviceModel;
}

class LedgerSigningProgressController extends Notifier<LedgerSigningProgress?> {
  int _generation = 0;

  @override
  LedgerSigningProgress? build() {
    ref.onDispose(() => _generation++);
    return null;
  }

  /// Each attempt owns its observer. Late native/USB events cannot update a retry.
  LedgerSigningProgressReporter begin(String accountUuid) {
    final generation = ++_generation;
    state = LedgerSigningProgress(accountUuid, LedgerSigningStage.preparing);
    return (phase, {deviceModel}) {
      if (generation != _generation) return;
      final stage = switch (phase) {
        'preparing' => LedgerSigningStage.preparing,
        'sending' => LedgerSigningStage.sending,
        'reviewing' => LedgerSigningStage.reviewing,
        'finishing' => LedgerSigningStage.finishing,
        _ => null,
      };
      final current = state;
      if (stage == null || current == null) return;
      final nextStage = stage.index > current.stage.index
          ? stage
          : current.stage;
      final nextModel = deviceModel ?? current.deviceModel;
      if (nextStage == current.stage && nextModel == current.deviceModel) {
        return;
      }
      state = LedgerSigningProgress(
        accountUuid,
        nextStage,
        deviceModel: nextModel,
      );
    };
  }

  void cancel() {
    final generation = ++_generation;
    // Callers also cancel from widget disposal. Invalidate events immediately,
    // but notify UI listeners after that lifecycle has finished.
    scheduleMicrotask(() {
      if (generation == _generation) state = null;
    });
  }
}

final ledgerSigningProgressProvider =
    NotifierProvider<LedgerSigningProgressController, LedgerSigningProgress?>(
      LedgerSigningProgressController.new,
    );

extension LedgerSigningStageCopy on LedgerSigningStage {
  String title(AppLocalizations l10n) => switch (this) {
    LedgerSigningStage.preparing => l10n.ledgerSigningTitlePreparing,
    LedgerSigningStage.sending => l10n.ledgerSigningTitleSending,
    LedgerSigningStage.reviewing => l10n.ledgerSigningTitleReviewing,
    LedgerSigningStage.finishing => l10n.ledgerSigningTitleFinishing,
  };
  String message(AppLocalizations l10n) => switch (this) {
    LedgerSigningStage.preparing => l10n.ledgerSigningMsgPreparing,
    LedgerSigningStage.sending => l10n.ledgerSigningMsgSending(
      l10n.ledgerSigningWaitInstruction,
    ),
    LedgerSigningStage.reviewing => l10n.ledgerSigningMsgReviewing,
    LedgerSigningStage.finishing => l10n.ledgerSigningKeepVizorOpen,
  };
  String status(AppLocalizations l10n) => switch (this) {
    LedgerSigningStage.sending => l10n.ledgerSigningStatusPreparing,
    LedgerSigningStage.reviewing => l10n.ledgerSigningStatusReview,
    _ => l10n.commonPleaseWait,
  };
}
