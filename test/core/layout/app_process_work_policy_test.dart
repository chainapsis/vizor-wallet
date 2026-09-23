import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/lifecycle/app_shutdown_signal.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';

void main() {
  test('exit blocks foreground and hidden work on both form factors once', () {
    final shutdown = AppShutdownSignal();
    addTearDown(shutdown.dispose);
    var notifications = 0;
    shutdown.addListener(() => notifications++);
    shutdown.begin();
    shutdown.begin();
    expect(notifications, 1);
    for (final mode in AppFormFactor.values) {
      for (final foreground in [false, true]) {
        expect(
          canRunAppProcessWork(
            isInForeground: foreground,
            formFactor: mode,
            shutdownSignal: shutdown,
          ),
          isFalse,
        );
      }
    }
  });
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
