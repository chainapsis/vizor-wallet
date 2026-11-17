import 'package:flutter/widgets.dart';

import '../../../../core/widgets/liquid_metal.dart';
import '../../../../core/widgets/svg_shape_image.dart';

/// The top of a transaction record: the transaction type's icon, the same
/// one its activity row shows (a paper plane for a send, an arrow down for a
/// receive, the shield for a shielding), cast in the liquid metal of the
/// NU7 announcement.
///
/// Decorative: the title and status below already say what the record is.
class TransactionTypeHero extends StatelessWidget {
  const TransactionTypeHero({required this.iconName, super.key});

  /// An icon name from `AppIcons`, drawn from `assets/icons/<name>.svg`.
  final String iconName;

  static const size = 128.0;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      key: const ValueKey('mobile_tx_type_hero'),
      dimension: size,
      child: LiquidMetal(
        image: SvgShapeImage('assets/icons/$iconName.svg'),
        // Only the shape shows; the page shows through around it.
        colorBack: const Color(0x00000000),
        softness: 1,
        scale: 1,
      ),
    ),
  );
}
