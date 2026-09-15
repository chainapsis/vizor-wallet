import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/button_use_cases.dart' as button;
import 'package:zcash_wallet/widgetbook/request_amount_use_cases.dart'
    as request_amount;
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart' as screen;
import 'package:zcash_wallet/widgetbook/send_use_cases.dart' as send;
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart' as swap;
import 'package:zcash_wallet/widgetbook/text_field_use_cases.dart'
    as text_field;

// These exported names existed before the gallery refactor. Referencing them
// directly guards both their source file and WidgetBuilder signature.
void main() {
  test('capture builder exports remain source-compatible', () {
    final builders = <String, WidgetBuilder>{
      'buildButtonPrimaryLargeUseCase': button.buildButtonPrimaryLargeUseCase,
      'buildButtonPrimaryMediumUseCase': button.buildButtonPrimaryMediumUseCase,
      'buildButtonPrimarySmallUseCase': button.buildButtonPrimarySmallUseCase,
      'buildButtonSecondaryLargeUseCase':
          button.buildButtonSecondaryLargeUseCase,
      'buildButtonSecondaryMediumUseCase':
          button.buildButtonSecondaryMediumUseCase,
      'buildButtonSecondarySmallUseCase':
          button.buildButtonSecondarySmallUseCase,
      'buildButtonGhostLargeUseCase': button.buildButtonGhostLargeUseCase,
      'buildButtonGhostMediumUseCase': button.buildButtonGhostMediumUseCase,
      'buildButtonGhostSmallUseCase': button.buildButtonGhostSmallUseCase,
      'buildButtonDestructiveLargeUseCase':
          button.buildButtonDestructiveLargeUseCase,
      'buildButtonDestructiveMediumUseCase':
          button.buildButtonDestructiveMediumUseCase,
      'buildButtonDestructiveSmallUseCase':
          button.buildButtonDestructiveSmallUseCase,
      'buildButtonInteractiveUseCase': button.buildButtonInteractiveUseCase,
      'buildRequestModalStepOneEmptyUseCase':
          request_amount.buildRequestModalStepOneEmptyUseCase,
      'buildRequestModalStepOneAmountUseCase':
          request_amount.buildRequestModalStepOneAmountUseCase,
      'buildRequestModalStepOneTransparentUseCase':
          request_amount.buildRequestModalStepOneTransparentUseCase,
      'buildRequestModalStepOneAmountErrorUseCase':
          request_amount.buildRequestModalStepOneAmountErrorUseCase,
      'buildRequestModalStepTwoTransparentUseCase':
          request_amount.buildRequestModalStepTwoTransparentUseCase,
      'buildRequestMobileComposeEmptyUseCase':
          request_amount.buildRequestMobileComposeEmptyUseCase,
      'buildRequestMobileComposeUsdUseCase':
          request_amount.buildRequestMobileComposeUsdUseCase,
      'buildRequestMobileResultTransparentUseCase':
          request_amount.buildRequestMobileResultTransparentUseCase,
      'buildRequestMobileEntryUseCase':
          request_amount.buildRequestMobileEntryUseCase,
      'buildMobileAccountsManyUseCase': screen.buildMobileAccountsManyUseCase,
      'buildMobileHomeGiftCardsUseCase': screen.buildMobileHomeGiftCardsUseCase,
      'buildMobileHomeNoActivityUseCase':
          screen.buildMobileHomeNoActivityUseCase,
      'buildMobileHomeNoBalanceKeystoneUseCase':
          screen.buildMobileHomeNoBalanceKeystoneUseCase,
      'buildDesktopHomeGiftCardsUseCase':
          screen.buildDesktopHomeGiftCardsUseCase,
      'buildLostPasswordCountdownUseCase':
          screen.buildLostPasswordCountdownUseCase,
      'buildLostPasswordEnabledUseCase': screen.buildLostPasswordEnabledUseCase,
      'buildSendMemoTooLongUseCase': send.buildSendMemoTooLongUseCase,
      'buildSendPriceLoadingUseCase': send.buildSendPriceLoadingUseCase,
      'buildSwapPageFigmaNode1UseCase': swap.buildSwapPageFigmaNode1UseCase,
      'buildSwapPageFigmaNode2UseCase': swap.buildSwapPageFigmaNode2UseCase,
      'buildSwapPageFigmaNode3UseCase': swap.buildSwapPageFigmaNode3UseCase,
      'buildSwapPageFigmaNode6UseCase': swap.buildSwapPageFigmaNode6UseCase,
      'buildSwapPageUnsupportedFiatUseCase':
          swap.buildSwapPageUnsupportedFiatUseCase,
      'buildSwapWidgetFigmaNode1UseCase': swap.buildSwapWidgetFigmaNode1UseCase,
      'buildSwapWidgetFigmaNode2UseCase': swap.buildSwapWidgetFigmaNode2UseCase,
      'buildSwapWidgetFigmaNode3UseCase': swap.buildSwapWidgetFigmaNode3UseCase,
      'buildSwapWidgetFigmaNode5UseCase': swap.buildSwapWidgetFigmaNode5UseCase,
      'buildSwapWidgetFigmaNode6UseCase': swap.buildSwapWidgetFigmaNode6UseCase,
      'buildSwapWidgetUnsupportedFiatUseCase':
          swap.buildSwapWidgetUnsupportedFiatUseCase,
      'buildSwapAddressModalFigmaNode7UseCase':
          swap.buildSwapAddressModalFigmaNode7UseCase,
      'buildSwapSlippageModalUseCase': swap.buildSwapSlippageModalUseCase,
      'buildSwapSlippageModalCustomUseCase':
          swap.buildSwapSlippageModalCustomUseCase,
      'buildSwapSlippageModalInvalidUseCase':
          swap.buildSwapSlippageModalInvalidUseCase,
      'buildSwapAssetModalUseCase': swap.buildSwapAssetModalUseCase,
      'buildSwapAssetModalEmptyUseCase': swap.buildSwapAssetModalEmptyUseCase,
      'buildSwapAddressScanModalPermissionUseCase':
          swap.buildSwapAddressScanModalPermissionUseCase,
      'buildMobileSwapAddressScanRequestingUseCase':
          swap.buildMobileSwapAddressScanRequestingUseCase,
      'buildSwapAddressScanModalDeniedUseCase':
          swap.buildSwapAddressScanModalDeniedUseCase,
      'buildMobileSwapAddressScanDeniedUseCase':
          swap.buildMobileSwapAddressScanDeniedUseCase,
      'buildSwapAddressScanModalActiveUseCase':
          swap.buildSwapAddressScanModalActiveUseCase,
      'buildMobileSwapAddressScanActiveUseCase':
          swap.buildMobileSwapAddressScanActiveUseCase,
      'buildSwapAddressScanModalLoadingUseCase':
          swap.buildSwapAddressScanModalLoadingUseCase,
      'buildMobileSwapAddressScanLoadingUseCase':
          swap.buildMobileSwapAddressScanLoadingUseCase,
      'buildTextFieldInteractiveUseCase':
          text_field.buildTextFieldInteractiveUseCase,
    };
    expect(builders, hasLength(57));
  });
}
