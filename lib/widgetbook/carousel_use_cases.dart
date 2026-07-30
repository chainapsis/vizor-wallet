// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_carousel.dart';
import '../src/core/widgets/app_icon.dart';

const _historyTile = Color(0xFF9667E2);
const _walletTile = Color(0xFF00A460);
const _helmetTile = Color(0xFFB90A4A);
const _helmetAsset =
    'assets/illustrations/ironwood_migration_expect_running.png';

const _preparationItems = [
  AppCarouselItem.icon(
    message:
        'Once preparation finishes, your migration will begin automatically '
        'after a long intentional delay.',
    tileColor: _historyTile,
    icon: AppIcons.history,
    iconSize: 18,
  ),
  AppCarouselItem.icon(
    message:
        'We’re organizing your balance into common-sized parts. This makes '
        'your migration harder to link.',
    tileColor: _walletTile,
    icon: AppIcons.wallet,
  ),
  AppCarouselItem.icon(
    message:
        'We may have to do multiple rounds of note splitting depending on '
        'your balance.',
    tileColor: _helmetTile,
    icon: AppIcons.migrationSplit,
  ),
];

const _migrationItems = [
  AppCarouselItem.icon(
    message:
        'You can close Vizor anytime. Migration will pause, and you can '
        'restart it when you return.',
    tileColor: _historyTile,
    icon: AppIcons.pause,
  ),
  AppCarouselItem.icon(
    message:
        'Each Zcash block takes about 75 seconds to create, but timing can '
        'vary with network conditions.',
    tileColor: _walletTile,
    icon: AppIcons.migrationTimer,
    iconSize: 24,
  ),
  AppCarouselItem.image(
    message:
        'Keep Vizor running and the migration will automatically run in the '
        'background.',
    tileColor: _helmetTile,
    imageAsset: _helmetAsset,
  ),
];

Widget buildCarouselPreparationInteractiveUseCase(BuildContext context) =>
    _CarouselPreview(
      items: _preparationItems,
      semanticLabel: 'Migration preparation information',
    );

Widget buildCarouselPreparationCardOneUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _preparationItems,
      initialPage: 0,
      autoplay: false,
      semanticLabel: 'Migration preparation information',
    );

Widget buildCarouselPreparationCardTwoUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _preparationItems,
      initialPage: 1,
      autoplay: false,
      semanticLabel: 'Migration preparation information',
    );

Widget buildCarouselPreparationCardThreeUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _preparationItems,
      initialPage: 2,
      autoplay: false,
      semanticLabel: 'Migration preparation information',
    );

Widget buildCarouselMigrationInteractiveUseCase(BuildContext context) =>
    _CarouselPreview(
      items: _migrationItems,
      semanticLabel: 'Migration information',
    );

Widget buildCarouselMigrationCardOneUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _migrationItems,
      initialPage: 0,
      autoplay: false,
      semanticLabel: 'Migration information',
    );

Widget buildCarouselMigrationCardTwoUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _migrationItems,
      initialPage: 1,
      autoplay: false,
      semanticLabel: 'Migration information',
    );

Widget buildCarouselMigrationCardThreeUseCase(BuildContext context) =>
    const _CarouselPreview(
      items: _migrationItems,
      initialPage: 2,
      autoplay: false,
      semanticLabel: 'Migration information',
    );

class _CarouselPreview extends StatelessWidget {
  const _CarouselPreview({
    required this.items,
    required this.semanticLabel,
    this.initialPage = 0,
    this.autoplay = true,
  });

  final List<AppCarouselItem> items;
  final String semanticLabel;
  final int initialPage;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: AppCarousel(
          items: items,
          initialPage: initialPage,
          autoplay: autoplay,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
