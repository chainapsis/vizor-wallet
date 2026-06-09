// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; imports of it are confined to
// `lib/widgetbook/` and `lib/widgetbook.dart`, which are not reachable from
// the production entry point `lib/main.dart`.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import 'address_book_use_cases.dart';
import 'activity_use_cases.dart';
import 'button_use_cases.dart';
import 'chip_use_cases.dart';
import 'context_menu_use_cases.dart';
import 'color_use_cases.dart';
import 'home_desktop_use_cases.dart';
import 'icon_use_cases.dart';
import 'screen_use_cases.dart';
import 'send_use_cases.dart';
import 'swap_use_cases.dart';
import 'text_field_use_cases.dart';
import 'token_use_cases.dart';
import 'toast_use_cases.dart';
import 'typography_use_cases.dart';

/// Top-level Widgetbook app for the Zcash design system.
///
/// Only color tokens are registered in this first pass; more components will
/// be added as the design system grows. The ThemeAddon wraps every use case
/// in [AppTheme] with either [AppThemeData.dark] or [AppThemeData.light], so
/// the page chrome reacts to the selected theme while individual swatches
/// always show both dark and light values side-by-side.
class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key});

  static const _initialRoute = String.fromEnvironment(
    'VIZOR_WIDGETBOOK_INITIAL_ROUTE',
    defaultValue: '/',
  );

  @override
  Widget build(BuildContext context) {
    // `.material` instead of the default `Widgetbook()` because the default
    // `widgetsAppBuilder` in widgetbook 3.22.0 constructs a `WidgetsApp`
    // without a `pageRouteBuilder` and throws on first build. The MaterialApp
    // wrapper is only chrome for Widgetbook's own navigation — use cases
    // still render inside `AppTheme` via the ThemeAddon below.
    return Widgetbook.material(
      initialRoute: _initialRoute,
      addons: [
        ThemeAddon<AppThemeData>(
          themes: const [
            WidgetbookTheme(name: 'Dark', data: AppThemeData.dark),
            WidgetbookTheme(name: 'Light', data: AppThemeData.light),
          ],
          themeBuilder: (context, theme, child) =>
              AppTheme(data: theme, child: child),
          initialTheme: const WidgetbookTheme(
            name: 'Dark',
            data: AppThemeData.dark,
          ),
        ),
      ],
      directories: [
        WidgetbookFolder(
          name: 'Screens',
          children: [
            WidgetbookFolder(
              name: 'Home',
              children: [
                WidgetbookComponent(
                  name: 'Desktop',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Importing',
                      builder: buildHomeDesktopImportingUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'No balance',
                      builder: buildHomeDesktopNoBalanceUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'No activity',
                      builder: buildHomeDesktopNoActivityUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Default',
                      builder: buildHomeDesktopDefaultUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Hide balance & Keystone',
                      builder: buildHomeDesktopKeystoneUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Accounts',
                      builder: buildHomeDesktopAccountsUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Accounts - Scroll',
                      builder: buildHomeDesktopAccountsScrollUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Notice - Password recovery',
                      builder: buildHomeDesktopPasswordRecoveryNoticeUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Notice - Shield queued',
                      builder: buildHomeDesktopShieldQueuedNoticeUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Notice - Sync failure',
                      builder: buildHomeDesktopSyncFailureNoticeUseCase,
                    ),
                  ],
                ),
              ],
            ),
            WidgetbookFolder(
              name: 'Onboarding',
              children: [
                WidgetbookComponent(
                  name: 'Accounts',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Many Accounts',
                      builder: buildAccountsManyUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Welcome',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Large',
                      builder: buildWelcomeLargeUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Unlock',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Login',
                      builder: buildUnlockLoginUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Lost Password',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Countdown',
                      builder: buildLostPasswordCountdownUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Enabled',
                      builder: buildLostPasswordEnabledUseCase,
                    ),
                  ],
                ),
              ],
            ),
            WidgetbookFolder(
              name: 'Swap',
              children: [
                WidgetbookComponent(
                  name: 'Swap Page',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Input active - Pay amount',
                      builder: buildSwapPageFigmaNode1UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Input active - Receive amount',
                      builder: buildSwapPageFigmaNode2UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Amount entered',
                      builder: buildSwapPageFigmaNode3UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Direction switched',
                      builder: buildSwapPageFigmaNode5UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Fiat value input',
                      builder: buildSwapPageFigmaNode6UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Unsupported fiat price',
                      builder: buildSwapPageUnsupportedFiatUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Swap Modals',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Address modal',
                      builder: buildSwapAddressModalFigmaNode7UseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Address scan - Permission',
                      builder: buildSwapAddressScanModalPermissionUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Address scan - Denied',
                      builder: buildSwapAddressScanModalDeniedUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Address scan - Active',
                      builder: buildSwapAddressScanModalActiveUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Address scan - Loading',
                      builder: buildSwapAddressScanModalLoadingUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Slippage modal',
                      builder: buildSwapSlippageModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Slippage custom',
                      builder: buildSwapSlippageModalCustomUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Slippage invalid',
                      builder: buildSwapSlippageModalInvalidUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Asset modal',
                      builder: buildSwapAssetModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Asset modal - Empty',
                      builder: buildSwapAssetModalEmptyUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Swap Review',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Default',
                      builder: buildSwapReviewDefaultUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'ZEC to external',
                      builder: buildSwapReviewZecToExternalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amount - Left',
                      builder: buildSwapReviewLargeLeftAmountUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amount - Right',
                      builder: buildSwapReviewLargeRightAmountUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amounts - Both',
                      builder: buildSwapReviewLargeAmountsUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Swap Deposit',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Duration',
                      builder: buildSwapDepositDurationUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Countdown',
                      builder: buildSwapDepositCountdownUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Memo QR',
                      builder: buildSwapDepositMemoQrUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Hardware ZEC',
                      builder: buildSwapDepositHardwareZecUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Timeout',
                      builder: buildSwapDepositTimeoutUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Swap Status',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Progress',
                      builder: buildSwapStatusProgressUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Progress next step',
                      builder: buildSwapStatusProgressNextStepUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amount - Left',
                      builder: buildSwapStatusLargeLeftAmountUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amount - Right',
                      builder: buildSwapStatusLargeRightAmountUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Large amounts - Both',
                      builder: buildSwapStatusLargeAmountsUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Captured fiat basis',
                      builder: buildSwapStatusCapturedFiatUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Details collapsed',
                      builder: buildSwapStatusDetailsCollapsedUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Details expanded',
                      builder: buildSwapStatusDetailsExpandedUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Completed',
                      builder: buildSwapStatusCompletedUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Failed',
                      builder: buildSwapStatusFailedUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Incomplete deposit',
                      builder: buildSwapStatusIncompleteDepositUseCase,
                    ),
                  ],
                ),
              ],
            ),
            WidgetbookFolder(
              name: 'Send',
              children: [
                WidgetbookComponent(
                  name: 'Send page',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Empty state',
                      builder: buildSendEmptyUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Shielded - filled',
                      builder: buildSendShieldedFilledUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Shielded - memo too long',
                      builder: buildSendMemoTooLongUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Transparent recipient',
                      builder: buildSendTransparentUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Contact selected',
                      builder: buildSendContactSelectedUseCase,
                    ),
                  ],
                ),
              ],
            ),
            WidgetbookFolder(
              name: 'Address book',
              children: [
                WidgetbookComponent(
                  name: 'Page',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Contacts list',
                      builder: buildAddressBookContactsListUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Contacts list - Solana menu',
                      builder: buildAddressBookSolanaMenuUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'No contacts',
                      builder: buildAddressBookNoContactsUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Empty search',
                      builder: buildAddressBookEmptySearchUseCase,
                    ),
                  ],
                ),
                WidgetbookComponent(
                  name: 'Modals',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Add contact',
                      builder: buildAddressBookAddContactModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Avatar picker',
                      builder: buildAddressBookAvatarModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Network selector',
                      builder: buildAddressBookNetworkModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Network selector - Empty',
                      builder: buildAddressBookNetworkModalEmptyUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Edit contact',
                      builder: buildAddressBookEditContactModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Remove contact',
                      builder: buildAddressBookRemoveContactModalUseCase,
                    ),
                    WidgetbookUseCase(
                      name: 'Contact picker',
                      builder: buildAddressBookContactPickerModalUseCase,
                    ),
                  ],
                ),
              ],
            ),
            WidgetbookFolder(
              name: 'Activity',
              children: [
                WidgetbookComponent(
                  name: 'Page',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Default',
                      builder: buildActivityPageUseCase,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Tokens',
          children: [
            WidgetbookComponent(
              name: 'Typography',
              useCases: [
                WidgetbookUseCase(
                  name: 'All',
                  builder: buildTypographyAllUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Spacing',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildSpacingUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Icons',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildIconsAllUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Icon Size',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildIconSizeUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Radii',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildRadiiUseCase),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Components',
          children: [
            WidgetbookComponent(
              name: 'Button',
              useCases: [
                WidgetbookUseCase(
                  name: 'Matrix',
                  builder: buildButtonMatrixUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Interactive',
                  builder: buildButtonInteractiveUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Primary / Large',
                  builder: buildButtonPrimaryLargeUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Primary / Medium',
                  builder: buildButtonPrimaryMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Primary / Small',
                  builder: buildButtonPrimarySmallUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Secondary / Large',
                  builder: buildButtonSecondaryLargeUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Secondary / Medium',
                  builder: buildButtonSecondaryMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Secondary / Small',
                  builder: buildButtonSecondarySmallUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Ghost / Large',
                  builder: buildButtonGhostLargeUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Ghost / Medium',
                  builder: buildButtonGhostMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Ghost / Small',
                  builder: buildButtonGhostSmallUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Destructive / Large',
                  builder: buildButtonDestructiveLargeUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Destructive / Medium',
                  builder: buildButtonDestructiveMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Destructive / Small',
                  builder: buildButtonDestructiveSmallUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Chip',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildChipUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Context Menu',
              useCases: [
                WidgetbookUseCase(
                  name: 'Gallery',
                  builder: buildContextMenuGalleryUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Contact actions',
                  builder: buildContextMenuContactUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Account actions',
                  builder: buildContextMenuAccountUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Narrow width',
                  builder: buildContextMenuNarrowUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Loading Icon',
              useCases: [
                WidgetbookUseCase(
                  name: 'Animated',
                  builder: buildLoadingIconAnimatedUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Static',
                  builder: buildLoadingIconStaticUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Text Field',
              useCases: [
                WidgetbookUseCase(
                  name: 'Gallery',
                  builder: buildTextFieldGalleryUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Interactive',
                  builder: buildTextFieldInteractiveUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Toast',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildToastUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Swap Widget',
              useCases: [
                WidgetbookUseCase(
                  name: 'Input active - Pay amount',
                  builder: buildSwapWidgetFigmaNode1UseCase,
                ),
                WidgetbookUseCase(
                  name: 'Input active - Receive amount',
                  builder: buildSwapWidgetFigmaNode2UseCase,
                ),
                WidgetbookUseCase(
                  name: 'Amount entered',
                  builder: buildSwapWidgetFigmaNode3UseCase,
                ),
                WidgetbookUseCase(
                  name: 'Direction switched',
                  builder: buildSwapWidgetFigmaNode5UseCase,
                ),
                WidgetbookUseCase(
                  name: 'Fiat value input',
                  builder: buildSwapWidgetFigmaNode6UseCase,
                ),
                WidgetbookUseCase(
                  name: 'Unsupported fiat price',
                  builder: buildSwapWidgetUnsupportedFiatUseCase,
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Colors',
          children: [
            WidgetbookComponent(
              name: 'Primitives',
              useCases: [
                WidgetbookUseCase(
                  name: 'Neutral',
                  builder: buildPrimitivesNeutralUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Crimson',
                  builder: buildPrimitivesCrimsonUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Plum',
                  builder: buildPrimitivesPlumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Gold',
                  builder: buildPrimitivesGoldUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Green',
                  builder: buildPrimitivesGreenUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'Background',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildBackgroundUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Surface',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildSurfaceUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Border',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildBorderUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Text',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildTextUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Icon',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildIconUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Button',
              useCases: [
                WidgetbookUseCase(
                  name: 'Primary',
                  builder: buildButtonPrimaryUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Secondary',
                  builder: buildButtonSecondaryUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Ghost & Destructive',
                  builder: buildButtonGhostDestructiveUseCase,
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'State',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildStateUseCase),
              ],
            ),
            WidgetbookComponent(
              name: 'Fade',
              useCases: [
                WidgetbookUseCase(name: 'All', builder: buildFadeUseCase),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
