import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/wallet_provider.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_service.dart';
import '../services/gift_claim_import_store.dart';
import 'payment_link_claim_coordinator_provider.dart';
import 'payment_link_intake_provider.dart';

enum GiftClaimPhase { checking, longSyncConfirmation, inspected, failed }

enum GiftClaimFailure { network, otherNetwork, invalid }

/// The Gift Card a recipient without a wallet is looking at on `/gift`.
///
/// It owns its link and inspection apart from the intake queue, so a second
/// incoming link cannot replace what the user is reviewing.
@immutable
class GiftClaimFlowState {
  const GiftClaimFlowState({
    required this.link,
    required this.phase,
    this.inspection,
    this.failure,
    this.setupPasscode,
  });

  final VizorPaymentLink link;
  final GiftClaimPhase phase;
  final PaymentLinkClaimInspection? inspection;
  final GiftClaimFailure? failure;
  // Kept only until setup leaves the screen. Route refresh must not serialize it.
  final String? setupPasscode;
  bool get walletSetupInProgress => setupPasscode != null;
}

/// Carries the inspected Card through normal wallet import. The import commits
/// its recipient and starts the claim before Face ID; a restart uses the journal.
@immutable
class GiftClaimSetupReturn extends GiftClaimImportHandoff {
  const GiftClaimSetupReturn({
    required super.link,
    required super.accountUuidsBeforeSetup,
    required this.inspection,
  });

  final PaymentLinkClaimInspection inspection;
}

class GiftClaimSetupReturnNotifier extends Notifier<GiftClaimSetupReturn?> {
  @override
  GiftClaimSetupReturn? build() => null;

  Future<void> begin(
    VizorPaymentLink link, {
    required Iterable<String> accountUuidsBeforeSetup,
    required PaymentLinkClaimInspection inspection,
  }) async {
    final request = GiftClaimSetupReturn(
      link: link,
      accountUuidsBeforeSetup: Set.unmodifiable(accountUuidsBeforeSetup),
      inspection: inspection,
    );
    state = request;
    try {
      await ref.read(giftClaimImportStoreProvider).save(request);
    } catch (_) {
      clearIfMatches(request);
      rethrow;
    }
  }

  Future<void> clear() async {
    final request = state;
    if (request == null) return;
    await ref.read(giftClaimImportStoreProvider).clear(request);
    clearIfMatches(request);
  }

  /// Completes only the handoff this caller started. A newer Card may have
  /// replaced it while an earlier claim was preparing off-screen.
  bool clearIfMatches(GiftClaimSetupReturn request) {
    if (!identical(state, request)) return false;
    state = null;
    return true;
  }
}

final giftClaimSetupReturnProvider =
    NotifierProvider<GiftClaimSetupReturnNotifier, GiftClaimSetupReturn?>(
      GiftClaimSetupReturnNotifier.new,
    );

String giftClaimSetupCompletionLocation(
  WidgetRef ref, {
  required String otherwise,
}) => ref.read(giftClaimSetupReturnProvider) == null
    ? otherwise
    : '/payment-links';

class GiftClaimFlowNotifier extends Notifier<GiftClaimFlowState?> {
  // Advanced whenever the flow changes hands, so a late inspection result
  // from an earlier Card or check is not published.
  int _generation = 0;
  Future<GiftClaimFlowState>? _inspectionTask;
  // Different payloads can use the same claim wallet. Drain the old check and
  // its cleanup before inspecting another payload with that wallet identity.
  final _cleanupByWallet = <String, Future<void>>{};

  @override
  GiftClaimFlowState? build() {
    // Once a wallet exists, setup or Payment Links owns the Card; the
    // claim wallet this flow checked stays available for that handoff.
    ref.listen(walletProvider, (_, next) {
      if (next.value?.hasWallet != true ||
          state == null ||
          state!.walletSetupInProgress) {
        return;
      }
      final generation = ++_generation;
      // Wallet state can rebuild lazily while the covered Gift screen builds.
      // Invalidate late checks now, then publish the handoff outside that build.
      scheduleMicrotask(() {
        if (!ref.mounted || generation != _generation) return;
        if (ref.read(walletProvider).value?.hasWallet == true) state = null;
      });
    });
    return null;
  }

  /// Retain the checked Card while its first account finishes durable setup.
  void beginWalletSetup(
    PaymentLinkClaimInspection inspection, {
    required String passcode,
  }) {
    _generation++;
    state = GiftClaimFlowState(
      link: inspection.link,
      phase: GiftClaimPhase.inspected,
      inspection: inspection,
      setupPasscode: passcode,
    );
  }

  /// Navigation away releases only the setup owned by this screen.
  void finishWalletSetup(PaymentLinkClaimInspection inspection) {
    if (!ref.mounted ||
        state?.walletSetupInProgress != true ||
        !identical(state?.inspection, inspection)) {
      return;
    }
    _generation++;
    state = null;
  }

  /// Starts checking [link] unless the same Card is already open.
  void open(VizorPaymentLink link) {
    final current = state;
    if (current != null && current.link.hasSameCanonicalPayload(link)) return;
    _generation++;
    _queueInspectionCleanup(current);
    _check(link, allowLongSync: false);
  }

  /// Checks the open Card again, optionally accepting a long history scan.
  void recheck({bool allowLongSync = false}) {
    final current = state;
    if (current == null || current.phase == GiftClaimPhase.checking) return;
    _check(current.link, allowLongSync: allowLongSync);
  }

  /// Route removal may run while Navigator is building. The screen schedules
  /// this cleanup afterward, without allowing an old pop to close a newer Card
  /// or discard a handoff already owned by a newly created/imported wallet.
  void closeAfterPop(GiftClaimFlowState? poppedFlow) {
    if (!ref.mounted || !identical(state, poppedFlow)) return;
    if (state?.walletSetupInProgress == true ||
        ref.read(walletProvider).value?.hasWallet == true) {
      return;
    }
    unawaited(
      close().catchError((Object error) {
        log('Gift import cleanup failed: ${error.runtimeType}');
      }),
    );
  }

  /// The user left `/gift`: drop the Card and its unsaved claim wallet.
  Future<void> close() async {
    final current = state;
    _generation++;
    if (ref.read(giftClaimSetupReturnProvider) != null) {
      await ref.read(giftClaimSetupReturnProvider.notifier).clear();
      if (!ref.mounted || !identical(state, current)) return;
    }
    state = null;
    _queueInspectionCleanup(current);
    final pending = ref.read(paymentLinkIntakeProvider).pendingLink;
    if (current != null &&
        pending != null &&
        pending.hasSameCanonicalPayload(current.link)) {
      ref.read(paymentLinkIntakeProvider.notifier).takePending();
    }
  }

  /// Persist the Card before leaving for normal wallet import. The live caller
  /// retains its inspection so committing the imported recipient needs no scan.
  Future<bool> handOffToSetup({
    Iterable<String> accountUuidsBeforeSetup = const <String>[],
  }) async {
    final current = state;
    if (current == null || current.inspection == null) return false;
    if (ref.read(paymentLinkIntakeProvider.notifier).prioritize(current.link) !=
        PaymentLinkIntakeResult.accepted) {
      return false;
    }
    await ref
        .read(giftClaimSetupReturnProvider.notifier)
        .begin(
          current.inspection?.link ?? current.link,
          accountUuidsBeforeSetup: accountUuidsBeforeSetup,
          inspection: current.inspection!,
        );
    return ref.mounted && identical(state, current);
  }

  /// The recipient chose the dedicated one-step Gift Card wallet instead.
  Future<void> cancelSetupReturn() =>
      ref.read(giftClaimSetupReturnProvider.notifier).clear();

  void _check(VizorPaymentLink link, {required bool allowLongSync}) {
    final generation = ++_generation;
    state = GiftClaimFlowState(link: link, phase: GiftClaimPhase.checking);
    _inspectionTask = null;
    final cleanup = _cleanupByWallet[paymentLinkClaimWalletDirectoryName(link)];
    if (cleanup == null) {
      _startInspection(link, generation, allowLongSync: allowLongSync);
    } else {
      unawaited(
        _startAfterCleanup(
          cleanup,
          link,
          generation,
          allowLongSync: allowLongSync,
        ),
      );
    }
  }

  Future<void> _startAfterCleanup(
    Future<void> cleanup,
    VizorPaymentLink link,
    int generation, {
    required bool allowLongSync,
  }) async {
    try {
      await cleanup;
    } catch (error) {
      if (generation == _generation && ref.mounted) {
        log('GiftClaimFlow: claim wallet cleanup failed: ${error.runtimeType}');
        state = GiftClaimFlowState(
          link: link,
          phase: GiftClaimPhase.failed,
          failure: GiftClaimFailure.network,
        );
      }
      return;
    }
    if (generation != _generation || !ref.mounted) return;
    _startInspection(link, generation, allowLongSync: allowLongSync);
  }

  void _startInspection(
    VizorPaymentLink link,
    int generation, {
    required bool allowLongSync,
  }) {
    _inspectionTask = _inspect(link, generation, allowLongSync: allowLongSync);
  }

  Future<GiftClaimFlowState> _inspect(
    VizorPaymentLink link,
    int generation, {
    required bool allowLongSync,
  }) async {
    GiftClaimFlowState next;
    try {
      PaymentLinkClaimInspection? inspection;
      // Registered with the reset drain; skipped outright during a reset.
      await ref.read(paymentLinkClaimCoordinatorProvider).trackRetention(
        () async {
          inspection = await ref
              .read(paymentLinkOperationsProvider)
              .inspectClaim(link, allowLongSync: allowLongSync);
        },
      );
      final result = inspection;
      next = result == null
          ? GiftClaimFlowState(
              link: link,
              phase: GiftClaimPhase.failed,
              failure: GiftClaimFailure.network,
            )
          : GiftClaimFlowState(
              link: result.link,
              phase: GiftClaimPhase.inspected,
              inspection: result,
            );
    } on PaymentLinkLongSyncConfirmationRequired {
      next = GiftClaimFlowState(
        link: link,
        phase: GiftClaimPhase.longSyncConfirmation,
      );
    } on PaymentLinkNetworkMismatchException {
      next = GiftClaimFlowState(
        link: link,
        phase: GiftClaimPhase.failed,
        failure: GiftClaimFailure.otherNetwork,
      );
    } on FormatException {
      next = GiftClaimFlowState(
        link: link,
        phase: GiftClaimPhase.failed,
        failure: GiftClaimFailure.invalid,
      );
    } catch (error) {
      log('GiftClaimFlow: inspection failed: ${error.runtimeType}');
      next = GiftClaimFlowState(
        link: link,
        phase: GiftClaimPhase.failed,
        failure: GiftClaimFailure.network,
      );
    }
    if (generation != _generation || !ref.mounted) {
      return next;
    }
    state = next;
    return next;
  }

  void _queueInspectionCleanup(GiftClaimFlowState? flow) {
    if (flow == null) return;
    final walletId = paymentLinkClaimWalletDirectoryName(flow.link);
    final previous = _cleanupByWallet[walletId];
    final task = _inspectionTask;
    final operations = ref.read(paymentLinkOperationsProvider);
    late final Future<void> cleanup;
    cleanup = () async {
      if (previous != null) await previous;
      final finished = task == null ? flow : await task;
      final inspection = finished.inspection ?? flow.inspection;
      if (inspection != null) {
        await operations.discardClaimInspection(inspection);
      }
    }();
    _cleanupByWallet[walletId] = cleanup;
    unawaited(
      cleanup
          .then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              log(
                'GiftClaimFlow: claim wallet cleanup failed: ${error.runtimeType}',
              );
            },
          )
          .whenComplete(() {
            if (identical(_cleanupByWallet[walletId], cleanup)) {
              _cleanupByWallet.remove(walletId);
            }
          }),
    );
  }
}

final giftClaimFlowProvider =
    NotifierProvider<GiftClaimFlowNotifier, GiftClaimFlowState?>(
      GiftClaimFlowNotifier.new,
    );
