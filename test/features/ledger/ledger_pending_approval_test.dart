import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_pending_approval.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';

void main() {
  test('only the phases that can wait on the device count as pending', () {
    const awaiting = {
      LedgerSigningModalPhase.preparing,
      LedgerSigningModalPhase.awaitingDevice,
    };
    for (final phase in LedgerSigningModalPhase.values) {
      expect(
        ledgerPhaseAwaitsDevice(phase),
        awaiting.contains(phase),
        reason: '$phase',
      );
    }
    expect(ledgerPhaseAwaitsDevice(null), isFalse);
  });

  test('handle registers after the current frame and releases once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(ledgerPendingApprovalProvider.notifier);
    final handle = LedgerPendingApprovalHandle(notifier);

    handle.update(LedgerSigningModalPhase.preparing);
    expect(container.read(ledgerPendingApprovalProvider), isEmpty);
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), {handle.requestId});

    handle.update(LedgerSigningModalPhase.awaitingDevice);
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), {handle.requestId});

    handle.update(LedgerSigningModalPhase.saving);
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), isEmpty);

    handle.update(LedgerSigningModalPhase.awaitingDevice);
    handle.release();
    await Future<void>.microtask(() {});
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), isEmpty);
  });

  test('the registry stays non-empty until every screen releases', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(ledgerPendingApprovalProvider.notifier);
    final send = LedgerPendingApprovalHandle(notifier);
    final shield = LedgerPendingApprovalHandle(notifier);

    send.update(LedgerSigningModalPhase.awaitingDevice);
    shield.update(LedgerSigningModalPhase.preparing);
    await Future<void>.microtask(() {});
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), hasLength(2));

    send.release();
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), {shield.requestId});

    shield.update(LedgerSigningModalPhase.failed);
    await Future<void>.microtask(() {});
    expect(container.read(ledgerPendingApprovalProvider), isEmpty);
  });
}
