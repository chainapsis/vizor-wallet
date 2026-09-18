import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/activity/gift_card_activity_index.dart';
import '../src/features/activity/widgets/gift_card_activity_detail_view.dart';
import '../src/features/payment_links/models/gift_card_usage.dart';
import '../src/features/payment_links/providers/gift_card_tracking_provider.dart';
import '../src/features/payment_links/widgets/gift_card_usage_status.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';

void _noop() {}

// Capture-only fixtures: no wallet, storage, keys or network are accessed.
class _CaptureState extends GiftCardTrackingStateNotifier {
  @override
  GiftCardTrackingState build() =>
      const GiftCardTrackingState(failedAddresses: {'failed'});
}

class _CaptureCheckingState extends GiftCardTrackingStateNotifier {
  @override
  GiftCardTrackingState build() => const GiftCardTrackingState(checking: true);
}

Widget _fixture(Widget child, {bool checking = false}) => ProviderScope(
  overrides: [
    giftCardTrackingStateProvider.overrideWith(
      checking ? _CaptureCheckingState.new : _CaptureState.new,
    ),
    giftCardUsageProvider.overrideWith((ref, address) async {
      final status = switch (address) {
        'awaiting' => GiftCardUsageStatus.unknown,
        'unknown' => GiftCardUsageStatus.unknown,
        'detected' => GiftCardUsageStatus.spendDetected,
        'used' => GiftCardUsageStatus.used,
        _ => GiftCardUsageStatus.unused,
      };
      return GiftCardUsage(
        status: status,
        reason: address == 'awaiting'
            ? GiftCardUsageReason.awaitingConfirmation
            : null,
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

Widget buildGiftCardUsageListCapture(BuildContext context) => _list();
Widget buildGiftCardUsageCheckingCapture(BuildContext context) =>
    _list(checking: true);
Widget buildMobileGiftCardUsageListCapture(BuildContext context) =>
    _list(mobile: true);
Widget buildMobileGiftCardUsageCheckingCapture(BuildContext context) =>
    _list(mobile: true, checking: true);

Widget _list({bool mobile = false, bool checking = false}) {
  Widget row(String address) => mobile
      ? PaymentLinkCardListMobileRow(
          thumbnail: const FittedBox(child: _card),
          amountText: '0.25 ZEC',
          dateText: 'September 14',
          showLinkActions: true,
          onCopyLink: _noop,
          onShowQr: _noop,
          metadata: GiftCardUsageStatusView(
            address: address,
            inline: true,
            dateText: 'September 14',
            hideStableLabel: true,
          ),
        )
      : PaymentLinkCardListRow(
          thumbnail: const FittedBox(child: _card),
          amountText: '0.25 ZEC',
          dateText: 'September 14',
          showLinkActions: true,
          onCopyLink: _noop,
          onShowQr: _noop,
          usageStatus: GiftCardUsageStatusView(address: address, inline: true),
        );
  final sections = mobile
      ? [
          PaymentLinkCardsSection(
            label: 'Pending',
            cards: ['awaiting', 'unknown'].map(row).toList(),
          ),
          PaymentLinkCardsSection(
            label: 'Unused',
            cards: ['unused', 'failed'].map(row).toList(),
          ),
          PaymentLinkCardsSection(
            label: 'Used',
            cards: ['detected', 'used'].map(row).toList(),
          ),
        ]
      : [
          PaymentLinkCardsSection(
            label: 'Pending',
            cards: [
              'awaiting',
              'unknown',
              'unused',
              'detected',
              'used',
              'failed',
            ].map(row).toList(),
          ),
        ];
  return _fixture(
    mobile
        ? PaymentLinkCardsMobileView(
            sections: sections,
            onBack: _noop,
            onCreate: _noop,
            onRedeem: _noop,
          )
        : PaymentLinkCardsDesktopView(
            sections: sections,
            onBack: _noop,
            onCreate: _noop,
            onRedeem: _noop,
          ),
    checking: checking,
  );
}

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
    onHome: _noop,
    onCopy: _noop,
  ),
);

Widget buildGiftCardUsageShareCapture(BuildContext context) => _fixture(
  const PaymentLinkShareQrDesktopView(
    artwork: PaymentLinkCardArtwork.ruby,
    qrData: 'https://example.invalid/gift-card-preview',
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
