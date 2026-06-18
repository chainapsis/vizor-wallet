import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../models/address_book_contact.dart';

class AddressBookNetworkIcon extends StatelessWidget {
  const AddressBookNetworkIcon({
    required this.network,
    required this.size,
    super.key,
  });

  final AddressBookNetwork network;
  final double size;

  @override
  Widget build(BuildContext context) {
    // All networks (Zcash included) render their standard asset logo in a
    // raised circle — no special branded crimson treatment for Zcash.
    final padding = size <= 16 ? 0.0 : 3.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Image.asset(network.assetPath, fit: BoxFit.cover),
      ),
    );
  }
}
