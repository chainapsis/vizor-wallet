import 'package:flutter/widgets.dart';

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
    return SizedBox.square(
      dimension: size,
      child: ClipOval(child: Image.asset(network.assetPath, fit: BoxFit.cover)),
    );
  }
}
