String ledgerZcashAppName(String networkName) => 'Zcash';

String ledgerZcashAppOpenInstruction(String networkName) {
  return 'Open the ${ledgerZcashAppName(networkName)} app';
}

String ledgerZcashAppOpenErrorInstruction(String networkName) {
  return '${ledgerZcashAppOpenInstruction(networkName)} on your Ledger.';
}
