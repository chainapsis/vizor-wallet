import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/create/address_types_screen.dart';

void main() {
  test('uses horizontal card scroll on mobile platforms', () {
    expect(usesMobileAddressTypesCardScroll(TargetPlatform.iOS), isTrue);
    expect(usesMobileAddressTypesCardScroll(TargetPlatform.android), isTrue);
  });

  test('keeps the fixed cards row on desktop and web', () {
    expect(usesMobileAddressTypesCardScroll(TargetPlatform.macOS), isFalse);
    expect(usesMobileAddressTypesCardScroll(TargetPlatform.linux), isFalse);
    expect(
      usesMobileAddressTypesCardScroll(TargetPlatform.iOS, isWeb: true),
      isFalse,
    );
  });
}
