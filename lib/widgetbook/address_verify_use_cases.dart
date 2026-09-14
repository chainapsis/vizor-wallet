// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../src/features/send/widgets/verify_address_modal.dart';
import 'support/wb_layout.dart';

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

/// A recipient on another chain: what the Pay and swap payout rows verify,
/// and the only caller of the `external` header kind.
const _sampleExternalAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

const _sampleContactName = 'Mike';
const _sampleContactPictureId = 'pfp-02';

/// Showcase address that mixes letter `O` and digit `0` so Geist Mono's
/// glyph distinction is visible in Widgetbook / figma-compare.
const kAddressViewerShowcaseAddress =
    'u10O0qrstuvwxyzO0O0abcdefghijklO0O0mnopqrstuvwxO0O001234567890O0O0'
    'yzABCDEFGHJKO0O0LMNPQRSTUVWXO0O0';

/// The address each unknown-recipient header kind is shown over.
String verifyAddressSampleAddressFor(VerifyAddressModalAddressKind kind) {
  return switch (kind) {
    VerifyAddressModalAddressKind.shielded => _sampleFullAddress,
    VerifyAddressModalAddressKind.transparent => _sampleTransparentAddress,
    VerifyAddressModalAddressKind.external => _sampleExternalAddress,
  };
}

/// One desktop verify-address modal; every builder below delegates here so the
/// gallery and figma_compare render the same tree.
///
/// [unknownAddressKind] picks the address too, because a transparent header
/// over a unified address is a pairing the app never produces. The contact
/// variant keeps the unified address: its header names the contact, not a pool.
Widget verifyAddressModalFixture({
  VerifyAddressModalVariant variant = VerifyAddressModalVariant.unknown,
  VerifyAddressModalAddressKind unknownAddressKind =
      VerifyAddressModalAddressKind.shielded,
  int? previousTransactionCount,
  bool glyphShowcaseAddress = false,
}) {
  final knownContact = variant == VerifyAddressModalVariant.knownContact;
  final address = glyphShowcaseAddress
      ? kAddressViewerShowcaseAddress
      : knownContact
      ? _sampleFullAddress
      : verifyAddressSampleAddressFor(unknownAddressKind);
  return _AddressVerifyModalFrame(
    child: VerifyAddressModal(
      address: address,
      variant: variant,
      unknownAddressKind: unknownAddressKind,
      contactName: knownContact ? _sampleContactName : null,
      contactProfilePictureId: knownContact ? _sampleContactPictureId : null,
      previousTransactionCount: previousTransactionCount,
      onClose: _noop,
    ),
  );
}

/// One mobile verify-address sheet.
///
/// Title and leading widget come from the caller, so the contact option
/// rebuilds what `mobile_send_screen.dart` passes for a saved recipient: the
/// contact label as the title and a large [AppProfilePicture] beside it.
Widget mobileAddressVerifySheetFixture({
  bool knownContact = false,
  bool glyphShowcaseAddress = false,
}) {
  return _MobileAddressVerifyFrame(
    child: MobileAddressVerifySheet(
      title: knownContact ? _sampleContactName : 'Unknown shielded address',
      address: glyphShowcaseAddress
          ? kAddressViewerShowcaseAddress
          : _sampleFullAddress,
      leading: knownContact
          ? const AppProfilePicture(
              profilePictureId: _sampleContactPictureId,
              size: AppProfilePictureSize.large,
            )
          : null,
      onClose: _noop,
    ),
  );
}

/// Verify-address modal, unknown recipient: shield header, wrapping
/// address, copy control. (Toggle the Widgetbook theme for the light variant.)
Widget buildVerifyAddressUnknownUseCase(BuildContext context) =>
    verifyAddressModalFixture();

/// Verify-address modal, unknown transparent recipient.
Widget buildVerifyAddressUnknownTransparentUseCase(BuildContext context) =>
    verifyAddressModalFixture(
      unknownAddressKind: VerifyAddressModalAddressKind.transparent,
    );

/// Verify-address modal, known contact.
Widget buildVerifyAddressKnownContactUseCase(BuildContext context) =>
    verifyAddressModalFixture(
      variant: VerifyAddressModalVariant.knownContact,
      previousTransactionCount: 12,
    );

/// Desktop viewer with a mixed `O`/`0` address for glyph comparison.
Widget buildVerifyAddressActionFooterUseCase(BuildContext context) =>
    verifyAddressModalFixture(glyphShowcaseAddress: true);

/// Mobile viewer with a mixed `O`/`0` address for glyph comparison.
Widget buildMobileVerifyAddressActionFooterUseCase(BuildContext context) =>
    mobileAddressVerifySheetFixture(glyphShowcaseAddress: true);

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
    return WbDesktopWindowBox(
      child: ColoredBox(
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
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
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
      ),
    );
  }
}
