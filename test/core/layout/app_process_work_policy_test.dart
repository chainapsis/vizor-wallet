import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';

void main() {
  test('mobile process work remains foreground-only', () {
    expect(
      canRunAppProcessWork(
        isInForeground: true,
        formFactor: AppFormFactor.mobile,
      ),
      isTrue,
    );
    expect(
      canRunAppProcessWork(
        isInForeground: false,
        formFactor: AppFormFactor.mobile,
      ),
      isFalse,
    );
  });

  test('desktop process work continues while windows are hidden', () {
    expect(
      canRunAppProcessWork(
        isInForeground: true,
        formFactor: AppFormFactor.desktop,
      ),
      isTrue,
    );
    expect(
      canRunAppProcessWork(
        isInForeground: false,
        formFactor: AppFormFactor.desktop,
      ),
      isTrue,
    );
  });
}
