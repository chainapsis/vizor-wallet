import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/activity/gift_card_activity_index.dart';
import '../src/features/activity/widgets/gift_card_activity_detail_view.dart';
import '../src/features/payment_links/models/gift_card_usage.dart';
import '../src/features/payment_links/providers/gift_card_tracking_provider.dart';
import '../src/features/payment_links/services/gift_card_tracking_service.dart';
import '../src/features/payment_links/widgets/gift_card_usage_status.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';

void _noop() {}

// Capture-only fixtures: no wallet, storage, keys or network are accessed.
class _CaptureTracker implements GiftCardTrackingService {
  @override
  Future<void> refresh({bool force = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CaptureState extends GiftCardTrackingStateNotifier {
  @override
  GiftCardTrackingState build() =>
      const GiftCardTrackingState(failedAddresses: {'failed'});
}

Widget _fixture(Widget child) => ProviderScope(
  overrides: [
    giftCardTrackingServiceProvider.overrideWithValue(_CaptureTracker()),
    giftCardTrackingStateProvider.overrideWith(_CaptureState.new),
    giftCardUsageProvider.overrideWith((ref, address) async {
      final status = switch (address) {
        'unknown' => GiftCardUsageStatus.unknown,
        'detected' => GiftCardUsageStatus.spendDetected,
        'used' => GiftCardUsageStatus.used,
        _ => GiftCardUsageStatus.unused,
      };
      return GiftCardUsage(
        status: status,
        checkedAt: status == GiftCardUsageStatus.unknown
            ? null
            : DateTime(2026, 9, 14, 18, 30),
        cleaned: status == GiftCardUsageStatus.used,
      );
    }),
  ],
  child: Builder(
    builder: (context) =>
        ColoredBox(color: context.colors.background.window, child: child),
  ),
);

const _card = PaymentLinkGiftCard(
  artwork: PaymentLinkCardArtwork.ruby,
  amountText: '0.25',
  showCaret: false,
);

Widget buildGiftCardUsageListCapture(BuildContext context) => _fixture(
  PaymentLinkCardsDesktopView(
    onBack: _noop,
    onCreate: _noop,
    onRedeem: _noop,
    sections: [
      PaymentLinkCardsSection(
        label: 'Pending',
        cards: [
          for (final address in [
            'unknown',
            'unused',
            'detected',
            'used',
            'failed',
          ])
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PaymentLinkCardListRow(
                  thumbnail: const FittedBox(child: _card),
                  amountText: '0.25 ZEC',
                  dateText: 'September 14',
                  showLinkActions: true,
                  onCopyLink: _noop,
                  onShowQr: _noop,
                ),
                GiftCardUsageStatusView(address: address),
              ],
            ),
        ],
      ),
    ],
  ),
);

Widget buildGiftCardUsageReadyCapture(BuildContext context) => _fixture(
  const PaymentLinkReadyMobileView(
    state: PaymentLinkReadyMobileState.ready,
    card: PaymentLinkGiftCard(
      artwork: PaymentLinkCardArtwork.ruby,
      amountText: '0.25',
      showCaret: false,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
    ),
    usageStatus: GiftCardUsageStatusView(
      address: 'unused',
      showCheckedAt: true,
    ),
    onHome: _noop,
    onCopy: _noop,
  ),
);

Widget buildGiftCardUsageShareCapture(BuildContext context) => _fixture(
  const PaymentLinkShareQrDesktopView(
    artwork: PaymentLinkCardArtwork.ruby,
    qrData: 'https://example.invalid/gift-card-preview',
    usageStatus: GiftCardUsageStatusView(
      address: 'unused',
      showCheckedAt: true,
    ),
    onBack: _noop,
    onSaveQr: _noop,
    onCopyLink: _noop,
  ),
);

Widget buildGiftCardUsageActivityCapture(BuildContext context) => _fixture(
  SingleChildScrollView(
    child: GiftCardActivityDetailView(
      kind: GiftCardActivityKind.created,
      artwork: PaymentLinkCardArtwork.ruby,
      cardAddress: 'used',
      amountText: '0.25',
      statusText: 'Completed',
      statusIconName: AppIcons.checkCircle,
      statusColor: context.colors.text.positiveStrong,
      timestampText: '14 September, 18:20',
      txIdText: 'f154...8143',
      feeText: '0.0002 ZEC',
      onTxIdPressed: _noop,
    ),
  ),
);
