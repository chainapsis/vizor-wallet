import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';

class GiftClaimFailureNotice {
  const GiftClaimFailureNotice(this.link, this.accountUuid);

  final VizorPaymentLink link;
  final String accountUuid;
}

class GiftClaimFailureNoticeNotifier extends Notifier<GiftClaimFailureNotice?> {
  @override
  GiftClaimFailureNotice? build() => null;

  void report(VizorPaymentLink link, String accountUuid) {
    state = GiftClaimFailureNotice(link, accountUuid);
  }

  void dismiss(GiftClaimFailureNotice notice) {
    if (identical(state, notice)) state = null;
  }
}

final giftClaimFailureNoticeProvider =
    NotifierProvider<GiftClaimFailureNoticeNotifier, GiftClaimFailureNotice?>(
      GiftClaimFailureNoticeNotifier.new,
    );
