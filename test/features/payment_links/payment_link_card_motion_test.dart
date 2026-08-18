import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_motion.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';

void main() {
  testWidgets('celebration grows and turns the settled card into view', (
    tester,
  ) async {
    var celebrate = false;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return PaymentLinkCardMotion(
            celebrate: celebrate,
            child: const SizedBox(
              key: ValueKey('motion-card'),
              width: PaymentLinkGiftCard.width,
              height: PaymentLinkGiftCard.height,
            ),
          );
        },
      ),
    );

    Matrix4 revealMatrix() =>
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('payment_link_reveal_transform')),
            )
            .transform;

    expect(revealMatrix().entry(0, 0), closeTo(1, 1e-6));

    update(() => celebrate = true);
    await tester.pump();
    await tester.pump(PaymentLinkCardMotion.revealDuration ~/ 2);
    expect(revealMatrix().entry(0, 0).abs(), lessThan(0.99));

    await tester.pump(PaymentLinkCardMotion.revealDuration);
    expect(revealMatrix().entry(0, 0), closeTo(1, 1e-6));
  });

  testWidgets('settled card tilts toward the pointer and releases to rest', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkCardMotion(
        child: SizedBox(
          key: ValueKey('motion-card'),
          width: PaymentLinkGiftCard.width,
          height: PaymentLinkGiftCard.height,
        ),
      ),
    );

    Matrix4 tiltMatrix() =>
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('payment_link_tilt_transform')),
            )
            .transform;
    final rest = tiltMatrix().clone();
    final region = tester.widget<MouseRegion>(
      find.byKey(const ValueKey('payment_link_tilt_mouse_region')),
    );
    region.onHover!(const PointerHoverEvent(position: Offset(312, 8)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tiltMatrix(), isNot(equals(rest)));
    expect(find.byKey(const ValueKey('payment_link_holo_shine')), findsNothing);

    region.onExit!(const PointerExitEvent());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tiltMatrix(), equals(rest));
  });

  testWidgets('gift card lighting follows the shared hover state', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkCardMotion(
        child: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          showCaret: false,
        ),
      ),
    );

    final region = tester.widget<MouseRegion>(
      find.byKey(const ValueKey('payment_link_tilt_mouse_region')),
    );
    region.onHover!(const PointerHoverEvent(position: Offset(312, 8)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('payment_link_holo_shine')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_metallic_shine')),
      findsOneWidget,
    );
  });

  testWidgets('message side uses the shared gloss layer', (tester) async {
    await _pump(
      tester,
      const PaymentLinkCardMotion(
        child: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: 'Happy birthday!',
        ),
      ),
    );
    expect(find.byType(PaymentLinkCardGlossShine), findsOneWidget);
  });

  testWidgets('reduced motion skips reveal and pointer effects', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkCardMotion(
        celebrate: true,
        child: SizedBox(
          key: ValueKey('motion-card'),
          width: PaymentLinkGiftCard.width,
          height: PaymentLinkGiftCard.height,
        ),
      ),
      disableAnimations: true,
    );

    final reveal = tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_reveal_transform')),
    );
    expect(reveal.transform.entry(0, 0), closeTo(1, 1e-6));

    final region = tester.widget<MouseRegion>(
      find.byKey(const ValueKey('payment_link_tilt_mouse_region')),
    );
    region.onHover!(const PointerHoverEvent(position: Offset(312, 8)));
    await tester.pump(const Duration(milliseconds: 500));

    final tilt = tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_tilt_transform')),
    );
    expect(tilt.transform, equals(Matrix4.identity()));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder:
          (context, appChild) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: AppTheme(data: AppThemeData.dark, child: appChild!),
          ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}
