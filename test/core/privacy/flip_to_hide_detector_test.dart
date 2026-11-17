import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/flip_to_hide_detector.dart';

const _up = -0.8;
const _down = 0.9;

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('a quick flip screen-down hides, and turning back keeps it hidden', () {
    final detector = FlipToHideDetector();

    expect(detector.add(_up, at: _ms(0), hidden: false), isNull);
    expect(
      detector.add(_down, at: _ms(300), hidden: false),
      FlipToHideAction.hide,
    );
    expect(detector.add(_up, at: _ms(800), hidden: true), isNull);
  });

  test('with amounts hidden, a flip down and back up shows them', () {
    final detector = FlipToHideDetector();

    detector.add(_up, at: _ms(0), hidden: true);
    expect(detector.add(_down, at: _ms(300), hidden: true), isNull);
    expect(
      detector.add(_up, at: _ms(1200), hidden: true),
      FlipToHideAction.show,
    );
  });

  test('a phone left screen-down past the window never shows', () {
    final detector = FlipToHideDetector();

    detector.add(_up, at: _ms(0), hidden: true);
    detector.add(_down, at: _ms(300), hidden: true);
    expect(detector.add(_up, at: _ms(2400), hidden: true), isNull);
  });

  test('a slow turn screen-down is not a flip', () {
    final detector = FlipToHideDetector();

    detector.add(_up, at: _ms(0), hidden: false);
    detector.add(0.5, at: _ms(800), hidden: false);
    expect(detector.add(_down, at: _ms(1600), hidden: false), isNull);
  });

  test('a phone screen-down when listening starts counts after facing up', () {
    final detector = FlipToHideDetector();

    expect(detector.add(_down, at: _ms(0), hidden: false), isNull);
    expect(detector.add(_up, at: _ms(500), hidden: false), isNull);
    expect(
      detector.add(_down, at: _ms(900), hidden: false),
      FlipToHideAction.hide,
    );
  });

  test('a wobble near screen-down is one flip', () {
    final detector = FlipToHideDetector();

    detector.add(_up, at: _ms(0), hidden: false);
    expect(
      detector.add(0.8, at: _ms(300), hidden: false),
      FlipToHideAction.hide,
    );
    expect(detector.add(0.6, at: _ms(400), hidden: true), isNull);
    expect(detector.add(0.8, at: _ms(500), hidden: true), isNull);
  });
}
