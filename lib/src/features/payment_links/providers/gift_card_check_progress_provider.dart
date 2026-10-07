import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';
import '../services/payment_link_service.dart'
    show paymentLinkClaimWalletDirectoryName;
import '../../../rust/api/sync.dart' as rust_sync;

class GiftCardCheckProgress {
  const GiftCardCheckProgress(this.link, this.event);
  final VizorPaymentLink link;
  final rust_sync.ApiGiftCardCheckProgress event;
  bool get hasFunding => event.fundingHeight > 0;
  String get label {
    final total = event.total;
    final percent = total > BigInt.zero
        ? (event.completed * BigInt.from(100) ~/ total).toInt().clamp(0, 100)
        : 0;
    return '${event.phase == 'finding' ? 'Finding the gift' : 'Checking the gift'}… $percent%';
  }
}

class GiftCardCheckProgressNotifier
    extends Notifier<Map<String, GiftCardCheckProgress>> {
  @override
  Map<String, GiftCardCheckProgress> build() => const {};
  void update(VizorPaymentLink link, rust_sync.ApiGiftCardCheckProgress event) {
    state = {
      ...state,
      paymentLinkClaimWalletDirectoryName(link): GiftCardCheckProgress(
        link,
        event,
      ),
    };
  }

  void clear(VizorPaymentLink link) {
    state = {...state}..remove(paymentLinkClaimWalletDirectoryName(link));
  }
}

final giftCardCheckProgressProvider =
    NotifierProvider<
      GiftCardCheckProgressNotifier,
      Map<String, GiftCardCheckProgress>
    >(GiftCardCheckProgressNotifier.new);
