import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_navigation_scope.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_window_layout.dart';
import 'package:zcash_wallet/src/services/native_mobile_navigation_geometry.dart';

MobileNavigationGeometry geometry(
  Size size, {
  bool left = false,
  List<Rect> blocked = const [],
  Rect? bar,
}) => MobileNavigationGeometry(
  edge: left ? MobileNavigationEdge.left : MobileNavigationEdge.right,
  viewSize: size,
  safeRect: Rect.fromLTWH(left ? 84 : 0, 0, size.width - 84, size.height),
  occlusions: blocked,
  barRect: bar,
);

void main() {
  test('ordinary phone retains its full viewport and bottom tabs', () {
    const media = MediaQueryData(
      size: Size(393, 852),
      viewPadding: EdgeInsets.only(top: 59, bottom: 34),
    );
    final layout = MobileWindowLayout.resolve(media: media);
    expect(layout.mode, MobileNavigationMode.bottomTabs);
    expect(layout.body, Offset.zero & media.size);
    expect(layout.viewport, layout.body);
    expect(mobilePaneMedia(media, layout.body), media);
  });
  for (final left in [false, true]) {
    test('closed system-side placement keeps all body metrics ($left)', () {
      const size = Size(492, 720);
      final native = geometry(
        size,
        left: left,
        blocked: [Rect.fromLTWH(left ? 0 : 408, 0, 84, 190)],
      );
      final media = MediaQueryData(
        size: size,
        padding: EdgeInsets.only(left: left ? 84 : 0, right: left ? 0 : 84),
        viewPadding: EdgeInsets.only(left: left ? 84 : 0, right: left ? 0 : 84),
      );
      final layout = MobileWindowLayout.resolve(media: media, native: native);
      expect(layout.mode, MobileNavigationMode.systemSideTabs);
      expect(layout.body, Offset.zero & size);
      expect(layout.viewport, layout.body);
      expect(mobilePaneMedia(media, layout.body), media);
      expect(layout.rail!.overlaps(native.occlusions.first), isFalse);
      expect(layout.rail!.width, greaterThanOrEqualTo(52));
      expect(
        left ? layout.rail!.right <= 84 : layout.rail!.left >= 408,
        isTrue,
      );
    });
  }
  test('bar guide is usable at its exact 64-point extent', () {
    const size = Size(492, 720);
    final layout = MobileWindowLayout.resolve(
      media: const MediaQueryData(size: size),
      native: geometry(size, bar: const Rect.fromLTWH(418, 200, 64, 400)),
    );
    expect(layout.mode, MobileNavigationMode.systemSideTabs);
    expect(layout.rail!.width, 64);
  });
  test(
    'short side strip still hosts a scrollable rail instead of bottom tabs',
    () {
      const size = Size(492, 720);
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: 450),
        ),
        native: geometry(size, blocked: [const Rect.fromLTWH(408, 0, 84, 180)]),
      );
      expect(layout.mode, MobileNavigationMode.systemSideTabs);
      expect(layout.rail!.height, lessThan(232));
    },
  );
  test(
    'keyboard covering the usable lane never changes system side placement',
    () {
      const size = Size(492, 720);
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: 500),
        ),
        native: geometry(size, blocked: [const Rect.fromLTWH(408, 0, 84, 190)]),
      );
      expect(layout.mode, MobileNavigationMode.systemSideTabs);
      expect(layout.rail, isNotNull);
    },
  );
  test(
    'wide window takes priority over native side edge and constrains mobile content',
    () {
      const size = Size(900, 700);
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(size: size),
        native: geometry(size),
      );
      expect(layout.mode, MobileNavigationMode.sidebar);
      expect(layout.sidebar!.width, 256);
      expect(layout.body.width, inInclusiveRange(320, 440));
      expect(layout.sidebar!.right, lessThan(layout.body.left));
      expect(layout.rail, isNull);
    },
  );
  test(
    'a short wide window fits both panes below the old width breakpoint',
    () {
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(size: Size(568, 400)),
      );
      expect(layout.mode, MobileNavigationMode.sidebar);
      expect(layout.sidebar!.width, 200);
      expect(layout.body.width, 320);
    },
  );
  for (final size in [
    const Size(600, 700),
    const Size(690, 829),
    const Size(800, 800),
  ]) {
    test('portrait and square windows keep mobile navigation ($size)', () {
      final layout = MobileWindowLayout.resolve(
        media: MediaQueryData(size: size),
      );
      expect(layout.mode, MobileNavigationMode.bottomTabs);
      expect(layout.sidebar, isNull);
      expect(layout.body, Offset.zero & size);
    });
  }
  test('keyboard cannot turn a portrait window into the sidebar layout', () {
    final layout = MobileWindowLayout.resolve(
      media: const MediaQueryData(
        size: Size(690, 829),
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        viewInsets: EdgeInsets.only(bottom: 500),
      ),
    );
    expect(layout.mode, MobileNavigationMode.bottomTabs);
    expect(layout.windowPolicy.usesWideLayout, isFalse);
  });
  test('wide surfaces reach the bottom while pane content retains safety', () {
    const size = Size(951, 669);
    const media = MediaQueryData(
      size: size,
      viewPadding: EdgeInsets.only(right: 84, bottom: 34),
      padding: EdgeInsets.only(right: 84, bottom: 34),
    );
    final layout = MobileWindowLayout.resolve(
      media: media,
      native: const MobileNavigationGeometry(
        edge: MobileNavigationEdge.right,
        viewSize: size,
        safeRect: Rect.fromLTWH(0, 0, 867, 635),
        occlusions: [],
      ),
    );
    expect(layout.mode, MobileNavigationMode.sidebar);
    expect(layout.body.bottom, size.height);
    expect(layout.availableContentRect, const Rect.fromLTWH(288, 0, 563, 669));
    expect(layout.viewport, const Rect.fromLTWH(288, 0, 663, 669));
    expect(layout.viewport.width, greaterThan(layout.body.width));
    expect(layout.sidebar!.top, 16);
    expect(size.height - layout.sidebar!.bottom, 16);
    expect(
      mobilePaneMedia(
        media,
        layout.body,
        safeRect: layout.contentSafeRect,
      ).padding.bottom,
      34,
    );
    expect(
      mobilePaneMedia(
        media,
        layout.sidebar!,
        safeRect: layout.contentSafeRect,
      ).padding.bottom,
      18,
    );
  });
  test(
    'native foreground insets survive missing Flutter padding and keyboard',
    () {
      const media = MediaQueryData(size: Size(951, 669));
      const pane = Rect.fromLTWH(300, 0, 440, 669);
      const safe = Rect.fromLTWH(0, 0, 867, 635);
      final local = mobilePaneMedia(media, pane, safeRect: safe);
      expect(local.padding.bottom, 34);
      expect(local.viewPadding.bottom, 34);
      final keyboard = mobilePaneMedia(
        media.copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
        pane,
        safeRect: safe,
      );
      expect(keyboard.padding.bottom, 0);
      expect(keyboard.viewPadding.bottom, 34);
      expect(keyboard.viewInsets.bottom, 300);
    },
  );
  test(
    'an occlusion keeps compact sidebar available when expanded width fails',
    () {
      const hole = Rect.fromLTWH(224, 0, 56, 700);
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(size: Size(900, 700)),
        native: const MobileNavigationGeometry(
          edge: MobileNavigationEdge.none,
          viewSize: Size(900, 700),
          safeRect: Rect.fromLTWH(0, 0, 900, 700),
          occlusions: [hole],
        ),
      );
      expect(layout.mode, MobileNavigationMode.sidebar);
      expect(layout.sidebar!.width, inInclusiveRange(200, 208));
      expect(layout.body.overlaps(hole), isFalse);
    },
  );
  test('wide Android vertical hinge remains outside both panes', () {
    const hinge = Rect.fromLTWH(350, 0, 24, 700);
    final layout = MobileWindowLayout.resolve(
      media: const MediaQueryData(
        size: Size(740, 700),
        displayFeatures: [
          DisplayFeature(
            bounds: hinge,
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      ),
    );
    expect(layout.mode, MobileNavigationMode.sidebar);
    expect(layout.body.overlaps(hinge), isFalse);
    expect(layout.sidebar!.overlaps(hinge), isFalse);
    expect(layout.viewport.overlaps(hinge), isFalse);
    expect(layout.availableContentRect!.overlaps(hinge), isFalse);
  });
  test('horizontal hinge gives the content one contiguous usable pane', () {
    const hinge = Rect.fromLTWH(0, 340, 900, 20);
    final layout = MobileWindowLayout.resolve(
      media: const MediaQueryData(
        size: Size(900, 720),
        displayFeatures: [
          DisplayFeature(
            bounds: hinge,
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
    );
    expect(layout.mode, MobileNavigationMode.sidebar);
    expect(layout.body.overlaps(hinge), isFalse);
    expect(layout.sidebar!.overlaps(hinge), isFalse);
    expect(layout.viewport.overlaps(hinge), isFalse);
  });
  test('flat zero-width fold does not split the window', () {
    final layout = MobileWindowLayout.resolve(
      media: const MediaQueryData(
        size: Size(740, 700),
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(370, 0, 0, 700),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      ),
    );
    expect(layout.mode, MobileNavigationMode.sidebar);
    final withoutFold = MobileWindowLayout.resolve(
      media: const MediaQueryData(size: Size(740, 700)),
    );
    expect(layout.body, withoutFold.body);
    expect(layout.body.left, lessThan(370));
    expect(layout.body.right, greaterThan(370));
  });
  test(
    'stale native size is ignored and onboarding never gets wallet navigation',
    () {
      final layout = MobileWindowLayout.resolve(
        media: const MediaQueryData(size: Size(492, 720)),
        native: geometry(const Size(900, 720)),
      );
      expect(layout.mode, MobileNavigationMode.bottomTabs);
      expect(
        MobileWindowLayout.resolve(
          media: const MediaQueryData(size: Size(900, 720)),
          wallet: false,
        ).mode,
        MobileNavigationMode.bottomTabs,
      );
    },
  );
  test(
    'pane metrics project keyboard, padding, gestures and display features',
    () {
      const media = MediaQueryData(
        size: Size(900, 720),
        viewPadding: EdgeInsets.fromLTRB(20, 40, 30, 24),
        padding: EdgeInsets.fromLTRB(20, 40, 30, 0),
        viewInsets: EdgeInsets.only(bottom: 300),
        systemGestureInsets: EdgeInsets.fromLTRB(18, 0, 18, 24),
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(600, 0, 20, 720),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      final pane = mobilePaneMedia(
        media,
        const Rect.fromLTWH(400, 40, 440, 656),
      );
      expect(pane.size, const Size(440, 656));
      expect(pane.viewPadding, EdgeInsets.zero);
      expect(pane.viewInsets.bottom, 276);
      expect(pane.systemGestureInsets, EdgeInsets.zero);
      expect(
        pane.displayFeatures.single.bounds,
        const Rect.fromLTWH(200, 0, 20, 656),
      );
    },
  );
  test(
    'native parser rejects invalid values and normalizes local coordinates',
    () {
      final payload = {
        'supported': true,
        'edge': 'right',
        'bounds': {'x': 10, 'y': 20, 'width': 492, 'height': 720},
        'safeRect': {'x': 10, 'y': 20, 'width': 408, 'height': 720},
        'occlusions': <Object>[],
        'divisions': <Object>[],
      };
      expect(
        MobileNavigationGeometry.fromNative(payload)!.safeRect,
        const Rect.fromLTWH(0, 0, 408, 720),
      );
      expect(
        MobileNavigationGeometry.fromNative({
          ...payload,
          'bounds': {'x': 0, 'y': 0, 'width': double.nan, 'height': 720},
        }),
        isNull,
      );
    },
  );
}
