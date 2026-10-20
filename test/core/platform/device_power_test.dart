import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/platform/device_power.dart';

void main() {
  test('scan power follows the thermal state and power saving', () {
    int level(int thermal, {bool lowPower = false}) =>
        syncScanPowerFor(DevicePower(thermal: thermal, lowPower: lowPower));

    expect(level(0), 0);
    expect(level(0, lowPower: true), 1);
    expect(level(1), 0);
    expect(level(1, lowPower: true), 1);
    expect(level(2), 1);
    expect(level(3, lowPower: true), 1);
  });

  test('device power events need an int thermal state and a bool', () {
    expect(
      DevicePower.fromEvent({'thermal': 2, 'lowPower': true}),
      const DevicePower(thermal: 2, lowPower: true),
    );
    expect(DevicePower.fromEvent({'thermal': '2', 'lowPower': true}), isNull);
    expect(DevicePower.fromEvent({'thermal': 2}), isNull);
    expect(DevicePower.fromEvent(null), isNull);
  });
}
