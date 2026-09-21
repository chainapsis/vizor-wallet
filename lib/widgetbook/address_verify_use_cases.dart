// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../src/features/send/widgets/verify_address_modal.dart';

/// 200-character placeholder address used by the existing unknown/contact
/// cases so Widgetbook screenshots stay stable.
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

/// Showcase address that mixes letter `O` and digit `0` so Geist Mono's
/// glyph distinction is visible in Widgetbook / figma-compare.
const kAddressViewerShowcaseAddress =
    'u10O0qrstuvwxyzO0O0abcdefghijklO0O0mnopqrstuvwxO0O001234567890O0O0'
    'yzABCDEFGHJKO0O0LMNPQRSTUVWXO0O0';

/// Verify-address modal, unknown recipient: shield header, wrapping
/// address, copy control. (Toggle the Widgetbook theme for the light variant.)
Widget buildVerifyAddressUnknownUseCase(BuildContext context) {
  return const _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleFullAddress,
      variant: VerifyAddressModalVariant.unknown,
      onClose: _noop,
    ),
  );
}

/// Verify-address modal, unknown transparent recipient.
Widget buildVerifyAddressUnknownTransparentUseCase(BuildContext context) {
  return const _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleTransparentAddress,
      variant: VerifyAddressModalVariant.unknown,
      unknownAddressKind: VerifyAddressModalAddressKind.transparent,
      onClose: _noop,
    ),
  );
}

/// Verify-address modal, known contact.
Widget buildVerifyAddressKnownContactUseCase(BuildContext context) {
  return const _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: _sampleFullAddress,
      variant: VerifyAddressModalVariant.knownContact,
      contactName: 'Mike',
      contactProfilePictureId: 'pfp-02',
      previousTransactionCount: 12,
      onClose: _noop,
    ),
  );
}

/// Desktop viewer with a mixed `O`/`0` address for glyph comparison.
Widget buildVerifyAddressActionFooterUseCase(BuildContext context) {
  return const _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: kAddressViewerShowcaseAddress,
      variant: VerifyAddressModalVariant.unknown,
      onClose: _noop,
    ),
  );
}

/// Mobile viewer with a mixed `O`/`0` address for glyph comparison.
Widget buildMobileVerifyAddressActionFooterUseCase(BuildContext context) {
  return const _MobileAddressVerifyFrame(
    child: MobileAddressVerifySheet(
      title: 'Unknown shielded address',
      address: kAddressViewerShowcaseAddress,
      onClose: _noop,
    ),
  );
}

void _noop() {}

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
            children: [AppPaneModalOverlay(onDismiss: _noop, child: child)],
          ),
        ),
      ),
    );
  }
}

class _MobileAddressVerifyFrame extends StatelessWidget {
  const _MobileAddressVerifyFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 393,
      height: 852,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          viewPadding: EdgeInsets.only(top: 55, bottom: 34),
        ),
        child: ColoredBox(
          color: colors.background.neutralScrim,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: MobileModalCard(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
