// Dev-only simulator entry point; production main.dart never imports it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/features/activity/widgets/activity_feed.dart';
import 'figma_compare_app.dart';
import 'figma_compare_capture.dart';
import 'figma_compare_scenarios.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(kAppFormFactor == AppFormFactor.mobile);
  final root = Directory('${Directory.systemTemp.path}/home-resolution-review')
    ..createSync(recursive: true);
  final configuration = File('${root.path}/config.json');
  final config = configuration.existsSync()
      ? jsonDecode(configuration.readAsStringSync()) as Map<String, dynamic>
      : const <String, dynamic>{};
  final kind = config['kind'] as String? ?? 'transactions';
  final theme = config['theme'] == 'light' ? ThemeMode.light : ThemeMode.dark;
  final output = Directory('${root.path}/$kind')..createSync(recursive: true);
  final errors = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    original?.call(details);
  };
  final boundary = GlobalKey();
  runApp(
    FigmaCompareApp(
      scenario: figmaCompareScenarios.firstWhere(
        (scenario) => scenario.id == 'mobile-home-ten-$kind',
      ),
      themeMode: theme,
      captureBoundaryKey: boundary,
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  await WidgetsBinding.instance.endOfFrame;

  final scrollable = _elements()
      .whereType<StatefulElement>()
      .map((element) => element.state)
      .whereType<ScrollableState>()
      .first;
  final capture = FigmaCompareCaptureController(captureBoundaryKey: boundary);
  for (final position in ['top', 'middle', 'bottom']) {
    final fraction = switch (position) {
      'middle' => 0.5,
      'bottom' => 1.0,
      _ => 0.0,
    };
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent * fraction);
    await capture.capture(
      contentOutputPath: '${output.path}/$position.content.png',
      pixelRatio: 1,
      settleDelay: const Duration(milliseconds: 500),
    );
    final elements = _elements();
    final groups = elements
        .map((element) => element.widget)
        .whereType<ActivityFeedRowGroup>()
        .toList();
    final rows = elements.where(
      (element) =>
          element.widget.key is ValueKey<String> &&
          (element.widget.key! as ValueKey<String>).value.startsWith(
            'mobile_home_activity_row_',
          ),
    );
    final tabBar = elements.firstWhere(
      (element) => element.widget is AppMobileTabBar,
    );
    final media = MediaQuery.of(boundary.currentContext!);
    final seeAll =
        elements
                .firstWhere(
                  (element) =>
                      element.widget is Text &&
                      (element.widget as Text).data == 'See all',
                )
                .findRenderObject()!
            as RenderParagraph;
    File('${output.path}/$position.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'viewport': [media.size.width, media.size.height],
        'padding': [media.padding.top, media.padding.bottom],
        'viewPadding': [media.viewPadding.top, media.viewPadding.bottom],
        'textScale': media.textScaler.scale(16) / 16,
        'theme': theme.name,
        'kind': kind,
        'position': position,
        'scrollPixels': scrollable.position.pixels,
        'scrollExtent': scrollable.position.maxScrollExtent,
        'parentCount': groups.length,
        'childCount': groups.fold<int>(
          0,
          (count, group) => count + group.row.childRows.length,
        ),
        'seeAll': {
          'height': seeAll.size.height,
          'intrinsicHeight': seeAll.getMaxIntrinsicHeight(seeAll.size.width),
        },
        'tabBar': _rect(tabBar),
        'rows': [
          for (final row in rows)
            {'key': row.widget.key.toString(), 'rect': _rect(row)},
        ],
        'errors': errors,
      }),
    );
    debugPrint('HOME_REVIEW_READY ${output.path}/$position.json');
    final acknowledgement = File('${output.path}/$position.ack');
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!acknowledgement.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'No simulator screenshot acknowledgement for $position',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  FlutterError.onError = original;
  exit(0);
}

List<Element> _elements() {
  final result = <Element>[];
  void visit(Element element) {
    result.add(element);
    element.visitChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return result;
}

List<double> _rect(Element element) {
  final render = element.findRenderObject()! as RenderBox;
  final offset = render.localToGlobal(Offset.zero);
  return [
    offset.dx,
    offset.dy,
    offset.dx + render.size.width,
    offset.dy + render.size.height,
  ];
}
