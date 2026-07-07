import '../../providers/multisig_signing_request_provider.dart';

enum MultisigSigningRequestBucket {
  needsAction,
  readyToSend,
  waiting,
  reviewOnly,
}

class MultisigSigningRequestGroups {
  const MultisigSigningRequestGroups({
    required this.needsAction,
    required this.readyToSend,
    required this.waiting,
    required this.reviewOnly,
  });

  final List<MultisigSigningRequestRecord> needsAction;
  final List<MultisigSigningRequestRecord> readyToSend;
  final List<MultisigSigningRequestRecord> waiting;
  final List<MultisigSigningRequestRecord> reviewOnly;

  int get activeCount =>
      needsAction.length +
      readyToSend.length +
      waiting.length +
      reviewOnly.length;

  int get actionableCount => needsAction.length + readyToSend.length;

  bool get isEmpty => activeCount == 0;
}

List<MultisigSigningRequestRecord> activeMultisigSigningRequestsForAccount(
  Iterable<MultisigSigningRequestRecord> requests,
  String? accountUuid,
) {
  if (accountUuid == null) return const <MultisigSigningRequestRecord>[];
  return [
    for (final request in requests)
      if (request.accountUuid == accountUuid && !request.isBroadcasted) request,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

MultisigSigningRequestGroups groupMultisigSigningRequests(
  Iterable<MultisigSigningRequestRecord> requests,
) {
  final needsAction = <MultisigSigningRequestRecord>[];
  final readyToSend = <MultisigSigningRequestRecord>[];
  final waiting = <MultisigSigningRequestRecord>[];
  final reviewOnly = <MultisigSigningRequestRecord>[];

  for (final request in requests) {
    switch (multisigSigningRequestBucket(request)) {
      case MultisigSigningRequestBucket.needsAction:
        needsAction.add(request);
      case MultisigSigningRequestBucket.readyToSend:
        readyToSend.add(request);
      case MultisigSigningRequestBucket.waiting:
        waiting.add(request);
      case MultisigSigningRequestBucket.reviewOnly:
        reviewOnly.add(request);
    }
  }

  return MultisigSigningRequestGroups(
    needsAction: needsAction,
    readyToSend: readyToSend,
    waiting: waiting,
    reviewOnly: reviewOnly,
  );
}

MultisigSigningRequestBucket multisigSigningRequestBucket(
  MultisigSigningRequestRecord request,
) {
  if (request.hasBroadcastTxid) {
    return MultisigSigningRequestBucket.needsAction;
  }
  if (request.readyToBroadcast) {
    return MultisigSigningRequestBucket.readyToSend;
  }
  if (request.isReviewOnly || !request.localParticipantSelected) {
    return MultisigSigningRequestBucket.reviewOnly;
  }
  if (multisigSigningRequestNeedsLocalAction(request)) {
    return MultisigSigningRequestBucket.needsAction;
  }
  return MultisigSigningRequestBucket.waiting;
}

bool multisigSigningRequestNeedsLocalAction(
  MultisigSigningRequestRecord request,
) {
  if (request.hasBroadcastTxid) return !request.broadcastResultSent;
  if (!request.localParticipantSelected) return false;
  if (!request.coordinatorSubmitted) return true;
  if (!request.localRound1Submitted) return true;
  return request.round1Complete && !request.localRound2Submitted;
}

String multisigSigningRequestStatusLabel(MultisigSigningRequestRecord request) {
  if (request.hasBroadcastTxid) return 'Share result';
  if (request.readyToBroadcast) return 'Ready to send';
  if (request.isReviewOnly || !request.localParticipantSelected) {
    return 'Review only';
  }
  if (!request.coordinatorSubmitted) return 'Setup needed';
  if (!request.localRound1Submitted) return 'Needs approval';
  if (request.round1Complete && !request.localRound2Submitted) {
    return 'Finish approval';
  }
  return 'Waiting';
}

String multisigSigningRequestStatusBody(MultisigSigningRequestRecord request) {
  if (request.hasBroadcastTxid) return 'Share the send result with the group.';
  if (request.readyToBroadcast) return 'All approvals are collected.';
  if (request.isReviewOnly || !request.localParticipantSelected) {
    return 'You can review this send.';
  }
  if (!request.coordinatorSubmitted) {
    return 'Save the request for the group.';
  }
  if (!request.localRound1Submitted) return 'Your approval is needed.';
  if (request.round1Complete && !request.localRound2Submitted) {
    return 'Finish your approval.';
  }
  return 'Waiting for the group.';
}

String multisigSigningHomeTitle(MultisigSigningRequestGroups groups) {
  if (groups.needsAction.isNotEmpty && groups.readyToSend.isNotEmpty) {
    final count = groups.actionableCount;
    return '$count sends need your action';
  }
  if (groups.needsAction.isNotEmpty) {
    final count = groups.needsAction.length;
    return count == 1
        ? '1 send needs your action'
        : '$count sends need your action';
  }
  if (groups.readyToSend.isNotEmpty) {
    final count = groups.readyToSend.length;
    return count == 1 ? '1 send is ready' : '$count sends are ready';
  }
  if (groups.waiting.isNotEmpty) {
    final count = groups.waiting.length;
    return count == 1 ? '1 send is waiting' : '$count sends are waiting';
  }
  if (groups.reviewOnly.isNotEmpty) {
    final count = groups.reviewOnly.length;
    return count == 1 ? '1 send to review' : '$count sends to review';
  }
  return 'No active multisig sends';
}

String multisigSigningHomeSubtitle(MultisigSigningRequestGroups groups) {
  if (groups.needsAction.isNotEmpty) return 'Open multisig to continue.';
  if (groups.readyToSend.isNotEmpty) return 'Send it when you are ready.';
  if (groups.waiting.isNotEmpty) return 'Waiting for other approvers.';
  if (groups.reviewOnly.isNotEmpty) return 'Review the latest request.';
  return 'New requests will appear here.';
}
