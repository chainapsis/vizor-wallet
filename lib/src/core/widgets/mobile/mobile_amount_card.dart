/// The card a mobile amount is typed into, shared by Pay and Request ZEC.
library;

import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import 'mobile_surface_card.dart';

/// Pay's amount card: the mobile surface (ground fill and its soft lift) with
/// 28 corners and 16 inside, an optional [header] row, then the amount row
/// and the unit switch under it, 24 above and below them.
///
/// Pay puts "Paying in" and its asset picker in the header; Request ZEC has
/// no asset to pick and leaves it out. The card is at least [height] tall,
/// with the amount centred when there is no header, so it is the same card
/// on every page. Its minimum row heights keep the 1x geometry, while larger
/// text can grow the rows and card.
class MobileAmountCard extends StatelessWidget {
  const MobileAmountCard({
    required this.amount,
    required this.conversion,
    this.header,
    super.key,
  });

  static const cornerRadius = 28.0;
  static const headerHeight = 56.0;
  static const amountRowHeight = 56.0;
  static const conversionRowHeight = 20.0;

  /// The amount row and the unit switch with the room above and below them.
  static const _amountBlockHeight =
      AppSpacing.md * 2 + amountRowHeight + AppSpacing.s + conversionRowHeight;

  /// Pay's card height (240), with or without a header.
  static const height =
      AppSpacing.sm * 2 + headerHeight + AppSpacing.sm + _amountBlockHeight;

  /// The typed amount and its unit, centred in [amountRowHeight].
  final Widget amount;

  /// The unit switch under the amount (the other unit's value).
  final Widget conversion;

  /// The row above the amount, [headerHeight] tall. Null leaves it out.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      cornerRadius: cornerRadius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: height - AppSpacing.sm * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: header == null
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: headerHeight),
                child: Center(child: header),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              // Centred: the amount row spans the card, the unit switch takes
              // only its own width so its tap area hugs its text.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: amountRowHeight,
                    ),
                    child: Center(child: amount),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: conversionRowHeight,
                    ),
                    child: Center(child: conversion),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
