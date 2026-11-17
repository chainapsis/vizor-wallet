import 'package:flutter/material.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_address_edit_modal.dart';

/// Real address editor and shared sheet chrome without wallet or network state.
Widget buildMobileSwapAddressCapture(BuildContext context) =>
    _addressCapture(context, SwapDirection.zecToExternal);

Widget buildMobileSwapRefundAddressCapture(BuildContext context) =>
    _addressCapture(context, SwapDirection.externalToZec);

Widget _addressCapture(BuildContext context, SwapDirection direction) =>
    Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: false,
          body: MobileModalOverlay(
            background: ColoredBox(color: context.colors.background.window),
            child: MobileSwapAddressEditModal(
              state: SwapState(
                direction: direction,
                amountText: '',
                receiveAmountText: '',
                destinationText: '',
                externalAsset: SwapAsset.usdc,
                reviewVisible: false,
                intents: const [],
              ),
              contacts: const [
                AddressBookContact(
                  id: 'fixture',
                  label: 'Treasury',
                  network: AddressBookNetwork.ethereum,
                  address: '0x52908400098527886e0f7030069857d2e4169ee7',
                  profilePictureId: 'default',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ],
              onSubmitted: (_, _) {},
              onScan: (_, _) {},
              onOpenContacts: (_, _) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
