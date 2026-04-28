import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_loading_icon.dart';

void main() {
  test('loader progress is derived from absolute frame time', () {
    expect(
      AppLoadingIconTiming.progressForFrameTime(Duration.zero),
      moreOrLessEquals(0),
    );
    expect(
      AppLoadingIconTiming.progressForFrameTime(
        AppLoadingIconTiming.period ~/ 2,
      ),
      moreOrLessEquals(0.5),
    );
    expect(
      AppLoadingIconTiming.progressForFrameTime(AppLoadingIconTiming.period),
      moreOrLessEquals(0),
    );
    expect(
      AppLoadingIconTiming.progressForFrameTime(
        AppLoadingIconTiming.period + AppLoadingIconTiming.period ~/ 2,
      ),
      moreOrLessEquals(0.5),
    );
  });

  test('loader opacity is deterministic for a shared frame time', () {
    final progress = AppLoadingIconTiming.progressForFrameTime(
      const Duration(milliseconds: 1234),
    );

    final firstLoaderOpacities = List.generate(
      AppLoadingIconTiming.spokeCount,
      (index) =>
          AppLoadingIconTiming.opacityForSpokeAtProgress(index, progress),
    );
    final secondLoaderOpacities = List.generate(
      AppLoadingIconTiming.spokeCount,
      (index) =>
          AppLoadingIconTiming.opacityForSpokeAtProgress(index, progress),
    );

    expect(secondLoaderOpacities, firstLoaderOpacities);
  });
}
