/// Which end of a swap uses a one-time Zcash address.
enum OneTimeAddressRole {
  /// The payout of a swap into ZEC.
  payout,

  /// The refund of a swap that sends ZEC.
  refund;

  String get label => switch (this) {
    payout => 'One-time address',
    refund => 'One-time refund address',
  };

  String get explanation => switch (this) {
    payout =>
      'A one-time Zcash address for this swap. Even a future quantum '
          "computer can't tie it to your wallet.",
    refund =>
      'If this swap is refunded, the ZEC comes back to a one-time Zcash '
          "address. Even a future quantum computer can't tie it to your "
          'wallet.',
  };
}
