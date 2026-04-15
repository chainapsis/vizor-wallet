// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; imports of it are confined to
// `lib/widgetbook/` and `lib/widgetbook.dart`, which are not reachable from
// the production entry point `lib/main.dart`.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import 'button_use_cases.dart';
import 'color_use_cases.dart';
import 'screen_use_cases.dart';
import 'token_use_cases.dart';
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

  @override
  Widget build(BuildContext context) {
    // `.material` instead of the default `Widgetbook()` because the default
    // `widgetsAppBuilder` in widgetbook 3.22.0 constructs a `WidgetsApp`
    // without a `pageRouteBuilder` and throws on first build. The MaterialApp
    // wrapper is only chrome for Widgetbook's own navigation — use cases
    // still render inside `AppTheme` via the ThemeAddon below.
    return Widgetbook.material(
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
              name: 'Onboarding',
              children: [
                WidgetbookComponent(
                  name: 'Welcome',
                  useCases: [
                    WidgetbookUseCase(
                      name: 'Large',
                      builder: buildWelcomeLargeUseCase,
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
                  name: 'Primary / Medium',
                  builder: buildButtonPrimaryMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Primary / Small',
                  builder: buildButtonPrimarySmallUseCase,
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
                  name: 'Ghost / Medium',
                  builder: buildButtonGhostMediumUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Ghost / Small',
                  builder: buildButtonGhostSmallUseCase,
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
                  name: 'Purple',
                  builder: buildPrimitivesPurpleUseCase,
                ),
                WidgetbookUseCase(
                  name: 'Cyan',
                  builder: buildPrimitivesCyanUseCase,
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
          ],
        ),
      ],
    );
  }
}
