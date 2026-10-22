import 'package:flutter/widgets.dart';

import 'app_privacy_host.dart';
import 'native_sensitive_content_bridge.dart';
import 'route_coverage_aware.dart';

/// Excludes native window captures while this screen displays a secret.
/// Background/app-switcher privacy is owned by the native app lifecycle,
/// independently of capture exclusion. This scope requests a solid cover even
/// when its secret is hidden; ordinary screens use the app-wide blur.
class SensitiveCaptureGuard extends StatefulWidget {
  const SensitiveCaptureGuard({
    required this.sensitiveContentVisible,
    required this.child,
    super.key,
  });

  final bool sensitiveContentVisible;
  final Widget child;

  @override
  State<SensitiveCaptureGuard> createState() => _SensitiveCaptureGuardState();
}

class _SensitiveCaptureGuardState extends State<SensitiveCaptureGuard>
    with RouteCoverageAware<SensitiveCaptureGuard> {
  final _solidToken = Object();
  final _token = NativeSensitiveContentBridge.createToken();

  @override
  void initState() {
    super.initState();
    AppPrivacyPolicy.setSolidScope(_solidToken, true);
    _syncVisibility();
  }

  @override
  void didUpdateWidget(covariant SensitiveCaptureGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensitiveContentVisible != widget.sensitiveContentVisible) {
      _syncVisibility();
    }
  }

  void _syncVisibility() => NativeSensitiveContentBridge.updateToken(
    _token,
    widget.sensitiveContentVisible,
  );

  @override
  void dispose() {
    AppPrivacyPolicy.setSolidScope(_solidToken, false);
    NativeSensitiveContentBridge.clearToken(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Include access gates and hidden secrets; retain solid through transitions.
    AppPrivacyPolicy.setSolidScope(
      _solidToken,
      !isCoveredByNextRoute || TickerMode.valuesOf(context).enabled,
    );
    return widget.child;
  }
}
