import 'package:url_launcher/url_launcher.dart';

import 'network_config.dart';
import 'rpc_endpoint_config.dart';

enum ZcashExplorerTxidOrder { protocol, display }

typedef ZcashExplorerLauncher = Future<bool> Function(Uri uri);

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');

Uri zcashExplorerTransactionUri({
  required String networkName,
  required String txidHex,
  required ZcashExplorerTxidOrder txidOrder,
}) {
  final network = zcashNetworkFromName(networkName);
  final host = switch (network) {
    ZcashNetwork.mainnet => 'mainnet.zcashexplorer.app',
    ZcashNetwork.testnet => 'testnet.zcashexplorer.app',
  };
  return Uri.https(
    host,
    '/transactions/${_explorerTxidHex(txidHex, txidOrder)}',
  );
}

String _explorerTxidHex(String txidHex, ZcashExplorerTxidOrder txidOrder) {
  final normalized = txidHex.trim().toLowerCase();
  return switch (txidOrder) {
    ZcashExplorerTxidOrder.display => normalized,
    ZcashExplorerTxidOrder.protocol => _protocolOrderToDisplayTxidHex(
      normalized,
    ),
  };
}

String _protocolOrderToDisplayTxidHex(String normalizedTxidHex) {
  if (!_txidHexPattern.hasMatch(normalizedTxidHex)) {
    return normalizedTxidHex;
  }

  // Wallet DB txids are protocol-order bytes; explorers use byte-reversed text.
  final bytes = <String>[];
  for (var i = 0; i < normalizedTxidHex.length; i += 2) {
    bytes.add(normalizedTxidHex.substring(i, i + 2));
  }
  return bytes.reversed.join();
}

Future<bool> launchZcashExplorerTransaction({
  required String networkName,
  required String txidHex,
  required ZcashExplorerTxidOrder txidOrder,
  ZcashExplorerLauncher? launcher,
}) async {
  final uri = zcashExplorerTransactionUri(
    networkName: networkName,
    txidHex: txidHex,
    txidOrder: txidOrder,
  );
  try {
    return await (launcher ?? _launchExternalUrl)(uri);
  } on Exception {
    return false;
  }
}

Future<bool> _launchExternalUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
