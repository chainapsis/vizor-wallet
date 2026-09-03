/// Shared vocabulary for the Gift Card list surfaces.
///
/// The desktop pane and the mobile screen render the same two tabs over the
/// same created/received sections, so the tab enum and the section grouping
/// live here rather than in either form factor's view file. `AGENTS.md` keeps
/// app code on one selector per concept; a mobile-only copy of these types
/// would let the two lanes drift apart silently.
library;

import 'package:flutter/widgets.dart';

enum PaymentLinkCardsTab { created, received }

/// A labelled group of Gift Card rows.
///
/// The rows themselves are form-factor specific widgets — this only carries
/// the heading the list renders above them.
class PaymentLinkCardsSection {
  const PaymentLinkCardsSection({required this.label, required this.cards});

  final String label;
  final List<Widget> cards;
}
