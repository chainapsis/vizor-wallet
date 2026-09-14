// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; imports of it are confined to
// `lib/widgetbook/` and `lib/widgetbook.dart`, which are not reachable from
// the production entry point `lib/main.dart`.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import 'gallery/accounts_settings_gallery.dart';
import 'gallery/address_book_gallery.dart';
import 'gallery/components_gallery.dart';
import 'gallery/onboarding_gallery.dart';
import 'gallery/scanner_gallery.dart';
import 'support/wb_compare_layouts.dart';
import 'support/wb_design_status.dart';

/// The Widgetbook navigation tree, shared by the app, the design-status
/// header counter, and the handoff generator.
///
/// Every leaf lives in a `gallery/<feature>_gallery.dart` list; this file only
/// names the folders. `homeActivityGalleryNodes` and
/// `accountsSettingsGalleryNodes` already carry their own feature folders, so
/// they are spread into `Screens` instead of being nested again.
final List<WidgetbookNode> widgetbookDirectories = [
  WidgetbookFolder(
    name: 'Screens',
    children: [
      WidgetbookFolder(name: 'Onboarding', children: onboardingGalleryNodes),
      WidgetbookFolder(name: 'Keystone', children: keystoneGalleryNodes),
      WidgetbookFolder(name: 'Scanning', children: scannerGalleryNodes),
      ...accountsSettingsGalleryNodes,
      WidgetbookFolder(name: 'Address book', children: addressBookGalleryNodes),
    ],
  ),
  WidgetbookFolder(name: 'Components', children: componentsGalleryNodes),
  WidgetbookFolder(name: 'Tokens', children: tokensGalleryNodes),
  WidgetbookFolder(name: 'Colors', children: colorsGalleryNodes),
];

Iterable<WidgetbookUseCase> widgetbookUseCases([
  List<WidgetbookNode>? roots,
]) sync* {
  for (final node in roots ?? widgetbookDirectories) {
    if (node is WidgetbookUseCase) {
      yield node;
    } else {
      final children = node.children;
      if (children != null) {
        yield* widgetbookUseCases(children);
      }
    }
  }
}

/// Top-level Widgetbook app for the Zcash design system.
///
/// The ThemeAddon wraps every use case in [AppTheme] with either
/// [AppThemeData.dark] or [AppThemeData.light], so the page chrome reacts to
/// the selected theme while individual swatches always show both dark and
/// light values side-by-side.
class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key, this.initialRoute = _initialRoute});

  static const _initialRoute = String.fromEnvironment(
    'VIZOR_WIDGETBOOK_INITIAL_ROUTE',
    defaultValue: '/',
  );

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    // `.material` instead of the default `Widgetbook()` because the default
    // `widgetsAppBuilder` in widgetbook 3.22.0 constructs a `WidgetsApp`
    // without a `pageRouteBuilder` and throws on first build. The MaterialApp
    // wrapper is only chrome for Widgetbook's own navigation — use cases
    // still render inside `AppTheme` via the ThemeAddon below.
    return Widgetbook.material(
      initialRoute: initialRoute,
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
        WbDesignStatusAddon(),
        // Centres every use case on the canvas: fixed-width mobile fixtures
        // otherwise sit top-left under the canvas's loose constraints, while
        // desktop pane frames centre themselves.
        AlignmentAddon(),
        // Innermost: addons wrap the use case outside-in, so the compare
        // canvas sits inside `AppTheme` (its captions read design tokens), and
        // the design-status chip and the alignment apply once to the pair
        // instead of twice. The `child` here is the workbench's own
        // constraint-loosening `Stack` around the use case, which is why each
        // pane loosens and centres its copy for itself.
        WbCompareLayoutsAddon(),
      ],
      directories: widgetbookDirectories,
    );
  }
}
