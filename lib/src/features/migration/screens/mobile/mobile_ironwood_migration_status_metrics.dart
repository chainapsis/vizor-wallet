part of 'mobile_ironwood_migration_flow_screen.dart';

BigInt _mobilePlanTotalZatoshi(rust_sync.OrchardMigrationPrivatePlan plan) {
  if (plan.totalMigratableZatoshi > BigInt.zero) {
    return plan.totalMigratableZatoshi;
  }
  return plan.scheduledTransfers.fold<BigInt>(
    BigInt.zero,
    (sum, transfer) => sum + transfer.valueZatoshi,
  );
}

List<double> _mobileStatusRailSegmentWidths({
  required double available,
  required List<BigInt> values,
}) {
  final count = values.length;
  if (count <= 0) return const [];
  final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
  if (count > 6) {
    if (total <= BigInt.zero) return List<double>.filled(count, 12);
    return [
      for (final value in values)
        math.max(12, available * value.toDouble() / total.toDouble()),
    ];
  }

  final gaps = math.max(0, count - 1) * _mobileMigrationPlanBarGap;
  final usable = math.max(0.0, available - gaps);
  if (usable <= 0) return List<double>.filled(count, 0);
  if (total <= BigInt.zero) return List<double>.filled(count, usable / count);

  const minimumWidth = 8.0;
  final doubleTotal = total.toDouble();
  final widths = [
    for (final value in values)
      math.max(minimumWidth, usable * value.toDouble() / doubleTotal),
  ];
  final widthTotal = widths.fold<double>(0, (sum, width) => sum + width);
  if (widthTotal <= usable) return widths;
  final scale = usable / widthTotal;
  return [for (final width in widths) width * scale];
}
