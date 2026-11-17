import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/motion/platform_reduce_motion_scope.dart';

void main() {
  Future<bool Function()> pumpScope(WidgetTester tester) async {
    late bool disableAnimations;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: PlatformReduceMotionScope(
          child: Builder(
            builder: (context) {
              disableAnimations = MediaQuery.disableAnimationsOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return () => disableAnimations;
  }

  testWidgets('platform reduce motion disables animations below the scope', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final disableAnimations = await pumpScope(tester);

    expect(disableAnimations(), isTrue);
  });

  testWidgets('animations stay on without reduce motion', (tester) async {
    final disableAnimations = await pumpScope(tester);

    expect(disableAnimations(), isFalse);
  });

  testWidgets('turning reduce motion on while running updates the scope', (
    tester,
  ) async {
    final disableAnimations = await pumpScope(tester);
    expect(disableAnimations(), isFalse);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.binding.handleAccessibilityFeaturesChanged();
    await tester.pump();

    expect(disableAnimations(), isTrue);
  });
}
