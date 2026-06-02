import '../../core/formatting/number_format.dart';
import '../../core/formatting/zec_amount.dart';

/// Formats raw zatoshi voting power as e.g. `12.5 ZEC`.
///
/// Delegates to [ZecAmount] for the decimal formatting. The denomination is
/// kept as the literal `ZEC` to preserve existing output across networks.
String formatVotingPower(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).pretty(denomStyle: ZecDenomStyle.upper, denomination: 'ZEC').toString();
}

String formatBlockHeight(int height) => formatGroupedInteger(height);
