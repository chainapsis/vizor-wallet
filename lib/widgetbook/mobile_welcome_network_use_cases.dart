import 'package:flutter/material.dart';

import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/settings/widgets/mobile/mobile_tor_control.dart';
import '../src/features/onboarding/mobile/mobile_network_settings_sheet.dart';
import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/rpc_endpoint_provider.dart';
import 'mobile_welcome_preview_scope.dart';

Widget buildMobileWelcomeNetworkOff(BuildContext context) =>
    _preview(const NetworkPrivacyState.off());
Widget buildMobileWelcomeNetworkConnecting(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
  ),
);
Widget buildMobileWelcomeNetworkConnected(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connected,
  ),
);
Widget buildMobileWelcomeNetworkSwitching(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
    targetTorEnabled: false,
  ),
);
Widget buildMobileWelcomeNetworkFailed(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.failed,
  ),
);
Widget buildMobileWelcomeNetworkSaveFailed(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: false,
    status: NetworkPrivacyConnectionStatus.failed,
    targetTorEnabled: true,
  ),
);
Widget buildMobileWelcomeNetworkDirectSaveFailed(BuildContext context) =>
    _preview(
      const NetworkPrivacyState(
        torEnabled: false,
        status: NetworkPrivacyConnectionStatus.failed,
        targetTorEnabled: false,
      ),
    );
Widget buildMobileWelcomeNetworkSwitchFailed(BuildContext context) => _preview(
  const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.failed,
    targetTorEnabled: false,
  ),
);
Widget buildMobileWelcomeNetworkWrongChain(BuildContext context) => _preview(
  const NetworkPrivacyState.off(),
  rpcError: const FormatException(
    'Endpoint is for test, but this wallet uses main.',
  ),
);
Widget buildMobileWelcomeNetworkRpcSaveFailed(BuildContext context) => _preview(
  const NetworkPrivacyState.off(),
  rpcError: const RpcEndpointSaveException('Preview storage failure'),
);
Widget buildMobileWelcomeNetworkRpcPending(BuildContext context) =>
    _preview(const NetworkPrivacyState.off(), rpcPending: true);

Widget _preview(
  NetworkPrivacyState state, {
  Object? rpcError,
  bool rpcPending = false,
}) => mobileWelcomePreviewScope(
  // This preview already owns an inline modal; the scope keeps Welcome's
  // startup presentation from stacking another one on top of the scene.
  state: state,
  child: _Preview(rpcPending: rpcPending, rpcError: rpcError),
);

class _Preview extends StatefulWidget {
  const _Preview({required this.rpcPending, this.rpcError});
  final bool rpcPending;
  final Object? rpcError;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _dismissal = ValueNotifier(true);
  final _controller = TextEditingController(text: 'preview.example:443');
  final _focus = FocusNode();

  @override
  void dispose() {
    _dismissal.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: MobileModalOverlay(
      background: const MobileWelcomeScreen(animateBackground: false),
      child: widget.rpcPending || widget.rpcError != null
          ? MobileNetworkSettingsContent(
              torControl: MobileTorControl(
                enabled: !widget.rpcPending,
                useGeneralDescription: true,
              ),
              current: defaultRpcEndpointConfig('main'),
              controller: _controller,
              focusNode: _focus,
              onChanged: (_) {},
              onSubmit: () {},
              onClose: widget.rpcPending ? null : () {},
              canUpdate: !widget.rpcPending,
              submitting: widget.rpcPending,
              error: widget.rpcError is FormatException
                  ? (widget.rpcError as FormatException).message
                  : widget.rpcError != null
                  ? "Couldn't save the endpoint. Try again."
                  : null,
            )
          : MobileNetworkSettingsSheet(dismissal: _dismissal),
    ),
  );
}
