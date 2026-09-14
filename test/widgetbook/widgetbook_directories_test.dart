import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

Widget _stub(BuildContext context) => const SizedBox.shrink();

WidgetbookUseCase _useCase(String name) =>
    WidgetbookUseCase(name: name, builder: _stub);

void main() {
  group('widgetbookUseCases', () {
    test('yields every leaf depth-first, in tree order', () {
      final tree = <WidgetbookNode>[
        WidgetbookFolder(
          name: 'Screens',
          children: [
            WidgetbookComponent(
              name: 'Home',
              useCases: [_useCase('Empty'), _useCase('Funded')],
            ),
            WidgetbookFolder(
              name: 'Swap',
              children: [
                WidgetbookComponent(
                  name: 'Swap page',
                  useCases: [_useCase('Playground')],
                ),
              ],
            ),
          ],
        ),
        WidgetbookComponent(name: 'Tokens', useCases: [_useCase('All')]),
      ];

      expect(widgetbookUseCases(tree).map((useCase) => useCase.name).toList(), [
        'Empty',
        'Funded',
        'Playground',
        'All',
      ]);
    });

    test('skips folders and components that have no use cases', () {
      final tree = <WidgetbookNode>[
        WidgetbookFolder(name: 'Empty folder', children: const []),
        WidgetbookFolder(
          name: 'Screens',
          children: [
            WidgetbookComponent(name: 'Nothing', useCases: const []),
            WidgetbookComponent(name: 'Home', useCases: [_useCase('Empty')]),
          ],
        ),
      ];

      expect(widgetbookUseCases(tree).map((useCase) => useCase.name).toList(), [
        'Empty',
      ]);
    });

    test('a bare use case at the root is its own leaf', () {
      expect(widgetbookUseCases([_useCase('Loose')]).single.name, 'Loose');
    });
  });

  group('the real registry', () {
    test('main screens own their flows without sibling playgrounds', () {
      WidgetbookRoot(children: widgetbookDirectories);
      final paths = widgetbookUseCases().map((entry) => entry.path).toSet();
      for (final feature in ['send', 'receive', 'pay', 'swap', 'settings']) {
        final surface = feature == 'swap' ? 'swap-page' : '$feature-screen';
        expect(paths, contains('screens/$feature/$surface/screen'));
        expect(
          paths.where(
            (path) => path.startsWith('screens/$feature/$feature-flow/'),
          ),
          isEmpty,
        );
        expect(paths, isNot(contains('screens/$feature/$surface/playground')));
      }
      expect(paths, isNot(contains('screens/pay/pay-screen/wizard-shell')));
    });

    // Deliberately not a count: consolidation changes it every phase.
    test('has use cases and every leaf is named', () {
      final useCases = widgetbookUseCases().toList();

      expect(useCases, isNotEmpty);
      for (final useCase in useCases) {
        expect(useCase.name.trim(), isNotEmpty);
      }
    });

    test('no two use cases share a path', () {
      WidgetbookRoot(children: widgetbookDirectories);
      final paths = widgetbookUseCases().map((useCase) => useCase.path);

      expect(paths.toSet().length, paths.length);
    });

    test('no builder is registered under two paths', () {
      WidgetbookRoot(children: widgetbookDirectories);
      // One surface, one entry: the same builder under two paths means a
      // feature folder is duplicating another's surface.
      final pathsByBuilder = <WidgetBuilder, List<String>>{};
      for (final useCase in widgetbookUseCases()) {
        pathsByBuilder.putIfAbsent(useCase.builder, () => []).add(useCase.path);
      }
      final duplicates = pathsByBuilder.values.where(
        (paths) => paths.length > 1,
      );

      expect(duplicates, isEmpty, reason: 'duplicated builders: $duplicates');
    });

    test('onboarding small surfaces live under Components', () {
      WidgetbookRoot(children: widgetbookDirectories);
      final paths = widgetbookUseCases().map((useCase) => useCase.path).toSet();
      expect(
        paths,
        contains('screens/onboarding/components/seed-card/playground'),
      );
      expect(
        paths,
        contains('screens/onboarding/components/passcode-field/playground'),
      );
      expect(
        paths,
        contains('screens/onboarding/components/onboarding-sidebar/playground'),
      );
      expect(
        paths,
        contains('screens/onboarding/modals/birthday-calendar/playground'),
      );
      expect(
        paths,
        contains(
          'screens/onboarding/modals/mobile-screenshot-warning-sheet/playground',
        ),
      );
    });

    test(
      'feature folders separate full screens from their building blocks',
      () {
        WidgetbookRoot(children: widgetbookDirectories);
        final paths = widgetbookUseCases().map((entry) => entry.path).toSet();
        for (final path in const [
          'screens/onboarding/welcome/playground',
          'screens/send/send-review-screen/playground',
          'screens/send/send-status-screen/playground',
          'screens/settings/endpoint/playground',
          'screens/settings/explorer/playground',
          'screens/send/components/send-compose/playground',
          'screens/swap/components/asset-icon/playground',
          'screens/pay/components/pay-wizard-stepper/playground',
          'screens/address-book/components/network-icon/playground',
          'screens/pay/modals/pay-modals/asset-selector',
          'screens/swap/modals/swap-modals/address-editor',
        ]) {
          expect(paths, contains(path), reason: 'misclassified surface: $path');
        }
      },
    );
  });
}
