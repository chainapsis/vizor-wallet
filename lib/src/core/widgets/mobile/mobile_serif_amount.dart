/// The large serif amount of the mobile Home balance card, shared with the
/// pages that show an amount the same way (the Request ZEC QR step).
library;

import 'package:flutter/widgets.dart';

/// The amount: Young Serif 40 / 44 with tabular figures.
const kMobileSerifAmountStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w400,
  fontSize: 40,
  height: 44 / 40,
  letterSpacing: -1.35,
  fontFeatures: [FontFeature.enable('case'), FontFeature.tabularFigures()],
);

/// The ticker beside [kMobileSerifAmountStyle]: Young Serif 28 / 31.
const kMobileSerifTickerStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w400,
  fontSize: 28,
  height: 31 / 28,
  letterSpacing: -1.35,
  fontFeatures: [FontFeature.enable('case')],
);
