import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_window_policy.dart';

void main() {
  for (final sample in [
    (size: const Size(393, 852), wide: false),
    (size: const Size(466, 678), wide: false),
    (size: const Size(690, 829), wide: false),
    (size: const Size(800, 800), wide: false),
    (size: const Size(829, 690), wide: true),
    (size: const Size(951, 669), wide: true),
    (size: const Size(700, 600), wide: true),
    (size: const Size(567, 400), wide: false),
    (size: const Size(568, 400), wide: true),
    (size: const Size(800, 159), wide: false),
  ]) {
    test('window ${sample.size} selects wide=${sample.wide}', () {
      final policy = MobileWindowPolicy.resolve(
        MediaQueryData(size: sample.size),
      );
      expect(policy.usesWideLayout, sample.wide);
    });
  }

  test('safe area affects fitting while keyboard insets do not', () {
    const media = MediaQueryData(
      size: Size(650, 500),
      viewPadding: EdgeInsets.only(right: 84, bottom: 24),
      padding: EdgeInsets.only(right: 84, bottom: 24),
    );
    final policy = MobileWindowPolicy.resolve(media);
    expect(policy.safeRect.size, const Size(566, 476));
    expect(policy.usesWideLayout, isFalse);
    final keyboard = MobileWindowPolicy.resolve(
      media.copyWith(
        padding: const EdgeInsets.only(right: 84),
        viewInsets: const EdgeInsets.only(bottom: 500),
      ),
    );
    expect(keyboard.safeRect, policy.safeRect);
    expect(keyboard.usesWideLayout, policy.usesWideLayout);
  });

  for (final size in [const Size(716, 794), const Size(800, 800)]) {
    test(
      'safe insets cannot reclassify a portrait or square window ($size)',
      () {
        final policy = MobileWindowPolicy.resolve(
          MediaQueryData(
            size: size,
            viewPadding: const EdgeInsets.symmetric(vertical: 50),
          ),
        );
        expect(policy.safeRect.width, greaterThan(policy.safeRect.height));
        expect(policy.usesWideLayout, isFalse);
      },
    );
  }

  testWidgets('nested pages inherit the window policy instead of pane size', (
    tester,
  ) async {
    final rootPolicy = MobileWindowPolicy.resolve(
      const MediaQueryData(size: Size(951, 669)),
    );
    late MobileWindowPolicy inherited;
    await tester.pumpWidget(
      MobileWindowPolicyScope(
        policy: rootPolicy,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(320, 669)),
          child: Builder(
            builder: (context) {
              inherited = MobileWindowPolicyScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(inherited, same(rootPolicy));
    expect(inherited.usesWideLayout, isTrue);
  });
}
