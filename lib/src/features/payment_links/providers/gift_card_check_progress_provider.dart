import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_service.dart'
    show paymentLinkClaimWalletDirectoryName;
import '../../../rust/api/sync.dart' as rust_sync;

class GiftCardCheckProgress {
  const GiftCardCheckProgress(this.link, this.event);
  final VizorPaymentLink link;
  final rust_sync.ApiGiftCardCheckProgress event;
  bool get hasFunding => event.fundingHeight > 0;
  String label(AppLocalizations l10n) {
    final total = event.total;
    final percent = total > BigInt.zero
        ? (event.completed * BigInt.from(100) ~/ total).toInt().clamp(0, 100)
        : 0;
    return l10n.paymentLinkCheckProgress(
      event.phase == 'finding' ? 'finding' : 'checking',
      '$percent',
    );
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
