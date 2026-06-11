// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/send/widgets/verify_address_modal.dart';

/// 200-character Figma-shaped placeholder address: 8 lines × 5 groups, with
/// the mock's repeated group content so Widgetbook screenshots can compare
/// against the design without fixture noise.
const _sampleFullAddress =
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345'
    'u17dc12345123451234512345';

const _sampleTransparentAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

/// Verify-address modal, unknown recipient: shield header, full-UA grid,
/// Close only. (Toggle the Widgetbook theme for the light variant.)
Widget buildVerifyAddressUnknownUseCase(BuildContext context) {
  return _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleFullAddress,
      variant: VerifyAddressModalVariant.unknown,
      onClose: () {},
    ),
  );
}

/// Verify-address modal, unknown transparent recipient: transparent-address
/// header, full-address grid, Close only.
Widget buildVerifyAddressUnknownTransparentUseCase(BuildContext context) {
  return _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleTransparentAddress,
      variant: VerifyAddressModalVariant.unknown,
      unknownAddressKind: VerifyAddressModalAddressKind.transparent,
      onClose: () {},
    ),
  );
}

/// Verify-address modal, known contact: avatar + name header with the
/// previous-transactions sub-line, full-UA grid, Close only.
Widget buildVerifyAddressKnownContactUseCase(BuildContext context) {
  return _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleFullAddress,
      variant: VerifyAddressModalVariant.knownContact,
      contactName: 'Mike',
      contactProfilePictureId: 'pfp-02',
      previousTransactionCount: 12,
      onClose: () {},
    ),
  );
}

/// Trailing-pane stand-in on the window background: a pane-radius surface
/// hosting the real [AppPaneModalOverlay] scrim with the modal centered,
/// mirroring how the live review screen presents its overlays.
class _AddressVerifyModalFrame extends StatelessWidget {
  const _AddressVerifyModalFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.window,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.background.base,
            borderRadius: BorderRadius.circular(AppWindowSizing.paneRadius),
          ),
          child: Stack(
            children: [AppPaneModalOverlay(onDismiss: () {}, child: child)],
          ),
        ),
      ),
    );
  }
}
