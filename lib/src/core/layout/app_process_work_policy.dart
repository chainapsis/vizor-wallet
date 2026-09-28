import 'app_form_factor.dart';
import '../lifecycle/app_shutdown_signal.dart';

/// Whether process-owned work may continue in the current app lifecycle.
///
/// Mobile hands long-running work over to platform background facilities when
/// available, so Dart-owned work remains foreground-only. Desktop keeps the
/// same work alive while its app process is running, even when every window is
/// hidden.
bool canRunAppProcessWork({
  required bool isInForeground,
  AppFormFactor formFactor = kAppFormFactor,
  AppShutdownSignal? shutdownSignal,
}) {
  return !(shutdownSignal ?? appShutdownSignal).isShuttingDown &&
      (isInForeground || formFactor == AppFormFactor.desktop);
}
